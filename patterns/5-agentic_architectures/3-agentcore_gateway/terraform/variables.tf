/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/variables.tf ---

variable "identifier" {
  description = "Pattern identifier."
  type        = string

  default = "agentic-core"
}

variable "aws_region" {
  description = "AWS Region to build the pattern."
  type        = string

  default = "eu-west-1"
}

variable "model_id" {
  description = "Model ID the gateway's inference target serves, as listed by Amazon Bedrock's OpenAI-compatible endpoint (bedrock-mantle). Use a model your organization approves for your use case."
  type        = string

  default = "anthropic.claude-haiku-4-5"
}

variable "vpc_endpoints" {
  description = "AWS services centralized in the endpoints VPC (key = short name used in resource names, value = interface endpoint service suffix and DNS name)."
  type = map(object({
    service     = string
    domain_name = string
  }))

  # domain_name placeholders: <region>, <account> and <gateway-id> are replaced in the resource configurations (central.tf)
  default = {
    gateway  = { service = "bedrock-agentcore.gateway", domain_name = "<gateway-id>.gateway.bedrock-agentcore.<region>.amazonaws.com" }
    registry = { service = "agent-registry", domain_name = "agent-registry.<region>.api.aws" }
    ecr-api  = { service = "ecr.api", domain_name = "api.ecr.<region>.amazonaws.com" }
    ecr-dkr  = { service = "ecr.dkr", domain_name = "<account>.dkr.ecr.<region>.amazonaws.com" }
    logs     = { service = "logs", domain_name = "logs.<region>.amazonaws.com" }
    sts      = { service = "sts", domain_name = "sts.<region>.amazonaws.com" }
    ssm-msgs = { service = "ssmmessages", domain_name = "ssmmessages.<region>.amazonaws.com" }
  }
}

variable "domain_name" {
  description = "Domain of the VPC-hosted backends' names (for example, example.com gives tickets.example.com and triage.example.com). The gateway calls the backends by these names; no hosted zone is needed."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the AWS Certificate Manager (ACM) public certificate for the backends' load balancers. It must cover *.<domain_name>, and be in the account and Region you deploy to."
  type        = string
}
