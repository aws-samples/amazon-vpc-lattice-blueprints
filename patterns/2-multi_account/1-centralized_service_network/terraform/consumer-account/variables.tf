/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/consumer-account/variables.tf ---

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

variable "vpc" {
  type        = any
  description = "VPC to create."

  default = {
    cidr_block               = "10.0.0.0/24"
    number_azs               = 2
    private_subnet_netmask   = 28
    endpoints_subnet_netmask = 28
    instance_type            = "t2.micro"
  }
}
