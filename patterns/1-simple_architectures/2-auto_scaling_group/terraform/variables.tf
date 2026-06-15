/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/2-auto_scaling_group/terraform/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "asg-target"
}

variable "aws_region" {
  type        = string
  description = "AWS Region to use in the example."

  default = "eu-west-1"
}

variable "vpc" {
  type        = any
  description = "Information about the VPCs."

  default = {
    number_azs               = 2
    cidr_block               = "10.0.0.0/16"
    private_subnet_netmask   = 24
    endpoints_subnet_netmask = 24
    instance_type            = "t3.micro"
  }
}
