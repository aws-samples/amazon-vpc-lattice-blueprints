/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/tf_modules/consumer_instance/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."
}

variable "vpc_name" {
  type        = string
  description = "Name of the VPC where the EC2 instance(s) are created."
}

variable "vpc" {
  type        = any
  description = "VPC resources."
}

variable "vpc_information" {
  type        = any
  description = "VPC information (defined in root variables.tf file)."
}

variable "instance_profile_name" {
  type        = string
  description = "Optional IAM instance profile name to attach to the consumer instances. Defaults to none (no profile attached)."
  default     = null
}
