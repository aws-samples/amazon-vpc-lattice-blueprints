/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/2-multi_account/2-distributed/terraform/provider-account/outputs.tf ---

output "service_domain_name" {
  description = "VPC Lattice service domain name (curl this from a consumer instance)."
  value       = values({ for k, v in module.vpclattice_lambda_service.services : k => v.attributes.dns_entry[0].domain_name })[0]
}

output "aurora_endpoint" {
  description = "Aurora cluster writer endpoint. From a consumer instance it resolves to a VPC Lattice-managed address (129.224.0.x/17) via the shared resource configuration."
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "aurora_secret_arn" {
  description = "ARN of the RDS-managed Aurora master secret. Shared org-wide (secret + KMS policies); the consumer reads it cross-account to authenticate to the database."
  value       = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
}
