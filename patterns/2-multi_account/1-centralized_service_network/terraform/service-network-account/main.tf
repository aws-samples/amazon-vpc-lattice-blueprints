/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/service-network-account/main.tf ---

# AWS Organizations organization
data "aws_organizations_organization" "org" {}

# Obtaining the RAM Resource Share from the Provider Account.
# This single share ("provider-resource-share") contains BOTH the VPC Lattice service and the
# Aurora resource configuration, so we split its ARNs by resource type below.
data "aws_ram_resource_share" "provider" {
  resource_owner = "OTHER-ACCOUNTS"
  name           = "provider-resource-share"
}

locals {
  shared_service_arns        = [for arn in data.aws_ram_resource_share.provider.resource_arns : arn if length(regexall(":service/", arn)) > 0]
  shared_resource_config_arn = [for arn in data.aws_ram_resource_share.provider.resource_arns : arn if length(regexall(":resourceconfiguration/", arn)) > 0][0]

  # Open (allow-all) auth policy.
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

  services = { for k, v in toset(local.shared_service_arns) : k => { identifier = v } }
}

# Associate the shared resource configuration (Aurora) to the service network
resource "aws_vpclattice_service_network_resource_association" "resource_association" {
  resource_configuration_identifier = local.shared_resource_config_arn
  service_network_identifier        = module.vpclattice_service_network.service_network.id
}

# ---------- VPC LATTICE ACCESS LOGGING ----------
# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (service network scope - covers all associated services)
resource "aws_vpclattice_access_log_subscription" "service_network_access_logs" {
  resource_identifier = module.vpclattice_service_network.service_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}
