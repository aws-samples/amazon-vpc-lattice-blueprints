/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/6-rds/terraform/main.tf ---

# ---------- VPC RESOURCE ----------
# Resource gateway
resource "aws_vpclattice_resource_gateway" "resource_gateway" {
  name               = "${var.identifier}-rgw"
  vpc_id             = module.provider_vpc.vpc_attributes.id
  subnet_ids         = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type    = "DUALSTACK"
  security_group_ids = [aws_security_group.provider_rgw_sg.id]
}

# Resource configuration
resource "aws_vpclattice_resource_configuration" "resource_configuration" {
  name = "${var.identifier}-rcg"
  type = "ARN"

  resource_gateway_identifier = aws_vpclattice_resource_gateway.resource_gateway.id

  resource_configuration_definition {
    arn_resource {
      arn = aws_rds_cluster.aurora_cluster.arn
    }
  }
}

# Resource association (service network)
resource "aws_vpclattice_service_network_resource_association" "resource_association" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.resource_configuration.id
  service_network_identifier        = module.service_network.service_network.id
}

# ---------- VPC LATTICE SERVICE NETWORK ----------
module "service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name      = "service-network-${var.identifier}"
    auth_type = "NONE"
  }
}

# ---------- CONSUMER VPC AND EC2 INSTANCES ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

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

resource "aws_vpclattice_service_network_vpc_association" "vpc_assocation" {
  vpc_identifier             = module.consumer_vpc.vpc_attributes.id
  service_network_identifier = module.service_network.service_network.id
  security_group_ids         = [aws_security_group.vpclattice_sg.id]
  private_dns_enabled        = true

  dns_options {
    private_dns_preference = "ALL_DOMAINS"
  }
}

module "consumer_instances" {
  source = "../../../tf_modules/consumer_instance"

  identifier      = var.identifier
  vpc_name        = "consumer_vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# Security Group (VPC Lattice VPC association)
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

# ---------- PRIVATE HOSTED ZONE ----------
# # Private Hosted Zone
# resource "aws_route53_zone" "private_hosted_zone" {
#   name = "var.hosted_zone_name"

#   vpc {
#     vpc_id = module.consumer_vpc.vpc_attributes.id
#   }
# }

# ---------- PROVIDER (AURORA INSTANCE) ----------
# Provider VPC
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "provider-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  subnets = {
    resourcegateway = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
    database = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

data "aws_vpc" "provider_vpc" {
  id = module.provider_vpc.vpc_attributes.id
}

# DB Subnet Group
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group-${var.identifier}"
  subnet_ids = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "database" })
}

# Aurora Cluster
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier     = "aurora-${var.identifier}"
  engine                 = var.aurora_db_configuration.engine
  database_name          = var.aurora_db_configuration.db_name
  master_username        = var.aurora_db_configuration.username
  master_password        = var.aurora_db_configuration.password
  db_subnet_group_name   = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]
  skip_final_snapshot    = true
}

# Aurora Instance
resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "aurora-instance-${var.identifier}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = var.aurora_db_configuration.instance_class
  engine             = aws_rds_cluster.aurora_cluster.engine
}

# Security Group: Resource Configuration
resource "aws_security_group" "provider_rgw_sg" {
  name        = "provider-rgw-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_db_ipv4" {
  security_group_id = aws_security_group.provider_rgw_sg.id

  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_db_ipv6" {
  security_group_id = aws_security_group.provider_rgw_sg.id

  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"
  cidr_ipv6   = data.aws_vpc.provider_vpc.ipv6_cidr_block
}

# Security Group: RDS
resource "aws_security_group" "aurora_sg" {
  name        = "aurora-security-group-${var.identifier}"
  description = "Security group for RDS instance"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "provider_allowing_ingress_rcg" {
  security_group_id = aws_security_group.aurora_sg.id

  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.provider_rgw_sg.id
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any_ipv4" {
  security_group_id = aws_security_group.aurora_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any_ipv6" {
  security_group_id = aws_security_group.aurora_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}
