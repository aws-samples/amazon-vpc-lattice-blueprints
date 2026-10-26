# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Helpdesk 'triage' specialist agent, served over the A2A protocol (Strands Agents A2AServer).

It runs on Amazon ECS, behind a VPC Lattice service or an Amazon Bedrock AgentCore Gateway target, or on Amazon
Bedrock AgentCore Runtime with the A2A server protocol. All expect an A2A server on port 9000 at the root path.
PUBLIC_URL is the URL advertised in the agent card (/.well-known/agent-card.json).

The model depends on CONNECTIVITY_MODE:

- self_hosted_gateway: the AI gateway's model endpoint, found in AWS Agent Registry at start-up and called through
  VPC Lattice (SigV4) with the triage agent's virtual key.
- agentcore_gateway: the AgentCore Gateway's model endpoint, found in AWS Agent Registry at start-up and called
  with the triage agent's IAM role (SigV4, bedrock-agentcore).

The model record's protocol names the API: OpenAI Chat Completions ("openai") or the Anthropic Messages API
("anthropic").
- any other mode: Amazon Bedrock (MODEL_ID).
"""
import json
import logging
import os
import socket
import time

import boto3
import httpx
import openai
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.config import Config
from strands import Agent
from strands.models import BedrockModel
from strands.models.openai import OpenAIModel
from strands.multiagent.a2a import A2AServer

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("triage")

REGION = os.environ.get("AWS_REGION", "eu-west-1")
MODE = os.environ.get("CONNECTIVITY_MODE", "direct")
MODEL_ID = os.environ.get("MODEL_ID", "eu.anthropic.claude-haiku-5-5")
session = boto3.session.Session(region_name=REGION)


class GatewayAuth(httpx.Auth):
    """Sign httpx requests with SigV4: for VPC Lattice (vpc-lattice-svcs, unsigned payload) or for AgentCore Gateway
    (bedrock-agentcore, signed payload)."""

    requires_request_body = True

    def __init__(self, service, unsigned_payload):
        self.service = service
        self.unsigned_payload = unsigned_payload

    def auth_flow(self, request):
        headers = {"host": request.url.netloc.decode()}
        if self.unsigned_payload:
            headers["x-amz-content-sha256"] = "UNSIGNED-PAYLOAD"
        if "content-type" in request.headers:
            headers["content-type"] = request.headers["content-type"]
        aws_request = AWSRequest(method=request.method, url=str(request.url), data=request.content, headers=headers)
        aws_request.context["payload_signing_enabled"] = not self.unsigned_payload
        SigV4Auth(session.get_credentials().get_frozen_credentials(), self.service, REGION).add_auth(aws_request)
        for name, value in aws_request.headers.items():
            request.headers[name] = value
        yield request


def gateway_llm():
    """The gateway's model endpoint from AWS Agent Registry. Waits until the record is submitted for approval."""
    client = session.client("agent-registry", endpoint_url=os.environ.get("REGISTRY_ENDPOINT_URL") or None)
    registry_id = os.environ["REGISTRY_ID"]
    while True:
        record_ids = [r["recordId"] for r in client.list_discoverable_registry_records(registryId=registry_id)["registryRecords"]]
        if record_ids:
            records = client.batch_get_discoverable_registry_record(
                entries=[{"registryId": registry_id, "recordIds": record_ids}])["registryRecords"]
            for record in records:
                custom = record.get("descriptors", {}).get("custom")
                if custom and json.loads(custom["data"]).get("protocol") in ("openai", "anthropic"):
                    llm = json.loads(custom["data"])
                    log.info(json.dumps({"model_endpoint": record["name"], "url": llm["baseUrl"]}))
                    return llm
        log.info("Waiting for the gateway's model endpoint in AWS Agent Registry")
        time.sleep(15)


async def _drop_api_key(request):
    """The Anthropic SDK always sends its API key as x-api-key; AgentCore Gateway accepts only one credential, the SigV4
    Authorization header. Runs after signing, and x-api-key isn't signed."""
    request.headers.pop("x-api-key", None)


def build_model():
    if MODE not in ("self_hosted_gateway", "agentcore_gateway"):
        # One long-lived model client: TCP keepalives (interval set by the task's net.ipv4.tcp_keepalive_time) stop
        # its idle connection to the centralized bedrock-runtime endpoint from timing out in VPC Lattice
        return BedrockModel(model_id=MODEL_ID, boto_session=session, boto_client_config=Config(tcp_keepalive=True))
    llm = gateway_llm()
    if MODE == "agentcore_gateway":
        auth, headers = GatewayAuth("bedrock-agentcore", unsigned_payload=False), {}
    else:
        secret = session.client("secretsmanager").get_secret_value(SecretId=os.environ["LITELLM_API_KEY_SECRET_ARN"])["SecretString"]
        key = secret if secret.startswith("sk-") else f"sk-{secret}"
        auth, headers = GatewayAuth("vpc-lattice-svcs", unsigned_payload=True), {"x-litellm-api-key": f"Bearer {key}"}
    # Same keepalive for the pooled connection to the gateway
    transport = httpx.AsyncHTTPTransport(socket_options=[(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)])
    http_client = httpx.AsyncClient(auth=auth, headers=headers, timeout=120, transport=transport)
    if llm["protocol"] == "anthropic":  # the Anthropic Messages API, for the gateways that serve it
        from strands.models.anthropic import AnthropicModel

        http_client.event_hooks = {"request": [_drop_api_key]}
        # Strands creates the Anthropic client once and reuses it, so the SigV4-signing HTTP client stays open
        return AnthropicModel(client_args={"base_url": llm["baseUrl"], "api_key": "signed-with-sigv4", "http_client": http_client},
                              model_id=llm["models"][0], max_tokens=4096)
    # One long-lived client, passed as `client`: with `client_args`, Strands closes the client (and the SigV4-signing
    # HTTP client) after every model call
    client = openai.AsyncOpenAI(base_url=llm["baseUrl"], api_key="signed-with-sigv4", http_client=http_client)
    return OpenAIModel(client=client, model_id=llm["models"][0])


agent = Agent(
    name="triage",
    description="Helpdesk triage agent: decides the priority (low, medium, high) of an IT issue.",
    model=build_model(),
    system_prompt=(
        "You triage IT helpdesk issues. Reply with one word, the priority (low, medium or high), followed by a "
        "one-sentence reason. Hardware that stops an employee from working is high."
    ),
    callback_handler=None,
)

if __name__ == "__main__":
    A2AServer(agent=agent, host="0.0.0.0", port=9000, http_url=os.environ.get("PUBLIC_URL"), serve_at_root=True).serve()
