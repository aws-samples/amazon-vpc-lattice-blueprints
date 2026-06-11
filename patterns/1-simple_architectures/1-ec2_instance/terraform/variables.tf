/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/1-ec2_instance/terraform/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "ec2-instance-target"
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

variable "custom_domain_name" {
  type        = string
  description = "Custom domain name for VPC Lattice service2."
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for VPC Lattice service2."
}

variable "hosted_zone_name" {
  type        = string
  description = "Private Hostes Zone name - for service2's DNS resolution configuration."
}
