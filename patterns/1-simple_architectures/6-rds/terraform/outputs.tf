/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/6-rds/terraform/outputs.tf ---

# Consumer EC2 instance IDs. Use these with Session Manager or EC2 Instance
# Connect to log in and run the documented connectivity tests (resolve the
# Aurora endpoint -> VPC Lattice-managed address, then connect with the MySQL client).
output "consumer_instance_ids" {
  description = "Consumer EC2 instance IDs (use with Session Manager / EC2 Instance Connect)."
  value       = module.consumer_instances.ec2_instances
}

# Aurora cluster endpoints. From the consumer instance these domain names
# resolve to VPC Lattice-managed addresses (129.224.0.x/17 / fd00:ec2:80::/64)
# thanks to the service network VPC association private DNS.
output "aurora" {
  description = "Aurora cluster endpoints resolved through VPC Lattice from the consumer VPC."
  value = {
    writer = aws_rds_cluster.aurora_cluster.endpoint
    reader = aws_rds_cluster.aurora_cluster.reader_endpoint
  }
}

# VPC Lattice resource configuration reference. The resource configuration
# (ARN type, pointing at the Aurora cluster) does not expose a generated domain
# name attribute; the consumer resolves the Aurora endpoint above. The id/arn
# are surfaced here for inspection and troubleshooting of the resource path.
output "resource_configuration" {
  description = "VPC Lattice resource configuration id and ARN (ARN type, targets the Aurora cluster)."
  value = {
    id  = aws_vpclattice_resource_configuration.resource_configuration.id
    arn = aws_vpclattice_resource_configuration.resource_configuration.arn
  }
}

# ARN reference to the RDS-managed primary password secret in AWS Secrets
# Manager. This is the secret ARN only, never the secret value. Retrieve the
# credentials from the consumer instance with the AWS CLI / Secrets Manager API
# to connect to Aurora.
output "rds_primary_user_secret_arn" {
  description = "ARN of the RDS-managed primary user secret in AWS Secrets Manager (reference only, not the secret value)."
  value       = aws_rds_cluster.aurora_cluster.master_user_secret[0].secret_arn
}
