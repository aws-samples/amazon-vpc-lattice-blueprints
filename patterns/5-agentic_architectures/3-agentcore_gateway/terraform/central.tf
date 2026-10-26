/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/central.tf ---

# ========== VPC LATTICE SERVICE NETWORK ==========
resource "aws_vpclattice_service_network" "service_network" {
  name      = "service-network-${var.identifier}"
  auth_type = "NONE"
}

# ---------- ACCESS LOGGING ----------
# Connections to the resource configurations (the centralized endpoints, including the gateway)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/service-network-${var.identifier}"
  retention_in_days = 7
}

resource "aws_vpclattice_access_log_subscription" "service_network" {
  resource_identifier      = aws_vpclattice_service_network.service_network.arn
  destination_arn          = aws_cloudwatch_log_group.vpclattice_access_logs.arn
  service_network_log_type = "RESOURCE"
}

# ========== CENTRAL AWS SERVICE ENDPOINTS ==========

# ---------- VPC RESOURCES (ENDPOINTS VPC) ----------
module "endpoints_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "endpoints-vpc-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    resourcegateway = { netmask = 24 }
    endpoints       = { netmask = 24 }
  }
}

# Interface VPC endpoints, with private DNS, so the resource gateway resolves each service's standard DNS name to its endpoint. The AgentCore Gateway endpoint (bedrock-agentcore.gateway) resolves every gateway's DNS name.
module "vpc_endpoints" {
  source = "../../../tf_modules/vpc_endpoints"

  identifier                 = var.identifier
  vpc                        = module.endpoints_vpc
  interface_vpc_endpoints    = distinct([for v in values(var.vpc_endpoints) : v.service])
  private_dns                = true
  workload_security_group_id = aws_security_group.resource_gateway_sg.id
}

# ---------- VPC LATTICE CONNECTIVITY (ENDPOINTS VPC) ----------
resource "aws_vpclattice_resource_gateway" "resource_gateway" {
  name                           = "resource-gateway-${var.identifier}"
  vpc_id                         = module.endpoints_vpc.vpc_attributes.id
  subnet_ids                     = values({ for k, v in module.endpoints_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type                = "IPV4"
  resource_config_dns_resolution = "IN_VPC"
  security_group_ids             = [aws_security_group.resource_gateway_sg.id]
}

# One resource configuration per endpoint, with the service's DNS name as its custom domain name. For the AgentCore Gateway, that's the gateway's own DNS name, so agent-ecs uses the same gateway URL as a caller outside a VPC.
resource "aws_vpclattice_resource_configuration" "endpoints" {
  for_each = var.vpc_endpoints

  name                        = "resource-config-${each.key}-${var.identifier}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.resource_gateway.id
  port_ranges                 = ["443"]
  protocol                    = "TCP"
  custom_domain_name          = replace(replace(replace(each.value.domain_name, "<region>", var.aws_region), "<account>", local.account_id), "<gateway-id>", aws_bedrockagentcore_gateway.gateway.gateway_id)

  resource_configuration_definition {
    dns_resource {
      domain_name     = replace(replace(replace(each.value.domain_name, "<region>", var.aws_region), "<account>", local.account_id), "<gateway-id>", aws_bedrockagentcore_gateway.gateway.gateway_id)
      ip_address_type = "IPV4"
    }
  }

  depends_on = [module.vpc_endpoints]
}

resource "aws_vpclattice_service_network_resource_association" "endpoints" {
  for_each = aws_vpclattice_resource_configuration.endpoints

  private_dns_enabled               = true
  resource_configuration_identifier = each.value.id
  service_network_identifier        = aws_vpclattice_service_network.service_network.id

  tags = {
    Name = "resource-association-${each.key}-${var.identifier}"
  }
}

# ---------- SECURITY GROUPS (ENDPOINTS VPC) ----------
resource "aws_security_group" "resource_gateway_sg" {
  name        = "endpoints-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.endpoints_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "resource_gateway_https" {
  security_group_id = aws_security_group.resource_gateway_sg.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = module.endpoints_vpc.vpc_attributes.cidr_block
}
