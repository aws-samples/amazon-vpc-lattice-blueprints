/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/6-rds/terraform/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "vpc-resources-rds"
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
    instance_type            = "t2.micro"
  }
}

variable "aurora_db_configuration" {
  type        = map(string)
  description = "RDS instance configuration."

  default = {
    engine         = "aurora-mysql"
    instance_class = "db.t3.medium"
    db_name        = "mydb"
    username       = "admin"
    password       = "admin123"
  }
}