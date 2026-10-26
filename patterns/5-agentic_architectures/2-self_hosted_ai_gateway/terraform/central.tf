/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/central.tf ---

# ========== VPC LATTICE SERVICE NETWORKS ==========
# Two service networks with the gateway as the only bridge:
# - 'agents': the agents (and the triage agent, for its model calls) reach the ai-gateway service. Nothing else.
# - 'backends': the gateway reaches the MCP server, the REST API, the triage agent and the model.

# ---------- 'agents' SERVICE NETWORK AND AUTH POLICY ----------
resource "aws_vpclattice_service_network" "agents" {
  name      = "service-network-agents-${var.identifier}"
  auth_type = "AWS_IAM"
}

# Only authenticated (SigV4-signed) requests. The ai-gateway service then decides which roles may call it (gateway.tf)
resource "aws_vpclattice_auth_policy" "agents_network" {
  resource_identifier = aws_vpclattice_service_network.agents.arn
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

# ---------- 'backends' SERVICE NETWORK AND AUTH POLICY ----------
resource "aws_vpclattice_service_network" "backends" {
  name      = "service-network-backends-${var.identifier}"
  auth_type = "AWS_IAM"
}

# Only requests from the gateway VPC. The gateway's requests are not signed, so this network can't require authentication: it authorizes the gateway by the VPC its requests come from (backends.tf)
resource "aws_vpclattice_auth_policy" "backends_network" {
  resource_identifier = aws_vpclattice_service_network.backends.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGatewayVpc"
      Effect    = "Allow"
      Principal = "*"
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "vpc-lattice-svcs:SourceVpc" = module.gateway_vpc.vpc_attributes.id
        }
      }
    }]
  })
}

# ---------- ACCESS LOGGING (ONE LOG GROUP PER SERVICE NETWORK) ----------
locals {
  service_networks = {
    agents   = aws_vpclattice_service_network.agents
    backends = aws_vpclattice_service_network.backends
  }
}

resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  for_each = local.service_networks

  name              = "/aws/vpclattice/${each.key}-${var.identifier}"
  retention_in_days = 7
}

# Requests to the VPC Lattice services (caller principal, auth decision, path, status code)
resource "aws_vpclattice_access_log_subscription" "services" {
  for_each = local.service_networks

  resource_identifier      = each.value.arn
  destination_arn          = aws_cloudwatch_log_group.vpclattice_access_logs[each.key].arn
  service_network_log_type = "SERVICE"
}

# Connections to the resource configurations (the centralized AWS endpoints)
resource "aws_vpclattice_access_log_subscription" "resources" {
  for_each = local.service_networks

  resource_identifier      = each.value.arn
  destination_arn          = aws_cloudwatch_log_group.vpclattice_access_logs[each.key].arn
  service_network_log_type = "RESOURCE"

  depends_on = [aws_vpclattice_access_log_subscription.services]
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

# One resource association per endpoint and service network that reaches it (var.vpc_endpoints networks)
resource "aws_vpclattice_service_network_resource_association" "endpoints" {
  for_each = merge([for k, v in var.vpc_endpoints : { for n in v.networks : "${n}/${k}" => { endpoint = k, network = n } }]...)

  private_dns_enabled               = true
  resource_configuration_identifier = aws_vpclattice_resource_configuration.endpoints[each.value.endpoint].id
  service_network_identifier        = local.service_networks[each.value.network].id

  tags = {
    Name = "resource-association-${each.value.network}-${each.value.endpoint}-${var.identifier}"
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

# ========== DNS RESOLUTION (BACKEND SERVICES, GATEWAY VPC) ==========

# ---------- PRIVATE HOSTED ZONE (GATEWAY VPC) ----------
# A and AAAA aliases to the DNS name VPC Lattice gives each backend service
resource "aws_route53_zone" "gateway_vpc" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.gateway_vpc.vpc_attributes.id
  }
}

resource "aws_route53_record" "gateway_vpc_backends" {
  for_each = { for pair in setproduct(keys(local.backend_services), ["A", "AAAA"]) : "${pair[0]}-${pair[1]}" => { service = pair[0], type = pair[1] } }

  zone_id = aws_route53_zone.gateway_vpc.zone_id
  name    = local.backend_services[each.value.service].custom_domain_name
  type    = each.value.type

  alias {
    name                   = local.backend_services[each.value.service].dns_entry[0].domain_name
    zone_id                = local.backend_services[each.value.service].dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# ========== DNS RESOLUTION (AI-GATEWAY SERVICE) ==========

# ---------- PRIVATE HOSTED ZONE (VPC ASSOCIATIONS: CONSUMER VPC A AND PROVIDER VPC) ----------
# A and AAAA aliases to the DNS name VPC Lattice gives the ai-gateway service
resource "aws_route53_zone" "vpc_associations" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.agent_ecs_vpc.vpc_attributes.id
  }

  vpc {
    vpc_id = module.provider_vpc.vpc_attributes.id
  }
}

resource "aws_route53_record" "vpc_associations_ai_gateway" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.vpc_associations.zone_id
  name    = module.ai_gateway_service.services["ai-gateway"].attributes.custom_domain_name
  type    = each.key

  alias {
    name                   = module.ai_gateway_service.services["ai-gateway"].attributes.dns_entry[0].domain_name
    zone_id                = module.ai_gateway_service.services["ai-gateway"].attributes.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------- PRIVATE HOSTED ZONE (CONSUMER VPC B) ----------
# Service network endpoint: A and AAAA aliases to the DNS name VPC Lattice gives the ai-gateway service on the endpoint
resource "aws_route53_zone" "consumer_vpc_b" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.agent_runtime_vpc.vpc_attributes.id
  }
}

# The endpoint's associations, read once the ai-gateway service is in the 'agents' service network
data "aws_vpc_endpoint_associations" "agent_runtime_service_network" {
  vpc_endpoint_id = aws_vpc_endpoint.agent_runtime_service_network.id

  depends_on = [module.ai_gateway_service]
}

locals {
  # The DNS entry of the ai-gateway service on the endpoint
  gateway_endpoint_dns_entry = one([for a in data.aws_vpc_endpoint_associations.agent_runtime_service_network.associations : a.dns_entry[0] if a.associated_resource_arn == module.ai_gateway_service.services["ai-gateway"].attributes.arn])
}

resource "aws_route53_record" "consumer_vpc_b_ai_gateway" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.consumer_vpc_b.zone_id
  name    = module.ai_gateway_service.services["ai-gateway"].attributes.custom_domain_name
  type    = each.key

  alias {
    name                   = local.gateway_endpoint_dns_entry.dns_name
    zone_id                = local.gateway_endpoint_dns_entry.hosted_zone_id
    evaluate_target_health = false
  }
}
