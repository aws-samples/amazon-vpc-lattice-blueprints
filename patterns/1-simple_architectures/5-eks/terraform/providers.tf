/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/5-eks/terraform/providers.tf ---

# EKS is the only multi-provider pattern: AWS + helm (to install the AWS Gateway
# API Controller). The CRDs and Gateway/HTTPRoute + sample app are applied via a
# local-exec kubectl provisioner (see main.tf), so no kubernetes/kubectl
# providers are needed. Core floor is >= 1.4.0 (the `terraform_data` resource),
# higher than the repo-wide 1.3.0 - see CONVENTIONS.md section 3.
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    # helm v2.x (uses the kubernetes {} block syntax in the provider below).
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

# Provider definition
provider "aws" {
  region = var.aws_region
}

# ---------- HELM PROVIDER ----------
# Authenticates to the EKS cluster via the exec plugin (`aws eks get-token`).
# Validates statically without a live cluster: the block only references the
# cluster resource attributes and does not contact the API server during
# `terraform validate`.
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.aws_region]
    }
  }
}
