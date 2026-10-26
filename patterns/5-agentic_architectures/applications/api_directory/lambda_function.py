# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Helpdesk 'directory' REST API.

GET /employees, GET /employees/{id} and POST /employees, running as an AWS Lambda function. It is reached through a
VPC Lattice service (Lambda target, event structure V2) or a private Amazon API Gateway REST API (Lambda proxy
integration), so it accepts both event formats. gateway_handler serves the same operations as the tools of an
Amazon Bedrock AgentCore Gateway Lambda target. Every response includes the caller identity the network passed in,
so the tests can show who reached the API. Employees are kept in memory: this is a connectivity demo.
"""
import base64
import json

EMPLOYEES = {
    "ana": {"id": "ana", "name": "Ana Garcia", "department": "Engineering", "device": "laptop-0042"},
    "bob": {"id": "bob", "name": "Bob Smith", "department": "Finance", "device": "laptop-0107"},
    "alice": {"id": "alice", "name": "Alice Martin", "department": "Helpdesk", "device": "laptop-0001"},
}


def _parse(event):
    """Return (method, path, body, caller) for a VPC Lattice V2 or API Gateway REST proxy event."""
    if "httpMethod" in event:  # API Gateway REST API (Lambda proxy integration)
        method, path = event["httpMethod"], event.get("path", "/")
        identity = event.get("requestContext", {}).get("identity", {})
        caller = identity.get("userArn") or identity.get("caller") or "anonymous"
    else:  # VPC Lattice (event structure V2)
        method, path = event.get("method", ""), event.get("path", "/")
        identity = event.get("requestContext", {}).get("identity", {})
        caller = identity.get("principal") or f"anonymous (source VPC {identity.get('sourceVpcArn', 'unknown')})"
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    return method.upper(), path.rstrip("/") or "/", body, caller


def _response(status, payload):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
        "isBase64Encoded": False,
    }


def lambda_handler(event, context):
    method, path, body, caller = _parse(event)
    print(json.dumps({"method": method, "path": path, "caller": caller}))
    parts = [p for p in path.split("/") if p]

    if parts == ["employees"] and method == "GET":
        return _response(200, {"employees": list(EMPLOYEES.values()), "caller": caller})
    if parts == ["employees"] and method == "POST":
        try:
            employee = json.loads(body)
            employee_id = employee["id"]
        except (json.JSONDecodeError, KeyError, TypeError):
            return _response(400, {"error": "Body must be a JSON object with an 'id' field", "caller": caller})
        EMPLOYEES[employee_id] = employee
        return _response(201, {"employee": employee, "caller": caller})
    if len(parts) == 2 and parts[0] == "employees" and method == "GET":
        employee = EMPLOYEES.get(parts[1])
        if employee is None:
            return _response(404, {"error": f"Employee '{parts[1]}' not found", "caller": caller})
        return _response(200, {"employee": employee, "caller": caller})
    return _response(404, {"error": f"No route for {method} {path}", "caller": caller})


# ---------- AMAZON BEDROCK AGENTCORE GATEWAY (LAMBDA TARGET) ----------
# The gateway invokes the function with the tool's arguments as the event, and the tool name
# (<target>___<tool>) in the client context. Each tool maps to one of the API's operations.
TOOL_ROUTES = {
    "listEmployees": lambda args: ("GET", "/employees", None),
    "getEmployee": lambda args: ("GET", f"/employees/{args.get('id', '')}", None),
    "createEmployee": lambda args: ("POST", "/employees", json.dumps(args)),
}


def gateway_handler(event, context):
    tool_name = context.client_context.custom["bedrockAgentCoreToolName"].split("___", 1)[-1]
    route = TOOL_ROUTES.get(tool_name)
    if route is None:
        return {"error": f"Unknown tool: {tool_name}"}
    method, path, body = route(event or {})
    # The gateway calls with its own service role; the API sees the Lambda target, not the agent behind it
    response = lambda_handler({"method": method, "path": path, "body": body, "requestContext": {"identity": {"principal": "AgentCore Gateway (Lambda target)"}}}, context)
    return {"status": response["statusCode"], **json.loads(response["body"])}
