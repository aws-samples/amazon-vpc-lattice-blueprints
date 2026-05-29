/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/3-lambda_function/terraform/main.tf ---

# Data source: Amazon VPC Lattice prefix list (IPv4 and IPv6)
data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv4" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv6" {
  name = "com.amazonaws.${var.aws_region}.ipv6.vpc-lattice"
}

# ---------- VPC LATTICE RESOURCES ----------
# VPC Lattice service network
module "service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name      = "service-network-${var.identifier}"
    auth_type = "NONE"
  }
}

# VPC Lattice service - VPC Lattice-generated FQDN, HTTPS listener, Instance type target
module "service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = module.service_network.service_network.id
  }

  services = {
    service = {
      name      = "service-${var.identifier}"
      auth_type = "NONE"

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              lamdbatarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lamdbatarget = {
      type = "LAMBDA"
      targets = {
        lambdafunction = { id = aws_lambda_function.lambda.arn }
      }
    }
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

  vpc_lattice = {
    service_network_identifier = module.service_network.service_network.id
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

# ---------- PROVIDER LAMBDA FUNCTION ----------
# AWS Lambda Function
resource "aws_lambda_function" "lambda" {
  function_name    = "lambda_function"
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

# IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "lambda-route53-role"
  path = "/"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}