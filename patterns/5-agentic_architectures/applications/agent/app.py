# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Helpdesk agent (Strands Agents), the consumer in every agentic pattern.

The same container image runs as a self-hosted agent on Amazon ECS (agent-ecs) and on Amazon Bedrock AgentCore
Runtime (agent-runtime). It serves the AgentCore Runtime HTTP contract (POST /invocations, GET /ping on port 8080).

How the agent reaches its tools, API, peer agents and LLM depends on CONNECTIVITY_MODE:

- direct: each MCP server, API and agent is a VPC Lattice service, called with SigV4 (vpc-lattice-svcs).
- self_hosted_gateway: everything goes through the AI gateway (a VPC Lattice service), with the agent's virtual key.
  The agent finds the gateway's endpoints (tools, agents and model) in AWS Agent Registry on every invocation.
- agentcore_gateway: everything goes through an Amazon Bedrock AgentCore Gateway, signed with the agent's IAM role
  (SigV4, bedrock-agentcore). The agent finds the gateway's endpoints in AWS Agent Registry on every invocation.

An invocation payload is either {"prompt": "..."} (the LLM decides which tools to call) or a deterministic test
action such as {"action": "call_tool", ...}. The actions return the HTTP status of every upstream call, so the
pattern tests can show where a request was allowed or denied without depending on the model's choices.
"""
import json
import logging
import os
import uuid
from typing import Optional

import boto3
import httpx
import openai
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent, tool
from strands.models import BedrockModel
from strands.models.openai import OpenAIModel
from strands.tools.mcp import MCPClient

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("helpdesk-agent")

REGION = os.environ.get("AWS_REGION", "eu-west-1")
MODE = os.environ.get("CONNECTIVITY_MODE", "direct")
AGENT_NAME = os.environ.get("AGENT_NAME", "agent")
MODEL_ID = os.environ.get("MODEL_ID", "eu.amazon.nova-pro-v1:0")
SYSTEM_PROMPT = (
    "You are an IT helpdesk assistant. When an employee reports an issue, look up the employee in the directory, "
    "open a ticket for their issue, ask the triage agent for a priority when it is available, and answer with the "
    "ticket identifier. For other requests, use only the tools the request needs. If a tool returns an HTTP error "
    "such as 403, say which call was denied instead of retrying."
)
# In direct mode the agent has no backends configured: it finds them in AWS Agent Registry on every invocation
DISCOVERY_PROMPT = (
    " You don't know the helpdesk services in advance: first call discover_services to find the MCP servers, REST "
    "APIs and agents available in AWS Agent Registry, then call them with call_mcp_tool, call_rest_api and "
    "send_agent_message, using the service names, tools and operations discover_services returns."
)

session = boto3.session.Session(region_name=REGION)
app = BedrockAgentCoreApp()


# ---------- SIGV4 FOR HTTPX ----------
class SigV4HttpxAuth(httpx.Auth):
    """Sign httpx requests with SigV4.

    VPC Lattice (vpc-lattice-svcs) does not support payload signing, so it uses UNSIGNED-PAYLOAD. AgentCore Gateway
    (bedrock-agentcore) signs the body. Only host, content-type and x-amz-* headers are signed, so headers added
    later by the HTTP stack don't invalidate the signature.
    """

    requires_request_body = True

    def __init__(self, service, unsigned_payload):
        self.service = service
        self.unsigned_payload = unsigned_payload

    def auth_flow(self, request):
        headers = {"host": request.url.netloc.decode()}
        if "content-type" in request.headers:
            headers["content-type"] = request.headers["content-type"]
        if self.unsigned_payload:
            headers["x-amz-content-sha256"] = "UNSIGNED-PAYLOAD"
        aws_request = AWSRequest(method=request.method, url=str(request.url), data=request.content, headers=headers)
        aws_request.context["payload_signing_enabled"] = not self.unsigned_payload
        SigV4Auth(session.get_credentials().get_frozen_credentials(), self.service, REGION).add_auth(aws_request)
        for name, value in aws_request.headers.items():
            request.headers[name] = value
        yield request


LATTICE_AUTH = SigV4HttpxAuth("vpc-lattice-svcs", unsigned_payload=True)
GATEWAY_AUTH = SigV4HttpxAuth("bedrock-agentcore", unsigned_payload=False)
# Signing for every call to a backend or gateway: AgentCore Gateway, or VPC Lattice in the other modes
AUTH = GATEWAY_AUTH if MODE == "agentcore_gateway" else LATTICE_AUTH
# The modes where the agent reaches everything through a gateway described in AWS Agent Registry
GATEWAY_MODES = ("self_hosted_gateway", "agentcore_gateway")


def _litellm_headers():
    """LiteLLM virtual key of this agent (read from AWS Secrets Manager), sent in x-litellm-api-key."""
    secret_arn = os.environ.get("LITELLM_API_KEY_SECRET_ARN")
    if not secret_arn:
        return {}
    if not hasattr(_litellm_headers, "key"):
        value = session.client("secretsmanager").get_secret_value(SecretId=secret_arn)["SecretString"]
        _litellm_headers.key = value if value.startswith("sk-") else f"sk-{value}"  # LiteLLM keys start with sk-
    return {"x-litellm-api-key": f"Bearer {_litellm_headers.key}"}


# ---------- SERVICE CATALOG (AWS AGENT REGISTRY) ----------
def load_catalog():
    """Read every approved record in the registry and return {record name: {type, description, url, ...}}.

    Lists the discoverable records, then reads their descriptors (MCP server.json and tools, the REST API's custom
    descriptor, the A2A agent card) through the centralized agent-registry endpoint.
    """
    client = session.client("agent-registry", endpoint_url=os.environ.get("REGISTRY_ENDPOINT_URL") or None)
    registry_id = os.environ["REGISTRY_ID"]
    record_ids, token = [], None
    while True:
        page = client.list_discoverable_registry_records(registryId=registry_id, **({"nextToken": token} if token else {}))
        record_ids += [r["recordId"] for r in page["registryRecords"]]
        token = page.get("nextToken")
        if not token:
            break
    if not record_ids:
        return {}
    records = client.batch_get_discoverable_registry_record(
        entries=[{"registryId": registry_id, "recordIds": record_ids}])["registryRecords"]
    catalog = {}
    for record in records:
        descriptors = record.get("descriptors", {})
        if "mcpServer" in descriptors:
            server = json.loads(descriptors["mcpServer"]["data"])
            tools = json.loads(descriptors["mcpServer"].get("additionalData", {}).get("tools", {}).get("data", "{}"))
            entry = {"type": "MCP server", "url": server["remotes"][0]["url"],
                     "tools": [{k: t.get(k) for k in ("name", "description", "inputSchema")} for t in tools.get("tools", [])]}
        elif "a2aAgentCard" in descriptors:
            card = json.loads(descriptors["a2aAgentCard"]["data"])
            entry = {"type": "A2A agent", "url": card["url"],
                     "skills": [skill.get("description") for skill in card.get("skills", [])]}
        elif "custom" in descriptors and json.loads(descriptors["custom"]["data"]).get("protocol") == "openapi":
            api = json.loads(descriptors["custom"]["data"])
            entry = {"type": "REST API", "url": api["baseUrl"],
                     "operations": [f"{o['method']} {o['path']}" for o in api.get("operations", [])]}
        elif "custom" in descriptors and json.loads(descriptors["custom"]["data"]).get("protocol") in ("openai", "anthropic"):
            llm = json.loads(descriptors["custom"]["data"])
            entry = {"type": "LLM", "url": llm["baseUrl"], "models": llm.get("models", []), "protocol": llm["protocol"]}
        else:
            continue
        catalog[record["name"]] = {"description": record.get("description"), **entry}
    return catalog


def _catalog_url(kind, name=None):
    """URL of a discovered service of one type (the named one, or the first one when no name is given)."""
    for service, entry in load_catalog().items():
        if entry["type"] == kind and name in (None, service):
            return service, entry["url"]
    raise LookupError(f"No {kind} found in AWS Agent Registry" + (f" with the name {name}" if name else ""))


def mcp_endpoints(catalog=None):
    """MCP servers this agent uses, found in the registry (the backends themselves, or the gateway's MCP endpoint):
    list of (name, url, auth, headers)."""
    return [(name, e["url"], AUTH, _litellm_headers())
            for name, e in (catalog or load_catalog()).items() if e["type"] == "MCP server"]


# ---------- RAW CALLS (DETERMINISTIC TEST ACTIONS) ----------
def _jsonrpc_result(response):
    """Parse a JSON-RPC reply sent as application/json or as a text/event-stream."""
    if "text/event-stream" in response.headers.get("content-type", ""):
        for line in response.text.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:])
        return None
    return response.json() if response.content else None


def mcp_request(url, auth, headers, method, params=None):
    """Initialize an MCP session, send one request, and return the HTTP status and JSON-RPC reply."""
    base = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream", **headers}
    with httpx.Client(auth=auth, timeout=60) as client:
        init = client.post(url, headers=base, json={
            "jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": AGENT_NAME, "version": "1.0.0"}},
        })
        if init.status_code >= 400:
            return {"step": "initialize", "status": init.status_code, "body": init.text[:500]}
        session_headers = dict(base)
        if init.headers.get("mcp-session-id"):
            session_headers["Mcp-Session-Id"] = init.headers["mcp-session-id"]
        protocol = (_jsonrpc_result(init) or {}).get("result", {}).get("protocolVersion")
        if protocol:
            session_headers["MCP-Protocol-Version"] = protocol
        client.post(url, headers=session_headers, json={"jsonrpc": "2.0", "method": "notifications/initialized"})
        reply = client.post(url, headers=session_headers, json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        body = _jsonrpc_result(reply) if reply.status_code < 400 else reply.text[:500]
        return {"step": method, "status": reply.status_code, "body": body}


def a2a_send(text, url=None):
    """Send one A2A message/send request (by default, to the first agent in the registry) and return the HTTP status
    and the agent's text reply."""
    url = url or _catalog_url("A2A agent")[1]
    auth, headers = AUTH, _litellm_headers()
    payload = {
        "jsonrpc": "2.0", "id": str(uuid.uuid4()), "method": "message/send",
        "params": {"message": {"kind": "message", "role": "user", "messageId": str(uuid.uuid4()),
                               "parts": [{"kind": "text", "text": text}]}},
    }
    with httpx.Client(auth=auth, timeout=120) as client:
        reply = client.post(url, json=payload, headers={"Content-Type": "application/json", **headers})
    if reply.status_code >= 400:
        return {"status": reply.status_code, "body": reply.text[:500]}
    result = (_jsonrpc_result(reply) or {}).get("result", {})
    parts = result.get("parts") or [p for a in result.get("artifacts", []) for p in a.get("parts", [])]
    return {"status": reply.status_code, "task_state": result.get("status", {}).get("state"),
            "reply": " ".join(p.get("text", "") for p in parts)}


def directory_request(method, path, body=None, base_url=None):
    """Call a REST API directly through VPC Lattice (direct mode only); by default, the first one in the registry."""
    url = (base_url or _catalog_url("REST API")[1]).rstrip("/") + path
    with httpx.Client(auth=LATTICE_AUTH, timeout=30) as client:
        reply = client.request(method, url, json=body, headers={"Content-Type": "application/json"})
    try:
        payload = reply.json()
    except ValueError:
        payload = reply.text[:500]
    return {"status": reply.status_code, "body": payload}


def discover(query):
    """Search the AWS Agent Registry for approved records (through its centralized endpoint)."""
    client = session.client("agent-registry", endpoint_url=os.environ.get("REGISTRY_ENDPOINT_URL") or None)
    records = client.search_discoverable_registry_records(
        searchQuery=query, registryIds=[os.environ["REGISTRY_ID"]], maxResults=10
    )["registryRecords"]
    return [{"name": r["name"], "type": r["recordType"], "description": r.get("description"),
             "descriptors": r.get("descriptors")} for r in records]


def invoke_peer_agent(text):
    """Invoke the peer agent hosted on AgentCore Runtime (InvokeAgentRuntime through the bedrock-agentcore endpoint)."""
    client = session.client("bedrock-agentcore")
    reply = client.invoke_agent_runtime(
        agentRuntimeArn=os.environ["PEER_AGENT_RUNTIME_ARN"],
        runtimeSessionId=str(uuid.uuid4()) + "-" + uuid.uuid4().hex[:8],
        payload=json.dumps({"prompt": text}).encode(),
    )
    return {"status": reply["ResponseMetadata"]["HTTPStatusCode"], "body": json.loads(reply["response"].read())}


# ---------- LLM-DRIVEN MODE ----------
# Direct mode: the services the model discovered in this invocation, so it can only call what the registry lists
DISCOVERED = {}


def _discovered(service, kind):
    entry = DISCOVERED.get(service)
    if not entry or entry["type"] != kind:
        raise ValueError(f"{service} is not a {kind} returned by discover_services; call discover_services first")
    return entry["url"]


@tool
def discover_services() -> str:
    """Find the helpdesk MCP servers, REST APIs and A2A agents in AWS Agent Registry, with their tools,
    operations and skills. Call this before any other helpdesk tool."""
    DISCOVERED.clear()
    DISCOVERED.update(load_catalog())
    return json.dumps({"services": DISCOVERED})


@tool
def call_mcp_tool(service: str, tool_name: str, arguments: dict) -> str:
    """Call a tool on an MCP server that discover_services returned (service = its name)."""
    url = _discovered(service, "MCP server")
    return json.dumps(mcp_request(url, LATTICE_AUTH, _litellm_headers(), "tools/call", {"name": tool_name, "arguments": arguments}))


@tool
def call_rest_api(service: str, method: str, path: str, body: Optional[dict] = None) -> str:
    """Call an operation of a REST API that discover_services returned (method and path from its operations,
    with path parameters filled in, for example GET /employees/ana)."""
    return json.dumps(directory_request(method.upper(), path, body, base_url=_discovered(service, "REST API")))


@tool
def send_agent_message(service: str, text: str) -> str:
    """Send a message to an A2A agent that discover_services returned and return its reply."""
    return json.dumps(a2a_send(text, url=_discovered(service, "A2A agent")))


async def _drop_api_key(request):
    """The Anthropic SDK always sends its API key as x-api-key; AgentCore Gateway accepts only one credential, the SigV4
    Authorization header. Runs after signing, and x-api-key isn't signed."""
    request.headers.pop("x-api-key", None)


def build_model(llm=None):
    """The model: Amazon Bedrock, or the gateway's model endpoint (llm, from the registry), in the API its record names:
    OpenAI Chat Completions ("openai") or the Anthropic Messages API ("anthropic")."""
    if llm and llm["protocol"] == "anthropic":
        from strands.models.anthropic import AnthropicModel  # only the gateways that serve the Messages API need it

        # Strands creates the Anthropic client once and reuses it, so the SigV4-signing HTTP client stays open
        http_client = httpx.AsyncClient(auth=AUTH, timeout=120, event_hooks={"request": [_drop_api_key]})
        return AnthropicModel(client_args={"base_url": llm["url"], "api_key": "signed-with-sigv4", "http_client": http_client},
                              model_id=llm["models"][0], max_tokens=4096)
    if llm:
        # One client for this invocation, passed as `client`: with `client_args`, Strands opens and closes an OpenAI
        # client on every model call, which also closes the SigV4-signing HTTP client after the first call
        http_client = httpx.AsyncClient(auth=AUTH, headers=_litellm_headers(), timeout=120)
        client = openai.AsyncOpenAI(base_url=llm["url"], api_key="signed-with-sigv4", http_client=http_client)
        return OpenAIModel(client=client, model_id=llm["models"][0])
    return BedrockModel(model_id=MODEL_ID, boto_session=session)


# Where each direct-mode tool call goes (the other modes reach every tool through their gateway)
TOOL_TARGETS = {
    "discover_services": lambda i: "agent-registry: ListDiscoverableRegistryRecords, BatchGetDiscoverableRegistryRecord",
    "call_mcp_tool": lambda i: f"{i.get('service')}: MCP tools/call {i.get('tool_name')}",
    "call_rest_api": lambda i: f"{i.get('service')}: {str(i.get('method', '')).upper()} {i.get('path')}",
    "send_agent_message": lambda i: f"{i.get('service')}: A2A message/send",
}


def _tool_target(name, tool_input, mcp_server=None):
    target = TOOL_TARGETS.get(name)
    if target:
        return target(tool_input)
    # A tool loaded from an MCP server (the gateway's MCP endpoint)
    return f"{mcp_server}: MCP tools/call {name}" if mcp_server else f"tool {name}"


def _tool_status(tool_result):
    """HTTP status a tool reported (the service tools return it in their JSON), the services discovered, or the
    tool's own status."""
    for block in tool_result.get("content", []):
        try:
            result = json.loads(block.get("text", ""))
        except (ValueError, AttributeError):
            continue
        if isinstance(result, dict) and isinstance(result.get("services"), dict):
            return ", ".join(result["services"]) or "no services found"
        if isinstance(result, dict) and isinstance(result.get("status"), int):
            return str(result["status"])
    return tool_result.get("status", "")


def trace(messages, catalog=None):
    """Summarize the calls an LLM-driven invocation made: each model turn, what it decided, and each tool call."""
    model, mcp_server, steps = "model in Amazon Bedrock (bedrock-runtime)", None, []
    if MODE in GATEWAY_MODES:
        # The agent reads the registry, then loads the tools it may use from the gateway's MCP endpoint
        llm = next(name for name, e in catalog.items() if e["type"] == "LLM")
        mcp_server = next((name for name, e in catalog.items() if e["type"] == "MCP server"), None)
        model = f"model {catalog[llm]['models'][0]} through {llm}"
        steps = [{"call": TOOL_TARGETS["discover_services"]({}), "status": ", ".join(catalog)}]
        if mcp_server:
            allowed = "this agent's virtual key allows" if MODE == "self_hosted_gateway" else "the gateway's policy allows"
            steps.append({"call": f"{mcp_server}: MCP tools/list", "detail": f"load the tools {allowed}"})
    pending = {}
    for message in messages:
        content = message.get("content", [])
        if message.get("role") == "assistant":
            uses = [b["toolUse"] for b in content if "toolUse" in b]
            text = " ".join(b["text"].strip() for b in content if b.get("text", "").strip())
            if uses:
                decision = "decides to call " + ", ".join(f"{u['name']}({json.dumps(u.get('input', {}))})" for u in uses)
            else:
                decision = "writes the final answer"
            steps.append({"call": model, "detail": decision, "reasoning": text[:300] if uses else ""})
            for use in uses:
                pending[use["toolUseId"]] = {"call": _tool_target(use["name"], use.get("input", {}), mcp_server)}
                steps.append(pending[use["toolUseId"]])
        else:
            for block in content:
                if "toolResult" in block and block["toolResult"].get("toolUseId") in pending:
                    pending[block["toolResult"]["toolUseId"]]["status"] = _tool_status(block["toolResult"])
    return steps


def run_prompt(prompt):
    catalog, llm = None, None
    if MODE == "direct":
        # No backends configured: the model discovers them in AWS Agent Registry and calls them through VPC Lattice
        tools, system_prompt = [discover_services, call_mcp_tool, call_rest_api, send_agent_message], SYSTEM_PROMPT + DISCOVERY_PROMPT
    else:
        # No gateway configured: the agent reads the gateway's endpoints in AWS Agent Registry. The tools come from
        # the gateway's MCP endpoint (only those the gateway allows this agent), the agents from their records.
        catalog = load_catalog()
        llm = next((e for e in catalog.values() if e["type"] == "LLM"), None)
        if llm is None:
            raise LookupError("No model endpoint found in AWS Agent Registry")
        DISCOVERED.clear()
        DISCOVERED.update(catalog)
        agents = [name for name, e in catalog.items() if e["type"] == "A2A agent"]
        clients = [MCPClient(url=url, headers=headers or None, auth_provider=auth) for _, url, auth, headers in mcp_endpoints(catalog)]
        tools = clients + ([send_agent_message] if agents else [])
        system_prompt = SYSTEM_PROMPT + (f" To ask another agent, call send_agent_message with one of these agents: {', '.join(agents)}." if agents else "")
    agent = Agent(model=build_model(llm), system_prompt=system_prompt, tools=tools)
    reply = str(agent(prompt))
    return {"reply": reply, "calls": trace(agent.messages, catalog)}


# ---------- ENTRYPOINT ----------
@app.entrypoint
def invoke(payload, context=None):
    action = payload.get("action")
    log.info(json.dumps({"agent": AGENT_NAME, "mode": MODE, "action": action or "prompt"}))
    try:
        if action is None:
            return {"agent": AGENT_NAME, **run_prompt(payload["prompt"])}
        if action == "whoami":
            result = session.client("sts").get_caller_identity()["Arn"]
        elif action == "discover":
            result = discover(payload.get("query", "helpdesk"))
        elif action == "list_tools":
            result = {name: mcp_request(url, auth, headers, "tools/list") for name, url, auth, headers in mcp_endpoints()}
        elif action == "call_tool":
            name, url, auth, headers = mcp_endpoints()[0]
            result = mcp_request(url, auth, headers, "tools/call",
                                 {"name": payload["name"], "arguments": payload.get("arguments", {})})
        elif action == "http":
            result = directory_request(payload.get("method", "GET"), payload["path"], payload.get("body"))
        elif action == "a2a":
            result = a2a_send(payload["text"])
        elif action == "invoke_agent":
            result = invoke_peer_agent(payload["text"])
        else:
            return {"agent": AGENT_NAME, "error": f"Unknown action: {action}"}
        return {"agent": AGENT_NAME, "mode": MODE, "action": action, "result": result}
    except Exception as error:  # report upstream failures (DNS, TLS, 4xx) instead of failing the invocation
        log.exception("Invocation failed")
        return {"agent": AGENT_NAME, "mode": MODE, "action": action, "error": f"{type(error).__name__}: {error}"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
