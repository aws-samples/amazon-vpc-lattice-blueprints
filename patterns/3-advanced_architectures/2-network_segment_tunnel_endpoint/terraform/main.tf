/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/3-advanced_architectures/2-network_segment_tunnel_endpoint/terraform/main.tf ---

# ---------- PROVIDER: NETWORK SEGMENT ----------
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "provider-vpc-${var.identifier}"
  cidr_block = var.provider_vpc.cidr_block
  az_count   = var.provider_vpc.number_azs

  subnets = {
    resourcegateway = {
      cidrs = var.provider_vpc.resourcegateway_subnet_cidrs
    }
    workload = {
      cidrs = var.provider_vpc.workload_subnet_cidrs
    }
  }
}

# Resource gateway. DNS resolution must be IN_VPC to attach a CIDR resource configuration
resource "aws_vpclattice_resource_gateway" "resource_gateway" {
  name                           = "resource-gateway-${var.identifier}"
  vpc_id                         = module.provider_vpc.vpc_attributes.id
  subnet_ids                     = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type                = "IPV4"
  resource_config_dns_resolution = "IN_VPC"
  security_group_ids             = [aws_security_group.provider_resource_gateway_sg.id]
}

# Resource configuration (CIDR type): the network segment
resource "aws_vpclattice_resource_configuration" "network_segment" {
  name                        = "resource-config-${var.identifier}"
  type                        = "CIDR"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.resource_gateway.id
  protocol                    = "TCP"
  port_ranges                 = [tostring(var.segment_port)]

  resource_configuration_definition {
    cidr_resource {
      cidr_ranges = var.provider_vpc.workload_subnet_cidrs
    }
  }
}

# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (resource configuration scope)
resource "aws_vpclattice_access_log_subscription" "resource_configuration_access_logs" {
  resource_identifier = aws_vpclattice_resource_configuration.network_segment.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}

# Security Group: Resource Gateway (controls traffic from the gateway to the segment)
resource "aws_security_group" "provider_resource_gateway_sg" {
  name        = "provider-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_segment" {
  for_each          = toset(var.provider_vpc.workload_subnet_cidrs)
  security_group_id = aws_security_group.provider_resource_gateway_sg.id

  from_port   = var.segment_port
  to_port     = var.segment_port
  ip_protocol = "tcp"
  cidr_ipv4   = each.value
}

# Security Group: segment hosts (traffic arrives from the resource gateway ENIs)
resource "aws_security_group" "provider_instance_sg" {
  name        = "provider-vpc-instance-security-group-${var.identifier}"
  description = "Network segment hosts Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "provider_allowing_ingress_resource_gateway" {
  security_group_id = aws_security_group.provider_instance_sg.id

  from_port                    = var.segment_port
  to_port                      = var.segment_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.provider_resource_gateway_sg.id
}

# Segment hosts: one web server per workload subnet
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "segment_host" {
  count = var.provider_vpc.number_azs

  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = false
  instance_type               = var.provider_vpc.instance_type
  vpc_security_group_ids      = [aws_security_group.provider_instance_sg.id]
  subnet_id                   = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })[count.index]
  user_data                   = templatefile("${path.module}/user_data/provider.sh.tftpl", { port = var.segment_port })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "provider-vpc-segment-host-${count.index + 1}-${var.identifier}"
  }
}

# ---------- CONSUMER: TUNNEL VPC ENDPOINT AND EC2 INSTANCES ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.consumer_vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  vpc_egress_only_internet_gateway     = true
  az_count                             = var.consumer_vpc.number_azs

  subnets = {
    workload = {
      netmask          = var.consumer_vpc.workload_subnet_netmask
      assign_ipv6_cidr = true
      connect_to_eigw  = true
    }
    endpoints = {
      netmask          = var.consumer_vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

locals {
  # Consumer endpoint subnets keyed by AZ, used by the tunnel endpoint and by the consumer instances to pick the tunnel endpoint IP in their own AZ.
  consumer_endpoint_subnets = { for k, v in module.consumer_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v if split("/", k)[0] == "endpoints" }
}

# Tunnel VPC endpoint. Its subnets must be in the resource gateway's Availability Zones.
resource "aws_vpc_endpoint" "tunnel" {
  vpc_id                     = module.consumer_vpc.vpc_attributes.id
  vpc_endpoint_type          = "Tunnel"
  resource_configuration_arn = aws_vpclattice_resource_configuration.network_segment.arn
  ip_address_type            = "ipv4"
  subnet_ids                 = [for v in values(local.consumer_endpoint_subnets) : v.id]
  security_group_ids         = [aws_security_group.tunnel_endpoint_sg.id]

  tags = {
    Name = "consumer-vpc-tunnel-endpoint-${var.identifier}"
  }
}

# Security Group: tunnel endpoint (GENEVE from the consumer instances)
resource "aws_security_group" "tunnel_endpoint_sg" {
  name        = "consumer-vpc-tunnel-endpoint-security-group-${var.identifier}"
  description = "Tunnel VPC endpoint Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "tunnel_endpoint_ingress_geneve" {
  security_group_id = aws_security_group.tunnel_endpoint_sg.id

  from_port                    = 6081
  to_port                      = 6081
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.consumer_instance_sg.id
}

# Security Group: consumer instances
resource "aws_security_group" "consumer_instance_sg" {
  name        = "consumer-vpc-instance-security-group-${var.identifier}"
  description = "Consumer EC2 Instance Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

# SSH from the EC2 Instance Connect endpoint
resource "aws_vpc_security_group_ingress_rule" "consumer_ingress_eic" {
  security_group_id = aws_security_group.consumer_instance_sg.id

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.consumer_eic_sg.id
}

# GENEVE from the tunnel endpoint back to the consumer instances
resource "aws_vpc_security_group_ingress_rule" "consumer_ingress_geneve" {
  security_group_id = aws_security_group.consumer_instance_sg.id

  from_port                    = 6081
  to_port                      = 6081
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.tunnel_endpoint_sg.id
}

resource "aws_vpc_security_group_egress_rule" "consumer_egress_any" {
  security_group_id = aws_security_group.consumer_instance_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "consumer_egress_any_ipv6" {
  security_group_id = aws_security_group.consumer_instance_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

# Tunnel endpoint network interfaces (one per AZ). Their IPs are the GENEVE targets.
data "aws_network_interface" "tunnel_endpoint" {
  count = var.consumer_vpc.number_azs
  id    = tolist(aws_vpc_endpoint.tunnel.network_interface_ids)[count.index]
}

# EC2 instances: one per workload subnet.
# The user data creates the GENEVE device toward the tunnel endpoint IP in the instance's own AZ.
resource "aws_instance" "consumer_instance" {
  count = var.consumer_vpc.number_azs

  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = false
  ipv6_address_count          = 1
  instance_type               = var.consumer_vpc.instance_type
  vpc_security_group_ids      = [aws_security_group.consumer_instance_sg.id]
  subnet_id                   = values({ for k, v in module.consumer_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })[count.index]

  user_data = templatefile("${path.module}/user_data/consumer.sh.tftpl", {
    endpoint_ips  = join(" ", [for eni in data.aws_network_interface.tunnel_endpoint : "${eni.availability_zone}=${eni.private_ip}"])
    segment_cidrs = join(" ", var.provider_vpc.workload_subnet_cidrs)
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "consumer-vpc-instance-${count.index + 1}-${var.identifier}"
  }
}

# Security Group: EC2 Instance Connect
resource "aws_security_group" "consumer_eic_sg" {
  name        = "consumer-vpc-eic-security-group-${var.identifier}"
  description = "EC2 Instance Connect Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "consumer_eic_egress_instances" {
  security_group_id = aws_security_group.consumer_eic_sg.id

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.consumer_instance_sg.id
}

# EC2 Instance Connect endpoint
resource "aws_ec2_instance_connect_endpoint" "consumer_eic_endpoint" {
  subnet_id          = values(local.consumer_endpoint_subnets)[0].id
  preserve_client_ip = false
  security_group_ids = [aws_security_group.consumer_eic_sg.id]
}
