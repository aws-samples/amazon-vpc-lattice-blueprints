/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/service-network-account/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "centralized-share"
}

variable "aws_region" {
  type        = string
  description = "AWS Region."

  default = "eu-west-1"
}
