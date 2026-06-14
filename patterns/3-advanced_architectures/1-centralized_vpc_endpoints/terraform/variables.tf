/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/3-advanced_architectures/1-centralized_vpc_endpoints/terraform/variables.tf ---

variable "identifier" {
  description = "Pattern identifier."
  type        = string

  default = "endpoints"
}

variable "aws_region" {
  description = "AWS Region to build the pattern."
  type        = string

  default = "eu-west-1"
}

variable "vpc_endpoints" {
  description = "VPC endpoints (AWS services) to centralized using VPC resources."
  type        = list(string)

  default = ["ssm", "ssmmessages", "ec2messages", "sts"]
}
