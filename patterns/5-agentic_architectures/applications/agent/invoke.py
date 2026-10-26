# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Send one invocation to the agent running in this container (used through ECS Exec in the pattern tests).

Usage: python /app/invoke.py '{"action": "list_tools"}'
       python /app/invoke.py <base64-encoded JSON>   (avoids nested quoting through ECS Exec)
"""
import base64
import json
import sys
import urllib.request

payload = sys.argv[1] if len(sys.argv) > 1 else '{"action": "whoami"}'
if not payload.lstrip().startswith("{"):
    payload = base64.b64decode(payload).decode("utf-8")
request = urllib.request.Request(
    "http://127.0.0.1:8080/invocations", data=payload.encode(), headers={"Content-Type": "application/json"}
)
with urllib.request.urlopen(request, timeout=300) as response:
    print(json.dumps(json.loads(response.read()), indent=2))
