/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/agent_registry.tf ---

# ========== AWS AGENT REGISTRY ==========
# The agents can only reach the AI gateway, so the records describe the gateway's endpoints

# ---------- REGISTRY ----------
resource "aws_agentregistry_registry" "registry" {
  name        = "registry-${var.identifier}"
  description = "Helpdesk AI gateway: tools, agents and models"

  discovery_configuration {
    authorizer_type = "AWS_IAM"
  }

  # Records become discoverable as soon as they are submitted (deploy.sh submits them)
  approval_configuration {
    auto_approval_rules = ["APPROVE_ALL"]
  }
}

# ---------- REGISTRY RECORDS ----------
# The gateway's MCP endpoint (server.json)
resource "awscc_agentregistry_registry_record" "ai_gateway_tools" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "ai-gateway-tools"
  display_name   = "Helpdesk tools through the AI gateway (MCP)"
  description    = "Helpdesk tickets and employee directory tools, served by the AI gateway."
  record_type    = "MCP"
  record_version = "1.0.0"

  descriptors = {
    mcp_server = {
      data_schema_version = "2025-12-11"
      data = jsonencode({
        name        = "internal.helpdesk/ai-gateway"
        description = "Helpdesk tickets and employee directory tools, served by the AI gateway."
        version     = "1.0.0"
        remotes     = [{ type = "streamable-http", url = "${local.gateway_url}/mcp/" }]
      })
    }
  }
}

# The triage agent through the gateway (agent card)
resource "awscc_agentregistry_registry_record" "ai_gateway_triage" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "ai-gateway-triage"
  display_name   = "Triage agent through the AI gateway (A2A)"
  description    = "A2A agent that decides the priority of an IT issue, served by the AI gateway."
  record_type    = "AGENT"
  record_version = "1.0.0"

  descriptors = {
    a2_a_agent_card = {
      data_schema_version = "0.3"
      data = jsonencode({
        name               = "triage"
        description        = "Helpdesk triage agent: decides the priority (low, medium, high) of an IT issue."
        version            = "1.0.0"
        protocolVersion    = "0.3.0"
        url                = "${local.gateway_url}/a2a/triage"
        preferredTransport = "JSONRPC"
        capabilities       = { streaming = true }
        defaultInputModes  = ["text"]
        defaultOutputModes = ["text"]
        skills             = [{ id = "triage", name = "Triage", description = "Assign a priority to an IT issue.", tags = ["helpdesk"] }]
      })
    }
  }
}

# The gateway's model endpoint (custom descriptor: OpenAI-compatible base URL and model alias)
resource "awscc_agentregistry_registry_record" "ai_gateway_llm" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "ai-gateway-llm"
  display_name   = "Helpdesk model through the AI gateway"
  description    = "OpenAI-compatible model endpoint of the AI gateway."
  record_type    = "CUSTOM"
  record_version = "1.0.0"

  descriptors = {
    custom = {
      data = jsonencode({
        protocol = "openai"
        baseUrl  = "${local.gateway_url}/v1"
        models   = ["helpdesk-llm"]
      })
    }
  }
}
