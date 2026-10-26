/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/central.tf ---

# ========== VPC LATTICE SERVICE NETWORK ==========

# ---------- SERVICE NETWORK AND AUTH POLICY ----------
resource "aws_vpclattice_service_network" "service_network" {
  name      = "service-network-${var.identifier}"
  auth_type = "AWS_IAM"
}

# Service network auth policy: only authenticated (SigV4-signed) requests.
resource "aws_vpclattice_auth_policy" "service_network" {
  resource_identifier = aws_vpclattice_service_network.service_network.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAnyAuthenticatedPrincipal"
      Effect    = "Allow"
      Principal = "*"
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "*"
      Condition = {
        StringNotEqualsIgnoreCase = {
          "aws:PrincipalType" = "anonymous"
        }
      }
    }]
  })
}

# ---------- ACCESS LOGGING ----------
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Requests to the VPC Lattice services (caller principal, auth decision, path, status code)
resource "aws_vpclattice_access_log_subscription" "service_network_services" {
  resource_identifier      = aws_vpclattice_service_network.service_network.arn
  destination_arn          = aws_cloudwatch_log_group.vpclattice_access_logs.arn
  service_network_log_type = "SERVICE"
}

# Connections to the resource configurations (the centralized AWS endpoints)
resource "aws_vpclattice_access_log_subscription" "service_network_resources" {
  resource_identifier      = aws_vpclattice_service_network.service_network.arn
  destination_arn          = aws_cloudwatch_log_group.vpclattice_access_logs.arn
  service_network_log_type = "RESOURCE"

  depends_on = [aws_vpclattice_access_log_subscription.service_network_services]
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

# Interface VPC endpoints
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

resource "aws_vpclattice_resource_configuration" "endpoints" {
  for_each = var.vpc_endpoints

  name                        = "resource-config-${each.key}-${var.identifier}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.resource_gateway.id
  port_ranges                 = ["443"]
  protocol                    = "TCP"
  custom_domain_name          = replace(replace(each.value.domain_name, "<region>", var.aws_region), "<account>", data.aws_caller_identity.current.account_id)

  resource_configuration_definition {
    dns_resource {
      domain_name     = replace(replace(each.value.domain_name, "<region>", var.aws_region), "<account>", data.aws_caller_identity.current.account_id)
      ip_address_type = "IPV4"
    }
  }

  depends_on = [module.vpc_endpoints]
}

resource "aws_vpclattice_service_network_resource_association" "endpoints" {
  for_each = var.vpc_endpoints

  private_dns_enabled               = true
  resource_configuration_identifier = aws_vpclattice_resource_configuration.endpoints[each.key].id
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

# ========== DNS RESOLUTION (VPC LATTICE SERVICES) ==========

# ---------- PRIVATE HOSTED ZONE (CONSUMER VPC A) ----------
# Consumer VPC A (VPC association): A and AAAA aliases to the DNS name VPC Lattice gives each service
resource "aws_route53_zone" "consumer_vpc_a" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.agent_ecs_vpc.vpc_attributes.id
  }
}

resource "aws_route53_record" "consumer_vpc_a_mcp_tickets" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.mcp_tickets_service.services["mcp-tickets"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = module.mcp_tickets_service.services["mcp-tickets"].attributes.dns_entry[0].domain_name
    zone_id                = module.mcp_tickets_service.services["mcp-tickets"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_a_mcp_tickets_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.mcp_tickets_service.services["mcp-tickets"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = module.mcp_tickets_service.services["mcp-tickets"].attributes.dns_entry[0].domain_name
    zone_id                = module.mcp_tickets_service.services["mcp-tickets"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_a_api_directory" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.api_directory_service.services["api-directory"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = module.api_directory_service.services["api-directory"].attributes.dns_entry[0].domain_name
    zone_id                = module.api_directory_service.services["api-directory"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_a_api_directory_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.api_directory_service.services["api-directory"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = module.api_directory_service.services["api-directory"].attributes.dns_entry[0].domain_name
    zone_id                = module.api_directory_service.services["api-directory"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_a_agent_triage" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.agent_triage_service.services["agent-triage"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = module.agent_triage_service.services["agent-triage"].attributes.dns_entry[0].domain_name
    zone_id                = module.agent_triage_service.services["agent-triage"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_a_agent_triage_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_a.zone_id
  name    = module.agent_triage_service.services["agent-triage"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = module.agent_triage_service.services["agent-triage"].attributes.dns_entry[0].domain_name
    zone_id                = module.agent_triage_service.services["agent-triage"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------- PRIVATE HOSTED ZONE (CONSUMER VPC B) ----------
# Consumer VPC B (service network endpoint): A and AAAA aliases to the DNS name VPC Lattice gives each service on the endpoint
resource "aws_route53_zone" "consumer_vpc_b" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.agent_runtime_vpc.vpc_attributes.id
  }
}

# The endpoint's associations, read once the services are in the service network
data "aws_vpc_endpoint_associations" "agent_runtime_service_network" {
  vpc_endpoint_id = aws_vpc_endpoint.agent_runtime_service_network.id

  depends_on = [module.mcp_tickets_service, module.api_directory_service, module.agent_triage_service]
}

locals {
  # The DNS entry of each service on the endpoint
  endpoint_dns_entries = {
    mcp-tickets   = one([for a in data.aws_vpc_endpoint_associations.agent_runtime_service_network.associations : a.dns_entry[0] if a.associated_resource_arn == module.mcp_tickets_service.services["mcp-tickets"].attributes.arn])
    api-directory = one([for a in data.aws_vpc_endpoint_associations.agent_runtime_service_network.associations : a.dns_entry[0] if a.associated_resource_arn == module.api_directory_service.services["api-directory"].attributes.arn])
    agent-triage  = one([for a in data.aws_vpc_endpoint_associations.agent_runtime_service_network.associations : a.dns_entry[0] if a.associated_resource_arn == module.agent_triage_service.services["agent-triage"].attributes.arn])
  }
}

resource "aws_route53_record" "consumer_vpc_b_mcp_tickets" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.mcp_tickets_service.services["mcp-tickets"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = local.endpoint_dns_entries["mcp-tickets"].dns_name
    zone_id                = local.endpoint_dns_entries["mcp-tickets"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_b_mcp_tickets_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.mcp_tickets_service.services["mcp-tickets"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = local.endpoint_dns_entries["mcp-tickets"].dns_name
    zone_id                = local.endpoint_dns_entries["mcp-tickets"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_b_api_directory" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.api_directory_service.services["api-directory"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = local.endpoint_dns_entries["api-directory"].dns_name
    zone_id                = local.endpoint_dns_entries["api-directory"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_b_api_directory_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.api_directory_service.services["api-directory"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = local.endpoint_dns_entries["api-directory"].dns_name
    zone_id                = local.endpoint_dns_entries["api-directory"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_b_agent_triage" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.agent_triage_service.services["agent-triage"].attributes.custom_domain_name
  type    = "A"

  alias {
    name                   = local.endpoint_dns_entries["agent-triage"].dns_name
    zone_id                = local.endpoint_dns_entries["agent-triage"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "consumer_vpc_b_agent_triage_aaaa" {
  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.agent_triage_service.services["agent-triage"].attributes.custom_domain_name
  type    = "AAAA"

  alias {
    name                   = local.endpoint_dns_entries["agent-triage"].dns_name
    zone_id                = local.endpoint_dns_entries["agent-triage"].hosted_zone_id
    evaluate_target_health = false
  }
}
