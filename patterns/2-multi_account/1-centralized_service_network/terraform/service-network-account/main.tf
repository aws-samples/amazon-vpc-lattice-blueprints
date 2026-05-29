/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/service-network-account/main.tf ---

# AWS Organizations organization
data "aws_organizations_organization" "org" {}

# Obtaining RAM Resource Share from Service Account
data "aws_ram_resource_share" "vpclattice_service" {
  resource_owner = "OTHER-ACCOUNTS"
  name           = "service-resource-share"
}

# ---------- AMAZON VPC LATTICE (SERVICE NETWORK) ----------
# VPC Lattice Module
module "vpclattice_service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name        = "service-network-${var.identifier}"
    auth_type   = "AWS_IAM"
    auth_policy = local.auth_policy
  }

  ram_share = {
    resource_share_name       = "service-network-resource-share"
    allow_external_principals = true
    principals                = [data.aws_organizations_organization.org.arn]
    share_services            = []
  }

  services = { for k, v in toset(data.aws_ram_resource_share.vpclattice_service.resource_arns) : k => { identifier = v } }
}

# VPC Lattice service network Auth Policy
locals {
  auth_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "*"
        Effect    = "Allow"
        Principal = "*"
        Resource  = "*"
      }
    ]
  })
}
