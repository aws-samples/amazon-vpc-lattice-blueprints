/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/3-advanced_architectures/1-centralized_vpc_endpoints/terraform/outputs.tf ---

output "instance_ids" {
  description = "EC2 Instance IDs."
  value       = [for v in aws_instance.ec2_instance : v.id]
}
