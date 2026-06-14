/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/5-eks/terraform/variables.tf ---

variable "identifier" {
  type        = string
  description = "Project identifier."

  default = "eks"
}

variable "aws_region" {
  type        = string
  description = "AWS Region to use in the example."

  default = "eu-west-1"
}

# ---------- EKS CLUSTER CONFIGURATION ----------
# Kubernetes control-plane version for the EKS cluster.
variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster."

  default = "1.35"
}

variable "vpc" {
  type        = any
  description = "Information about the VPCs."

  default = {
    number_azs               = 2
    cidr_block               = "10.0.0.0/16"
    private_subnet_netmask   = 24
    endpoints_subnet_netmask = 24
    public_subnet_netmask    = 28
    instance_type            = "t3.micro"
  }
}

# ---------- GATEWAY API CONFIGURATION ----------
variable "gateway_api_crds_version" {
  type        = string
  description = "Upstream Kubernetes Gateway API standard CRD bundle version to install (gateway.networking.k8s.io)."

  default = "v1.1.0"
}
