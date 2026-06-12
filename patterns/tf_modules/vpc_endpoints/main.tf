/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/tf_modules/vpc_endpoints/main.tf ---

# Data source (AWS Region)
data "aws_region" "current" {}

# Data source (VPC)
data "aws_vpc" "vpc" {
  id = var.vpc.vpc_attributes.id
}

# ---------- VPC ENDPOINTS (INTERFACE) ----------
resource "aws_vpc_endpoint" "interface_vpc_endpoints" {
  for_each = toset(var.interface_vpc_endpoints)

  vpc_id              = var.vpc.vpc_attributes.id
  subnet_ids          = values({ for k, v in var.vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "endpoints" })
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = var.private_dns
}

# ---------- VPC ENDPOINT (S3 - GATEWAY) ----------
resource "aws_vpc_endpoint" "s3_endpoint" {
  count = var.create_s3_gateway ? 1 : 0

  vpc_id          = var.vpc.vpc_attributes.id
  route_table_ids = values({ for k, v in var.vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
  service_name    = "com.amazonaws.${data.aws_region.current.region}.s3"
}

# ---------- SECURITY GROUP (INTERFACE VPC ENDPOINTS) ----------
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "endpoints-vpc-endpoint-security-group-${var.identifier}"
  description = "VPC endpoint Security Group"
  vpc_id      = var.vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.workload_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_any" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}
