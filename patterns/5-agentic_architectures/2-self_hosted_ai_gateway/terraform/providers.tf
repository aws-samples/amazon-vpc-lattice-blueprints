/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/providers.tf ---

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.106.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

# Provider definition
provider "aws" {
  region = var.aws_region
}

provider "awscc" {
  region = var.aws_region
}
