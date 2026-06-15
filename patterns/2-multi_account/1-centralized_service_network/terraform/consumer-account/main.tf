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
  vpc_egress_only_internet_gateway     = true
  az_count                             = var.vpc.number_azs

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
      connect_to_eigw  = true
    }
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

# VPC Lattice service network VPC association
resource "aws_vpclattice_service_network_vpc_association" "vpc_association" {
  vpc_identifier             = module.consumer_vpc.vpc_attributes.id
  service_network_identifier = data.aws_ram_resource_share.vpclattice_service.resource_arns[0]
  security_group_ids         = [aws_security_group.vpclattice_sg.id]
  private_dns_enabled        = true

  dns_options {
    private_dns_preference = "ALL_DOMAINS"
  }
}

# ---------- EC2 INSTANCES ----------
module "consumer_instances" {
  source = "../../../../tf_modules/consumer_instance"

  identifier            = var.identifier
  vpc_name              = "consumer-vpc"
  vpc                   = module.consumer_vpc
  vpc_information       = var.vpc
  instance_profile_name = aws_iam_instance_profile.consumer_instance.name
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

# Allow the consumer instances to reach the Aurora resource configuration (MySQL) through VPC Lattice
resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_instances_mysql" {
  security_group_id = aws_security_group.vpclattice_sg.id

  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}

# ---------- VPC ENDPOINT (SECRETS MANAGER) ----------
resource "aws_security_group" "secretsmanager_endpoint_sg" {
  name        = "consumer-vpc-secretsmanager-endpoint-security-group-${var.identifier}"
  description = "Secrets Manager interface endpoint Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "secretsmanager_endpoint_ingress_https" {
  security_group_id = aws_security_group.secretsmanager_endpoint_sg.id

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.consumer_vpc.vpc_attributes.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = values({ for k, v in module.consumer_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "endpoints" })
  security_group_ids  = [aws_security_group.secretsmanager_endpoint_sg.id]
}

# ---------- CONSUMER INSTANCE IAM (read the shared Aurora secret) ----------
data "aws_iam_policy_document" "consumer_instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Permissions to read the cross-account, RDS-managed Aurora secret and decrypt it.
data "aws_iam_policy_document" "consumer_read_secret" {
  statement {
    sid       = "ReadSharedAuroraSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:rds!*"]
  }

  statement {
    sid       = "DecryptSharedAuroraSecret"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "consumer_instance" {
  name               = "consumer-instance-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.consumer_instance_assume_role.json
}

resource "aws_iam_role_policy" "consumer_read_secret" {
  name   = "read-shared-aurora-secret"
  role   = aws_iam_role.consumer_instance.id
  policy = data.aws_iam_policy_document.consumer_read_secret.json
}

resource "aws_iam_instance_profile" "consumer_instance" {
  name = "consumer-instance-profile-${var.identifier}"
  role = aws_iam_role.consumer_instance.name
}
