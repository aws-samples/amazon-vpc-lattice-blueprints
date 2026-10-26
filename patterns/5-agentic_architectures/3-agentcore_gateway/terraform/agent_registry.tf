/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/agent_registry.tf ---

# ========== AWS AGENT REGISTRY ==========
# The agents only know the gateway, so the records describe the gateway's endpoints

# ---------- REGISTRY ----------
resource "aws_agentregistry_registry" "registry" {
  name        = "registry-${var.identifier}"
  description = "Helpdesk AgentCore Gateway: tools, agents and models"

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
resource "awscc_agentregistry_registry_record" "gateway_tools" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "gateway-tools"
  display_name   = "Helpdesk tools through the AgentCore Gateway (MCP)"
  description    = "Helpdesk tickets and employee directory tools, served by the AgentCore Gateway."
  record_type    = "MCP"
  record_version = "1.0.0"

  descriptors = {
    mcp_server = {
      data_schema_version = "2025-12-11"
      data = jsonencode({
        name        = "internal.helpdesk/agentcore-gateway"
        description = "Helpdesk tickets and employee directory tools, served by the AgentCore Gateway."
        version     = "1.0.0"
        remotes     = [{ type = "streamable-http", url = "${local.gateway_url}/mcp" }]
      })
    }
  }
}

# The triage agent through the gateway (agent card)
resource "awscc_agentregistry_registry_record" "gateway_triage" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "gateway-triage"
  display_name   = "Triage agent through the AgentCore Gateway (A2A)"
  description    = "A2A agent that decides the priority of an IT issue, served by the AgentCore Gateway."
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
        url                = "${local.gateway_url}/${aws_bedrockagentcore_gateway_target.triage.name}/"
        preferredTransport = "JSONRPC"
        capabilities       = { streaming = true }
        defaultInputModes  = ["text"]
        defaultOutputModes = ["text"]
        skills             = [{ id = "triage", name = "Triage", description = "Assign a priority to an IT issue.", tags = ["helpdesk"] }]
      })
    }
  }
}

# The gateway's model endpoint (custom descriptor: Anthropic Messages API base URL and model)
resource "awscc_agentregistry_registry_record" "gateway_llm" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "gateway-llm"
  display_name   = "Helpdesk model through the AgentCore Gateway"
  description    = "Model endpoint of the AgentCore Gateway (Anthropic Messages API)."
  record_type    = "CUSTOM"
  record_version = "1.0.0"

  descriptors = {
    custom = {
      data = jsonencode({
        protocol = "anthropic"
        baseUrl  = "${local.gateway_url}/inference"
        models   = [var.model_id]
      })
    }
  }
}
