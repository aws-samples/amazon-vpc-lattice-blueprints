/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/2-distributed/terraform/consumer-account/main.tf ---

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

  services = { for k, v in toset(data.aws_ram_resource_share.vpclattice_service.resource_arns) : k => { identifier = v } }
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

# ---------- CONSUMER VPC ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  vpc_lattice = {
    service_network_identifier = module.vpclattice_service_network.service_network.id
    security_group_ids         = [aws_security_group.vpclattice_sg.id]
  }

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
    }
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

# ---------- EC2 INSTANCES ----------
module "consumer_instances" {
  source = "../../../../tf_modules/consumer_instance"

  identifier      = var.identifier
  vpc_name        = "consumer-vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# ---------- SECURITY GROUP (VPC LATTICE ASSOCIATION) ----------
resource "aws_security_group" "vpclattice_sg" {
  name        = "consumer-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_instances_https" {
  security_group_id = aws_security_group.vpclattice_sg.id

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}
