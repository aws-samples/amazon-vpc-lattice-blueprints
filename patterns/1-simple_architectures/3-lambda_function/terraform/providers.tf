/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/3-lambda_function/terraform/providers.tf ---

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.7.0"
    }
  }
}

# Provider definition
provider "aws" {
  region = var.aws_region
}
