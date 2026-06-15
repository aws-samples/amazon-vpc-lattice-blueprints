/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/2-distributed/terraform/provider-account/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "distributed-share"
}

variable "aws_region" {
  type        = string
  description = "AWS Region."

  default = "eu-west-1"
}

variable "vpc" {
  type        = any
  description = "Provider VPC configuration (hosts the resource gateway and Aurora)."

  default = {
    number_azs              = 2
    cidr_block              = "10.0.0.0/16"
    rgw_subnet_netmask      = 24
    database_subnet_netmask = 24
  }
}

variable "aurora_db_configuration" {
  type        = map(string)
  description = "Aurora configuration. Primary credentials are managed by RDS in AWS Secrets Manager; no password is stored here."
  sensitive   = true

  default = {
    engine         = "aurora-mysql"
    engine_version = "8.0.mysql_aurora.3.12.0"
    instance_class = "db.t3.medium"
    db_name        = "mydb"
    username       = "admin"
  }
}
