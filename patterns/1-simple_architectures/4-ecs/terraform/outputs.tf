/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/4-ecs/terraform/outputs.tf ---

output "repository_url" {
  description = "Amazon ECR repository URL."
  value       = aws_ecr_repository.ecr_repository.repository_url
}

output "vpclattice_service_domain_name" {
  description = "VPC Lattice service domain name."
  value       = module.service.services.service.attributes.dns_entry[0].domain_name
}

output "consumer_instance_ids" {
  description = "Consumer EC2 Instance IDs"
  value       = module.consumer_instances.ec2_instances
}
