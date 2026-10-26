# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Start the LiteLLM gateway and create one virtual key per agent.

1. Render /app/config.yaml from the template and the task's environment variables.
2. Start the LiteLLM proxy on port 4000 and wait until it is healthy.
3. Create (or update) the virtual key of each agent, with the MCP servers, tools and agents it may use. The key
   values come from AWS Secrets Manager (injected by Amazon ECS), so the agents read the same values.
"""
import json
import os
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

PORT = 4000
BASE = f"http://127.0.0.1:{PORT}"

# Virtual key permissions per caller: agent-ecs gets every tool, agent-runtime every tool except creating employees
# in the directory, and the triage agent only the model (it calls the gateway for its own model calls).
KEYS = {
    "agent-ecs": {
        "secret_env": "AGENT_ECS_KEY",
        "models": ["helpdesk-llm"],
        "max_budget": float(os.environ.get("AGENT_ECS_BUDGET", "5")),
        "object_permission": {"mcp_servers": ["tickets", "directory"], "agents": ["triage"]},
    },
    "agent-runtime": {
        "secret_env": "AGENT_RUNTIME_KEY",
        "models": ["helpdesk-llm"],
        "max_budget": float(os.environ.get("AGENT_RUNTIME_BUDGET", "5")),
        "object_permission": {
            "mcp_servers": ["tickets", "directory"],
            # Tool names as LiteLLM lists them: the OpenAPI operationIds in lower case (getEmployee -> getemployee)
            "mcp_tool_permissions": {"directory": ["getemployee", "listemployees"]},
            "agents": ["triage"],
        },
    },
    "agent-triage": {
        "secret_env": "AGENT_TRIAGE_KEY",
        "models": ["helpdesk-llm"],
        "max_budget": float(os.environ.get("AGENT_TRIAGE_BUDGET", "5")),
        "object_permission": {"mcp_servers": ["no-mcp-servers"]},
    },
}


def render_config():
    hosts = sorted({urlparse(os.environ[v]).hostname for v in ("TICKETS_URL", "DIRECTORY_URL", "TRIAGE_URL")})
    values = dict(os.environ, ALLOWED_HOSTS=json.dumps(hosts))
    with open("/app/config.template.yaml", encoding="utf-8") as template:
        rendered = string.Template(template.read()).substitute(values)
    with open("/app/config.yaml", "w", encoding="utf-8") as config:
        config.write(rendered)


def call(method, path, body=None):
    request = urllib.request.Request(
        BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {os.environ['LITELLM_MASTER_KEY']}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()
    except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
        return 0, str(error)


def agent_ids():
    """Agent name -> agent ID. Key permissions name agents by ID, and LiteLLM assigns the IDs of config agents."""
    status, reply = call("GET", "/v1/agents")
    agents = json.loads(reply) if status == 200 else []
    agents = agents.get("agents", []) if isinstance(agents, dict) else agents
    return {agent["agent_name"]: agent["agent_id"] for agent in agents}


def ensure_keys():
    ids = agent_ids()
    for alias, spec in KEYS.items():
        value = os.environ[spec["secret_env"]]
        permission = dict(spec["object_permission"])
        if "agents" in permission:
            permission["agents"] = [ids.get(name, name) for name in permission["agents"]]
        body = {
            "key": value if value.startswith("sk-") else f"sk-{value}",  # LiteLLM keys start with sk-
            "key_alias": alias,
            "models": spec["models"],
            "max_budget": spec["max_budget"],
            "object_permission": permission,
        }
        status, reply = call("POST", "/key/generate", body)
        if status >= 400:  # the key already exists (task restart): apply the current permissions instead
            status, reply = call("POST", "/key/update", body)
        # Log the outcome only: a successful reply contains the key itself
        print(json.dumps({"key_alias": alias, "status": status, **({"error": reply[:300]} if status >= 400 else {})}), flush=True)


def main():
    master_key = os.environ["LITELLM_MASTER_KEY"]
    if not master_key.startswith("sk-"):  # LiteLLM requires the master key to start with sk-
        os.environ["LITELLM_MASTER_KEY"] = f"sk-{master_key}"
    render_config()
    proxy = subprocess.Popen(["litellm", "--config", "/app/config.yaml", "--port", str(PORT), "--host", "0.0.0.0"])
    for _ in range(120):
        if proxy.poll() is not None:
            sys.exit(proxy.returncode)
        if call("GET", "/health/readiness")[0] == 200:
            break
        time.sleep(5)
    ensure_keys()
    sys.exit(proxy.wait())


if __name__ == "__main__":
    main()
