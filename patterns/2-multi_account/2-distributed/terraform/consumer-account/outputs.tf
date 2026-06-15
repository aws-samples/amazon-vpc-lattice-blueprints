/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/2-distributed/terraform/consumer-account/outputs.tf ---

output "consumer_instance_ids" {
  description = "Consumer EC2 Instance IDs"
  value       = module.consumer_instances.ec2_instances
}
