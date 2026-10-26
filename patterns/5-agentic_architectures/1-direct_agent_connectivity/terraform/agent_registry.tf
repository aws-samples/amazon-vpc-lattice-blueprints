/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/agent_registry.tf ---

# ========== AWS AGENT REGISTRY ==========

# ---------- REGISTRY ----------
resource "aws_agentregistry_registry" "registry" {
  name        = "registry-${var.identifier}"
  description = "Helpdesk tools, APIs and agents"

  discovery_configuration {
    authorizer_type = "AWS_IAM"
  }

  # Records become discoverable as soon as they are submitted (deploy.sh submits them)
  approval_configuration {
    auto_approval_rules = ["APPROVE_ALL"]
  }
}

# ---------- REGISTRY RECORDS ----------
# MCP server record (server.json + tools)
resource "awscc_agentregistry_registry_record" "mcp_tickets" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "mcp-tickets"
  display_name   = "Helpdesk tickets (MCP)"
  description    = "MCP server to create and list helpdesk tickets."
  record_type    = "MCP"
  record_version = "1.0.0"

  descriptors = {
    mcp_server = {
      data_schema_version = "2025-12-11"
      data = jsonencode({
        name        = "internal.helpdesk/tickets"
        description = "Create and list helpdesk tickets."
        version     = "1.0.0"
        remotes     = [{ type = "streamable-http", url = "${local.service_urls["mcp-tickets"]}/mcp" }]
      })
      additional_data = {
        tools = {
          data_schema_version = "2025-06-18"
          data = jsonencode({
            tools = [
              { name = "create_ticket", description = "Open a helpdesk ticket for an employee.", inputSchema = { type = "object", properties = { employee_id = { type = "string" }, summary = { type = "string" }, priority = { type = "string" } }, required = ["employee_id", "summary"] } },
              { name = "list_tickets", description = "List the open helpdesk tickets.", inputSchema = { type = "object", properties = { employee_id = { type = "string" } } } },
            ]
          })
        }
      }
    }
  }
}

# REST API record (custom descriptor: base URL and operations)
resource "awscc_agentregistry_registry_record" "api_directory" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "api-directory"
  display_name   = "Employee directory (REST API)"
  description    = "REST API to look up and create employees."
  record_type    = "CUSTOM"
  record_version = "1.0.0"

  descriptors = {
    custom = {
      data = jsonencode({
        protocol = "openapi"
        baseUrl  = local.service_urls["api-directory"]
        operations = [
          { operationId = "listEmployees", method = "GET", path = "/employees" },
          { operationId = "getEmployee", method = "GET", path = "/employees/{id}" },
          { operationId = "createEmployee", method = "POST", path = "/employees" },
        ]
      })
    }
  }
}

# A2A agent record (agent card)
resource "awscc_agentregistry_registry_record" "agent_triage" {
  registry_id    = aws_agentregistry_registry.registry.registry_id
  name           = "agent-triage"
  display_name   = "Triage agent (A2A)"
  description    = "A2A agent that decides the priority of an IT issue."
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
        url                = "${local.service_urls["agent-triage"]}/"
        preferredTransport = "JSONRPC"
        capabilities       = { streaming = true }
        defaultInputModes  = ["text"]
        defaultOutputModes = ["text"]
        skills             = [{ id = "triage", name = "Triage", description = "Assign a priority to an IT issue.", tags = ["helpdesk"] }]
      })
    }
  }
}
