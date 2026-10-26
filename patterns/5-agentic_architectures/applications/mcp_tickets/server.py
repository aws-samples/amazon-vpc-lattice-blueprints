# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Helpdesk 'tickets' MCP server as a container (Amazon ECS), on port 8000.

The same MCP server as the AWS Lambda function (lambda_function.py), served over HTTP: POST /mcp for the MCP
messages (Streamable HTTP, stateless, JSON responses) and GET /health for the load balancer health check.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from lambda_function import lambda_handler


class Handler(BaseHTTPRequestHandler):
    def _reply(self, response):
        body = response["body"].encode()
        self.send_response(response["statusCode"])
        for name, value in response["headers"].items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        # A client can send the body with Content-Length or chunked (Transfer-Encoding: chunked), as AgentCore Gateway does
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            chunks = []
            while (size := int(self.rfile.readline().split(b";")[0].strip(), 16)) > 0:
                chunks.append(self.rfile.read(size))
                self.rfile.readline()  # CRLF after each chunk
            while self.rfile.readline() not in (b"\r\n", b"\n", b""):  # optional trailers, then the final CRLF
                pass
            return b"".join(chunks).decode()
        return self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()

    def _mcp(self, method):
        if self.path.split("?")[0].rstrip("/") != "/mcp":
            return self._reply({"statusCode": 404, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"error": "Not Found"})})
        body = self._read_body()
        # The caller the server sees is the address traffic arrives from (here, the load balancer)
        event = {"method": method, "body": body, "requestContext": {"identity": {"principal": f"anonymous (from {self.client_address[0]})"}}}
        self._reply(lambda_handler(event, None))

    def do_GET(self):
        if self.path == "/health":
            return self._reply({"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"status": "ok"})})
        self._mcp("GET")

    def do_POST(self):
        self._mcp("POST")

    def do_DELETE(self):
        self._mcp("DELETE")

    def log_message(self, format, *args):  # the handler already logs each MCP request
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
