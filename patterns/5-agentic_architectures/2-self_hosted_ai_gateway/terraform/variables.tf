/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/variables.tf ---

variable "identifier" {
  description = "Pattern identifier."
  type        = string

  default = "agentic-gateway"
}

variable "aws_region" {
  description = "AWS Region to build the pattern."
  type        = string

  default = "eu-west-1"
}

variable "model_id" {
  description = "Amazon Bedrock model (or inference profile) ID the AI gateway serves as helpdesk-llm. Use a model your organization approves for your use case."
  type        = string

  default = "eu.anthropic.claude-haiku-5-5"
}

variable "vpc_endpoints" {
  description = "AWS services centralized in the endpoints VPC (key = short name used in resource names, value = interface endpoint service suffix, DNS name, and the service networks that reach it)."
  type = map(object({
    service     = string
    domain_name = string
    networks    = list(string) # "agents", "backends", or both
  }))

  # domain_name placeholders: <region> and <account> are replaced in the resource configurations (central.tf)
  # networks: 'agents' holds what the agents and the triage agent call directly (registry, secrets, images, logs, ECS Exec)
  # 'backends' holds what the gateway calls (the model, secrets, images, logs). The model is only in 'backends', so every model call goes through the gateway.
  default = {
    registry = { service = "agent-registry", domain_name = "agent-registry.<region>.api.aws", networks = ["agents"] }
    bedrock  = { service = "bedrock-runtime", domain_name = "bedrock-runtime.<region>.amazonaws.com", networks = ["backends"] }
    ecr-api  = { service = "ecr.api", domain_name = "api.ecr.<region>.amazonaws.com", networks = ["agents", "backends"] }
    ecr-dkr  = { service = "ecr.dkr", domain_name = "<account>.dkr.ecr.<region>.amazonaws.com", networks = ["agents", "backends"] }
    logs     = { service = "logs", domain_name = "logs.<region>.amazonaws.com", networks = ["agents", "backends"] }
    sts      = { service = "sts", domain_name = "sts.<region>.amazonaws.com", networks = ["agents", "backends"] }
    secrets  = { service = "secretsmanager", domain_name = "secretsmanager.<region>.amazonaws.com", networks = ["agents", "backends"] }
    ssm-msgs = { service = "ssmmessages", domain_name = "ssmmessages.<region>.amazonaws.com", networks = ["agents"] }
  }
}

variable "hosted_zone_name" {
  description = "Domain of the VPC Lattice services' custom domain names (for example, example.com gives ai-gateway.example.com and mcp-tickets.example.com). Each VPC that calls a service gets a private hosted zone with this name."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the AWS Certificate Manager (ACM) certificate for the services' HTTPS listeners. It must cover *.<hosted_zone_name>."
  type        = string
}
