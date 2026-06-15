/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/1-centralized_service_network/terraform/provider-account/main.tf ---

# AWS Organizations organization
data "aws_organizations_organization" "org" {}

# Open (allow-all) auth policy.
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

# ---------- LAMBDA TARGET ----------
# AWS Lambda function (service target - returns a JSON greeting)
resource "aws_lambda_function" "lambda" {
  function_name    = "lambda-function-${var.identifier}"
  filename         = "lambda_function.zip"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256

  role    = aws_iam_role.lambda_role.arn
  runtime = "python3.14"
  handler = "lambda_function.lambda_handler"
}

data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "./lambda_function.py"
  output_path = "lambda_function.zip"
}

# Lambda IAM role (basic execution / logging)
resource "aws_iam_role" "lambda_role" {
  name               = "lambda-role-${var.identifier}"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC Lattice service
module "vpclattice_lambda_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  services = {
    lambdaservice = {
      name        = "lambda-service-${var.identifier}"
      auth_type   = "AWS_IAM"
      auth_policy = local.auth_policy

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              lambdatarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambdatarget = {
      type = "LAMBDA"
      targets = {
        lambdafunction = { id = aws_lambda_function.lambda.arn }
      }
    }
  }

  ram_share = {
    resource_share_name       = "provider-resource-share"
    allow_external_principals = false
    principals                = [data.aws_organizations_organization.org.arn]
    share_services            = ["lambdaservice"]
  }
}

# ---------- AURORA DATABASE (VPC RESOURCE) ----------
# VPC
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "provider-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  subnets = {
    resourcegateway = {
      netmask          = var.vpc.rgw_subnet_netmask
      assign_ipv6_cidr = true
    }
    database = {
      netmask          = var.vpc.database_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

data "aws_vpc" "provider_vpc" {
  id = module.provider_vpc.vpc_attributes.id
}

# Resource gateway
resource "aws_vpclattice_resource_gateway" "resource_gateway" {
  name               = "resource-gateway-${var.identifier}"
  vpc_id             = module.provider_vpc.vpc_attributes.id
  subnet_ids         = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type    = "DUALSTACK"
  security_group_ids = [aws_security_group.resource_gateway_sg.id]
}

# Resource gateway SG (reaches Aurora on 3306)
resource "aws_security_group" "resource_gateway_sg" {
  name        = "provider-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "rgw_egress_db_ipv4" {
  security_group_id = aws_security_group.resource_gateway_sg.id

  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "rgw_egress_db_ipv6" {
  security_group_id = aws_security_group.resource_gateway_sg.id

  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"
  cidr_ipv6   = data.aws_vpc.provider_vpc.ipv6_cidr_block
}

# Aurora database
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group-${var.identifier}"
  subnet_ids = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "database" })
}

# Credentials are managed by RDS and stored in AWS Secrets Manager. No password is ever defined in code.
# The secret is encrypted with a customer-managed KMS key (below) so it can be shared cross-account.
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier            = "aurora-${var.identifier}"
  engine                        = var.aurora_db_configuration.engine
  engine_version                = var.aurora_db_configuration.engine_version
  database_name                 = var.aurora_db_configuration.db_name
  master_username               = var.aurora_db_configuration.username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.aurora_secret.key_id
  db_subnet_group_name          = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids        = [aws_security_group.aurora_sg.id]
  storage_encrypted             = true
  skip_final_snapshot           = true
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "aurora-instance-${var.identifier}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = var.aurora_db_configuration.instance_class
  engine             = aws_rds_cluster.aurora_cluster.engine
}

# Aurora SG (ingress from the resource gateway)
resource "aws_security_group" "aurora_sg" {
  name        = "provider-vpc-aurora-security-group-${var.identifier}"
  description = "Aurora cluster Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "aurora_ingress_resource_gateway" {
  security_group_id = aws_security_group.aurora_sg.id

  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.resource_gateway_sg.id
}

resource "aws_vpc_security_group_egress_rule" "aurora_egress_ipv4" {
  security_group_id = aws_security_group.aurora_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "aurora_egress_ipv6" {
  security_group_id = aws_security_group.aurora_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

# Resource configuration
resource "aws_vpclattice_resource_configuration" "resource_configuration" {
  name = "resource-config-${var.identifier}"
  type = "ARN"

  resource_gateway_identifier = aws_vpclattice_resource_gateway.resource_gateway.id

  resource_configuration_definition {
    arn_resource {
      arn = aws_rds_cluster.aurora_cluster.arn
    }
  }
}

# RAM share (we re-use the RAM resource share created for the VPC Lattice service)
resource "aws_ram_resource_association" "resource_config" {
  resource_share_arn = module.vpclattice_lambda_service.ram_resource_share.id
  resource_arn       = aws_vpclattice_resource_configuration.resource_configuration.arn
}

# ---------- AURORA SECRET: CROSS-ACCOUNT SHARING ----------
# The consumer account reads the RDS-managed master secret directly (by ARN). Cross-account access requires:
# (1) a customer-managed KMS key
# (2) a resource policy on the secret.
data "aws_caller_identity" "current" {}

# Customer-managed KMS key that encrypts the Aurora master secret
resource "aws_kms_key" "aurora_secret" {
  description             = "Encrypts the Aurora master secret for ${var.identifier} (shared org-wide)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.aurora_secret_kms.json
}

data "aws_iam_policy_document" "aurora_secret_kms" {
  # Account root retains full control of the key.
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Any principal in the Organization can decrypt (to read the shared secret).
  statement {
    sid       = "AllowOrganizationDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.org.id]
    }
  }
}

# Resource policy on the RDS-managed secret: allow the Organization to read it.
resource "aws_secretsmanager_secret_policy" "aurora_secret" {
  secret_arn = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
  policy     = data.aws_iam_policy_document.aurora_secret_resource.json
}

data "aws_iam_policy_document" "aurora_secret_resource" {
  statement {
    sid       = "AllowOrganizationRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.org.id]
    }
  }
}
