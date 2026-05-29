/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/6-rds/terraform/outputs.tf ---

output "aurora" {
  value = {
    writer = aws_rds_cluster.aurora_cluster.endpoint
    reader = aws_rds_cluster.aurora_cluster.reader_endpoint
  }
}

output "phz_domain_names" {
  value = {
    writer = replace(aws_rds_cluster.aurora_cluster.endpoint, "/^${aws_rds_cluster.aurora_cluster.cluster_identifier}\\./", "")
    reader = replace(aws_rds_cluster.aurora_cluster.reader_endpoint, "/^${aws_rds_cluster.aurora_cluster.cluster_identifier}\\./", "")
  }
}

# data "awscc_vpclattice_service_network_resource_associations" "resource_associations" {}

# data "awscc_vpclattice_service_network_resource_association" "resource_association_1" {
#     id = tolist(data.awscc_vpclattice_service_network_resource_associations.resource_associations.ids)[1]
# }

# data "awscc_vpclattice_service_network_resource_association" "resource_association_2" {
#     id = tolist(data.awscc_vpclattice_service_network_resource_associations.resource_associations.ids)[2]
# }

# output "resource_associations" {
#     value = toset(data.awscc_vpclattice_service_network_resource_associations.resource_associations.ids)
# }

# output "resource_association" {
#     value = {
#         one = data.awscc_vpclattice_service_network_resource_association.resource_association_1
#         two = data.awscc_vpclattice_service_network_resource_association.resource_association_2
#     }
# }