/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/consumer-account/main.tf ---

# Obtaining RAM Resource Share from Service Network Account
data "aws_ram_resource_share" "vpclattice_service" {
  resource_owner = "OTHER-ACCOUNTS"
  name           = "service-network-resource-share"
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
    service_network_identifier = data.aws_ram_resource_share.vpclattice_service.resource_arns[0]
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
  vpc_name        = "consumer_vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# ---------- SECURITY GROUP (VPC LATTICE ASSOCIATION) ----------
resource "aws_security_group" "vpclattice_sg" {
  name        = "consumer_vpc-vpclattice-security-group-${var.identifier}"
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