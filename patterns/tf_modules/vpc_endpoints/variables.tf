/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/tf_modules/vpc_endpoints/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."
}

variable "vpc" {
  type        = any
  description = "VPC information."
}

variable "interface_vpc_endpoints" {
  description = "Interface VPC endpoints (AWS service names) to create."
  type        = list(string)
}

variable "private_dns" {
  description = "Private DNS configuration (for Interface endpoints)."
  type        = bool

  default = true
}

variable "workload_security_group_id" {
  description = "Security Group ID associated to workload (for Ingress SG rule)."
  type        = string
}

variable "create_s3_gateway" {
  description = "Creation of S3 gateway endpoint."
  type        = bool

  default = false
}
