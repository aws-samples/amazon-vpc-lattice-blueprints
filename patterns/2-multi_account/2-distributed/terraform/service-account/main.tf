/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/2-distributed/terraform/service-account/main.tf ---

# AWS Organizations organization
data "aws_organizations_organization" "org" {}

# ---------- VPC LATTICE SERVICE ----------
# VPC Lattice Module
module "vpc_lattice_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  services = {
    lambdaservice = {
      name        = "lambda-service-${var.identifier}"
      auth_type   = "AWS_IAM"
      auth_policy = local.auth_policy

      listeners = {
        https_listener = {
          name     = "httpslistener"
          port     = 443
          protocol = "HTTPS"
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
    resource_share_name       = "service-resource-share"
    allow_external_principals = false
    principals                = [data.aws_organizations_organization.org.arn]
    share_services            = ["lambdaservice"]
  }
}

# VPC Lattice service Auth Policy
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

# ---------- LAMBDA FUNCTION ----------
# AWS Lambda Function
resource "aws_lambda_function" "lambda" {
  function_name    = "lambda_function-${var.identifier}"
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

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = data.aws_iam_policy_document.lambda_policy_document.json
}

data "aws_iam_policy_document" "lambda_policy_document" {
  statement {
    sid    = "LambdaLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy_attachment" "lambda_policy_attachment" {
  name       = "lambda-logging-policy-attachment"
  roles      = [aws_iam_role.lambda_role.id]
  policy_arn = aws_iam_policy.lambda_policy.arn
}
