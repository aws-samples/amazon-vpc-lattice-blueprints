/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/gateway.tf ---

# ---------- GATEWAY ----------
# No protocol type: the gateway mixes MCP targets with an HTTP (A2A) and an inference target
resource "aws_bedrockagentcore_gateway" "gateway" {
  name            = "gateway-${var.identifier}"
  description     = "Helpdesk tools, triage agent and model"
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "AWS_IAM"

  policy_engine_configuration {
    arn  = aws_bedrockagentcore_policy_engine.gateway.policy_engine_arn
    mode = "ENFORCE"
  }

  # The gateway's role must be able to use the policy engine when the gateway is created
  depends_on = [time_sleep.gateway_role_propagation]
}

# CreateGateway checks the role's policy engine permissions straight away, and a role policy written seconds earlier
# can still be denied while IAM propagates it. Wait before creating the gateway.
resource "time_sleep" "gateway_role_propagation" {
  create_duration = "30s"

  triggers = {
    policy = aws_iam_role_policy.gateway.policy
  }
}

# ---------- GATEWAY LOGS ----------
# AgentCore doesn't configure gateway logs by default: deliver the gateway's application logs (requests, tool calls,
# target errors) to CloudWatch Logs, in the log group the AgentCore console would create
resource "aws_cloudwatch_log_group" "gateway_logs" {
  name              = "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/${aws_bedrockagentcore_gateway.gateway.gateway_id}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_delivery_source" "gateway" {
  name         = "gateway-logs-${var.identifier}"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_gateway.gateway.gateway_arn
}

resource "aws_cloudwatch_log_delivery_destination" "gateway" {
  name = "gateway-logs-${var.identifier}"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.gateway_logs.arn
  }
}

resource "aws_cloudwatch_log_delivery" "gateway" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway.arn
}

# ---------- GATEWAY POLICY (CEDAR) ----------
resource "aws_bedrockagentcore_policy_engine" "gateway" {
  name        = "policy_engine_${replace(var.identifier, "-", "_")}"
  description = "Access decisions for the helpdesk gateway"
}

locals {
  # The callers' identities, as the gateway sees them (each role's assumed-role ARN)
  gateway_principals = { for k, v in { agent_ecs = aws_iam_role.agent_ecs, agent_runtime = aws_iam_role.agent_runtime, triage = aws_iam_role.triage } : k => "AgentCore::IamEntity::\"arn:aws:sts::${local.account_id}:assumed-role/${v.name}\"" }
  gateway_resource   = "AgentCore::Gateway::\"${aws_bedrockagentcore_gateway.gateway.gateway_arn}\""

  # What each caller may use: a target name covers every tool or path of that target
  gateway_permissions = {
    # agent-ecs: everything
    agent_ecs = "action"
    # agent-runtime: everything except creating an employee
    agent_runtime = "action in [AgentCore::Action::\"tickets\", AgentCore::Action::\"directory___listEmployees\", AgentCore::Action::\"directory___getEmployee\", AgentCore::Action::\"triage\", AgentCore::Action::\"model\"]"
    # triage: only the model
    triage = "action in AgentCore::Action::\"model\""
  }
}

resource "aws_bedrockagentcore_policy" "callers" {
  for_each = local.gateway_permissions

  name             = "allow_${each.key}"
  policy_engine_id = aws_bedrockagentcore_policy_engine.gateway.policy_engine_id

  definition {
    cedar {
      statement = "permit(principal == ${local.gateway_principals[each.key]}, ${each.value}, resource == ${local.gateway_resource});"
    }
  }

  # The policy engine validates the actions against the gateway's targets
  depends_on = [aws_bedrockagentcore_gateway_target.directory, aws_bedrockagentcore_gateway_target.model, aws_bedrockagentcore_gateway_target.tickets, aws_bedrockagentcore_gateway_target.triage]
}

# ========== NATIVE TARGETS ==========

# ---------- TARGET: DIRECTORY (AWS LAMBDA) ----------
locals {
  directory_tools = {
    listEmployees  = { description = "List every employee in the directory.", properties = {}, required = [] }
    getEmployee    = { description = "Get one employee (name, department, device) by identifier.", properties = { id = "Employee identifier, for example 'ana'." }, required = ["id"] }
    createEmployee = { description = "Add an employee to the directory.", properties = { id = "Employee identifier.", name = "Full name.", department = "Department.", device = "Device identifier." }, required = ["id", "name"] }
  }
}

resource "aws_bedrockagentcore_gateway_target" "directory" {
  gateway_identifier = aws_bedrockagentcore_gateway.gateway.gateway_id
  name               = "directory"
  description        = "Employee directory API (AWS Lambda)"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.api_directory.arn

        tool_schema {
          dynamic "inline_payload" {
            for_each = local.directory_tools

            content {
              name        = inline_payload.key
              description = inline_payload.value.description

              input_schema {
                type = "object"

                dynamic "property" {
                  for_each = inline_payload.value.properties

                  content {
                    name        = property.key
                    type        = "string"
                    description = property.value
                    required    = contains(inline_payload.value.required, property.key)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# ---------- TARGET: MODEL (AMAZON BEDROCK) ----------
# Amazon Bedrock's OpenAI-compatible endpoint (bedrock-mantle connector), called with the gateway's role. The connector serves
# both Chat Completions and the Anthropic Messages API; the agents call Claude with the Messages API at <gateway>/inference.
resource "aws_bedrockagentcore_gateway_target" "model" {
  gateway_identifier = aws_bedrockagentcore_gateway.gateway.gateway_id
  name               = "model"
  description        = "Amazon Bedrock models (bedrock-mantle connector)"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    inference {
      connector {
        source {
          connector_id = "bedrock-mantle"
        }
      }
    }
  }
}

# ========== VPC-HOSTED TARGETS (SELF-MANAGED PRIVATE ENDPOINTS) ==========
# Each backend's owner publishes it as a VPC Lattice resource configuration (backends.tf), and the target names that configuration. The gateway calls the backend by its name (<backend>.<domain_name>), which matches the certificate on the backend's load balancer.

# ---------- TARGET: TICKETS (MCP SERVER, AMAZON ECS) ----------
resource "aws_bedrockagentcore_gateway_target" "tickets" {
  gateway_identifier = aws_bedrockagentcore_gateway.gateway.gateway_id
  name               = "tickets"
  description        = "Helpdesk tickets MCP server (Amazon ECS, tickets VPC)"

  private_endpoint {
    self_managed_lattice_resource {
      resource_configuration_identifier = aws_vpclattice_resource_configuration.tickets.arn
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://tickets.${var.domain_name}/mcp"
      }
    }
  }
}

# ---------- TARGET: TRIAGE (A2A AGENT, AMAZON ECS) ----------
resource "aws_bedrockagentcore_gateway_target" "triage" {
  gateway_identifier = aws_bedrockagentcore_gateway.gateway.gateway_id
  name               = "triage"
  description        = "Triage agent (A2A, Amazon ECS, triage VPC)"

  private_endpoint {
    self_managed_lattice_resource {
      resource_configuration_identifier = aws_vpclattice_resource_configuration.triage.arn
    }
  }

  credential_provider_configuration {
    gateway_iam_role {
      service = "bedrock-agentcore"
    }
  }

  target_configuration {
    http {
      passthrough {
        endpoint      = "https://triage.${var.domain_name}"
        protocol_type = "A2A"
      }
    }
  }
}
