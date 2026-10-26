# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Chat with one of the consumer agents from your machine (Python 3 and the AWS CLI only).

Pick an example prompt by number, or type your own. Each prompt is a separate invocation: the agent doesn't keep
the conversation between prompts.

Usage (the Terraform chat.sh and the CloudFormation `make chat` fill these in from the deployment outputs):
  python3 chat.py ecs --cluster <cluster> --service <service> --region <region>
  python3 chat.py runtime --arn <agent-runtime-arn>
"""
import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile

EXAMPLE_PROMPTS = [
    ("Look up an employee", "Who is Ana? Which department is she in and which device does she use?"),
    ("Report an issue", "Ana's laptop doesn't boot and she can't work. How urgent is it?"),
    ("Open a ticket", "Open a ticket for Ana: her laptop doesn't boot."),
    ("List tickets", "Which tickets are open for Ana?"),
    ("Add an employee (agent-ecs only)", "Add Zoe Lee to the directory with the identifier zoe."),
]


def find_session_manager_plugin():
    """Find the Session Manager plugin, also in its default install folders when they aren't on PATH.

    The AWS CLI looks the plugin up on PATH, so a folder where it's found is added to PATH for the ECS Exec calls.
    """
    if shutil.which("session-manager-plugin"):
        return True
    for folder in ("/usr/local/bin", "/usr/local/sessionmanagerplugin/bin", "/opt/homebrew/bin"):
        if os.access(os.path.join(folder, "session-manager-plugin"), os.X_OK):
            os.environ["PATH"] = folder + os.pathsep + os.environ.get("PATH", "")
            return True
    return False


def invoke_ecs(args, payload):
    """Run /app/invoke.py inside the agent-ecs container through ECS Exec."""
    task = subprocess.run(
        ["aws", "ecs", "list-tasks", "--cluster", args.cluster, "--service-name", args.service,
         "--query", "taskArns[0]", "--output", "text", "--region", args.region],
        check=True, capture_output=True, text=True).stdout.strip()
    encoded = base64.b64encode(json.dumps(payload).encode()).decode()  # avoids nested quoting through ECS Exec
    output = subprocess.run(
        ["aws", "ecs", "execute-command", "--cluster", args.cluster, "--task", task, "--container", "agent",
         "--interactive", "--region", args.region, "--command", f"python /app/invoke.py {encoded}"],
        check=True, capture_output=True, text=True).stdout
    # The Session Manager plugin prints session start/exit lines around the JSON response
    return json.loads(output[output.index("{"):output.rindex("}") + 1])


def invoke_runtime(args, payload):
    """Call InvokeAgentRuntime on agent-runtime."""
    region = args.arn.split(":")[3]
    with tempfile.TemporaryDirectory() as directory:
        response_file = os.path.join(directory, "response.json")
        subprocess.run(
            ["aws", "bedrock-agentcore", "invoke-agent-runtime", "--agent-runtime-arn", args.arn,
             "--payload", json.dumps(payload), "--cli-binary-format", "raw-in-base64-out", "--region", region,
             response_file],
            check=True, capture_output=True, text=True)
        with open(response_file, encoding="utf-8") as response:
            return json.load(response)


def print_calls(calls):
    """Print the calls the agent made: each model turn with its decision, and each tool call with its status."""
    if not calls:
        return
    print("  Calls made:")
    for number, call in enumerate(calls, start=1):
        status = f" -> {call['status']}" if call.get("status") else ""
        detail = f": {call['detail']}" if call.get("detail") else ""
        print(f"  {number}. {call['call']}{detail}{status}")
        if call.get("reasoning"):
            print(f"     \"{call['reasoning']}\"")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("agent", choices=["ecs", "runtime"])
    parser.add_argument("--cluster", help="ECS cluster (ecs)")
    parser.add_argument("--service", help="ECS service of agent-ecs (ecs)")
    parser.add_argument("--region", help="AWS Region (ecs)")
    parser.add_argument("--arn", help="AgentCore Runtime agent ARN (runtime)")
    args = parser.parse_args()
    if args.agent == "ecs" and not (args.cluster and args.service and args.region):
        parser.error("ecs needs --cluster, --service and --region")
    if args.agent == "runtime" and not args.arn:
        parser.error("runtime needs --arn")
    if args.agent == "ecs" and not find_session_manager_plugin():
        sys.exit("agent-ecs is reached through ECS Exec, which needs the Session Manager plugin for the AWS CLI: "
                 "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html")
    invoke = invoke_ecs if args.agent == "ecs" else invoke_runtime

    print(f"Connected to agent-{args.agent}. Example prompts:")
    for number, (title, prompt) in enumerate(EXAMPLE_PROMPTS, start=1):
        print(f"  {number}. {title}: \"{prompt}\"")
    print("Type a number, your own prompt, or 'exit'.")

    while True:
        try:
            text = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not text:
            continue
        if text.lower() in ("exit", "quit"):
            return
        if text.isdigit() and 1 <= int(text) <= len(EXAMPLE_PROMPTS):
            text = EXAMPLE_PROMPTS[int(text) - 1][1]
            print(f"you> {text}")
        try:
            response = invoke(args, {"prompt": text})
        except subprocess.CalledProcessError as error:
            print(f"Invocation failed: {(error.stderr or error.stdout).strip()}", file=sys.stderr)
            continue
        print_calls(response.get("calls", []))
        print(f"agent-{args.agent}> {response.get('reply') or response.get('error') or json.dumps(response)}")


if __name__ == "__main__":
    main()
