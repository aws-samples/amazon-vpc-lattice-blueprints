/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/variables.tf ---

variable "identifier" {
  description = "Pattern identifier."
  type        = string

  default = "agentic-direct"
}

variable "aws_region" {
  description = "AWS Region to build the pattern."
  type        = string

  default = "eu-west-1"
}

variable "model_id" {
  description = "Amazon Bedrock model (or inference profile) ID used by the agents. Use a model your organization approves for your use case."
  type        = string

  default = "eu.anthropic.claude-haiku-5-5"
}

variable "vpc_endpoints" {
  description = "AWS services centralized in the endpoints VPC (key = short name used in resource names, value = interface endpoint service suffix and DNS name)."
  type = map(object({
    service     = string
    domain_name = string
  }))

  # domain_name placeholders: <region> and <account> are replaced in the resource configurations (central.tf)
  default = {
    bedrock   = { service = "bedrock-runtime", domain_name = "bedrock-runtime.<region>.amazonaws.com" }
    agentcore = { service = "bedrock-agentcore", domain_name = "bedrock-agentcore.<region>.amazonaws.com" }
    registry  = { service = "agent-registry", domain_name = "agent-registry.<region>.api.aws" }
    ecr-api   = { service = "ecr.api", domain_name = "api.ecr.<region>.amazonaws.com" }
    ecr-dkr   = { service = "ecr.dkr", domain_name = "<account>.dkr.ecr.<region>.amazonaws.com" }
    logs      = { service = "logs", domain_name = "logs.<region>.amazonaws.com" }
    sts       = { service = "sts", domain_name = "sts.<region>.amazonaws.com" }
    ssm-msgs  = { service = "ssmmessages", domain_name = "ssmmessages.<region>.amazonaws.com" }
  }
}

variable "hosted_zone_name" {
  description = "Domain of the VPC Lattice services' custom domain names (for example, example.com gives mcp-tickets.example.com). Each consumer VPC gets a private hosted zone with this name."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the AWS Certificate Manager (ACM) certificate for the services' HTTPS listeners. It must cover *.<hosted_zone_name>."
  type        = string
}
