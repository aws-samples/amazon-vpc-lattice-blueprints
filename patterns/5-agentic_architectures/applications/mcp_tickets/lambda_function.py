# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Helpdesk 'tickets' MCP server.

Minimal MCP server (Streamable HTTP transport, stateless, JSON responses) running as an AWS Lambda function.
It is reached through a VPC Lattice service (Lambda target, event structure V2) or a private Amazon API Gateway
REST API (Lambda proxy integration), so it accepts both event formats. server.py serves the same handler from a
container. Tickets are kept in memory: this is a connectivity demo, not a ticketing system.
"""
import base64
import json
import uuid
from datetime import datetime, timezone

SUPPORTED_VERSIONS = ["2025-06-18", "2025-03-26"]
SERVER_INFO = {"name": "tickets", "version": "1.0.0"}
TICKETS = {}
TOOLS = [
    {
        "name": "create_ticket",
        "description": "Open a helpdesk ticket for an employee.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "employee_id": {"type": "string", "description": "Employee identifier, for example 'ana'."},
                "summary": {"type": "string", "description": "Short description of the issue."},
                "priority": {"type": "string", "enum": ["low", "medium", "high"]},
            },
            "required": ["employee_id", "summary"],
        },
    },
    {
        "name": "list_tickets",
        "description": "List the open helpdesk tickets, optionally filtered by employee.",
        "inputSchema": {
            "type": "object",
            "properties": {"employee_id": {"type": "string", "description": "Employee identifier."}},
        },
    },
]


def _parse(event):
    """Return (method, body, caller) for a VPC Lattice V2 or API Gateway REST proxy event."""
    if "httpMethod" in event:  # API Gateway REST API (Lambda proxy integration)
        method = event["httpMethod"]
        identity = event.get("requestContext", {}).get("identity", {})
        caller = identity.get("userArn") or identity.get("caller") or "anonymous"
    else:  # VPC Lattice (event structure V2)
        method = event.get("method", "")
        identity = event.get("requestContext", {}).get("identity", {})
        caller = identity.get("principal") or f"anonymous (source VPC {identity.get('sourceVpcArn', 'unknown')})"
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    return method.upper(), body, caller


def _response(status, payload=None, headers=None):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", **(headers or {})},
        "body": "" if payload is None else json.dumps(payload),
        "isBase64Encoded": False,
    }


def _call_tool(name, arguments, caller):
    if name == "create_ticket":
        ticket = {
            "id": f"TCK-{uuid.uuid4().hex[:8]}",
            "employee_id": arguments["employee_id"],
            "summary": arguments["summary"],
            "priority": arguments.get("priority", "medium"),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        TICKETS[ticket["id"]] = ticket
        result = {"ticket": ticket}
    elif name == "list_tickets":
        employee = arguments.get("employee_id")
        result = {"tickets": [t for t in TICKETS.values() if not employee or t["employee_id"] == employee]}
    else:
        return None
    result["caller"] = caller
    return {"content": [{"type": "text", "text": json.dumps(result)}], "isError": False}


def _handle(message, caller):
    method, msg_id, params = message.get("method"), message.get("id"), message.get("params") or {}
    if msg_id is None:  # notification (for example notifications/initialized): no response body
        return None
    if method == "initialize":
        requested = params.get("protocolVersion")
        result = {
            "protocolVersion": requested if requested in SUPPORTED_VERSIONS else SUPPORTED_VERSIONS[0],
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": SERVER_INFO,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        result = _call_tool(params.get("name"), params.get("arguments") or {}, caller)
        if result is None:
            return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32602, "message": f"Unknown tool: {params.get('name')}"}}
    else:
        return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32601, "message": f"Method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": msg_id, "result": result}


def lambda_handler(event, context):
    method, body, caller = _parse(event)
    print(json.dumps({"method": method, "caller": caller}))
    if method != "POST":  # stateless server: no SSE stream (GET) and no session to delete (DELETE)
        return _response(405, {"error": "Method Not Allowed"}, {"Allow": "POST"})
    try:
        message = json.loads(body)
    except json.JSONDecodeError:
        return _response(400, {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
    if isinstance(message, list):  # JSON-RPC batch
        replies = [r for r in (_handle(m, caller) for m in message) if r is not None]
        return _response(200, replies) if replies else _response(202)
    reply = _handle(message, caller)
    return _response(200, reply) if reply is not None else _response(202)
