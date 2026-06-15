/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/5-eks/terraform/outputs.tf ---

output "cluster_name" {
  description = "Amazon EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "configure_kubectl" {
  description = "Command to update your kubeconfig for kubectl access to the EKS cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}

output "repository_url" {
  description = "Amazon ECR repository URL."
  value       = aws_ecr_repository.eks_app.repository_url
}

output "consumer_instance_ids" {
  description = "Consumer EC2 instance IDs (use with EC2 Instance Connect to curl the EKS-backed service through VPC Lattice)."
  value       = module.consumer_instances.ec2_instances
}
