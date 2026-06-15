/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/tf_modules/vpc_endpoints/outputs.tf ---

output "interface_vpc_endpoints" {
  description = "VPC Endpoints (Interface)"
  value       = aws_vpc_endpoint.interface_vpc_endpoints
}
