/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/3-advanced_architectures/1-centralized_vpc_endpoints/terraform/main.tf ---

# ---------- VPC LATTICE SERVICE NETWORK ----------
resource "aws_vpclattice_service_network" "service_network" {
  name      = "service-network-${var.identifier}"
  auth_type = "NONE"
}

# ---------- VPC LATTICE ACCESS LOGGING ----------
# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (service network scope - covers all associated resources)
resource "aws_vpclattice_access_log_subscription" "service_network_access_logs" {
  resource_identifier = aws_vpclattice_service_network.service_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}

# ---------- RESOURCE CONFIGURATIONS AND SERVICE NETWORK ASSOCIATION ----------
# Resource Configuration (Group)
resource "awscc_vpclattice_resource_configuration" "resource_configuration_group_vpcendpoints" {
  name                        = "resource-config-group-vpcendpoints"
  resource_gateway_id         = aws_vpclattice_resource_gateway.resource_gateway.id
  port_ranges                 = ["443"]
  protocol_type               = "TCP"
  resource_configuration_type = "GROUP"
  group_domain                = "${var.aws_region}.amazonaws.com"
}

# Resource association (to service network)
resource "awscc_vpclattice_service_network_resource_association" "resource_association" {
  private_dns_enabled       = true
  resource_configuration_id = split("/", awscc_vpclattice_resource_configuration.resource_configuration_group_vpcendpoints.id)[1]
  service_network_id        = aws_vpclattice_service_network.service_network.id

  tags = [{
    key   = "Name"
    value = "resource-association-${var.identifier}"
  }]
}

# Resource configuration (1 per endpoint)
resource "awscc_vpclattice_resource_configuration" "resource_configuration" {
  for_each = toset(var.vpc_endpoints)

  name                            = "resource-config-${each.value}-${var.identifier}"
  resource_configuration_group_id = split("/", awscc_vpclattice_resource_configuration.resource_configuration_group_vpcendpoints.id)[1]
  custom_domain_name              = "${each.value}.${var.aws_region}.amazonaws.com"

  resource_configuration_type = "CHILD"
  resource_configuration_definition = {
    dns_resource = {
      domain_name     = "${each.value}.${var.aws_region}.amazonaws.com"
      ip_address_type = "IPV4"
    }
  }
}

# ---------- CENTRAL VPC ENDPOINTS ----------
module "endpoints_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "endpoints-vpc-${var.identifier}"
  az_count                             = 2
  cidr_block                           = "10.0.0.0/16"
  vpc_assign_generated_ipv6_cidr_block = true

  subnets = {
    resourcegateway = {
      netmask          = 24
      assign_ipv6_cidr = true
    }
    endpoints = {
      netmask          = 24
      assign_ipv6_cidr = true
    }
  }
}

# Resource gateway
resource "aws_vpclattice_resource_gateway" "resource_gateway" {
  name                           = "resource-gateway-${var.identifier}"
  vpc_id                         = module.endpoints_vpc.vpc_attributes.id
  subnet_ids                     = values({ for k, v in module.endpoints_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type                = "DUALSTACK"
  resource_config_dns_resolution = "IN_VPC"
  security_group_ids             = [aws_security_group.resource_gateway_sg.id]
}

# VPC endpoints
module "vpc_endpoints" {
  source = "../../../tf_modules/vpc_endpoints"

  identifier                 = var.identifier
  vpc                        = module.endpoints_vpc
  interface_vpc_endpoints    = var.vpc_endpoints
  private_dns                = true
  workload_security_group_id = aws_security_group.resource_gateway_sg.id
}

# Security Group: Resource gateway
resource "aws_security_group" "resource_gateway_sg" {
  name        = "endpoints-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.endpoints_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_any_tcp" {
  security_group_id = aws_security_group.resource_gateway_sg.id

  ip_protocol = "tcp"
  from_port   = 0
  to_port     = 65535
  cidr_ipv4   = "10.0.0.0/16"
}

# ---------- CONSUMER VPC ----------
# VPC
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  az_count                             = 2
  cidr_block                           = "10.0.0.0/16"
  vpc_assign_generated_ipv6_cidr_block = true

  subnets = {
    workload = {
      netmask          = 24
      assign_ipv6_cidr = true
    }
  }
}

# VPC Lattice VPC association
resource "awscc_vpclattice_service_network_vpc_association" "service_network_vpc_association" {
  vpc_identifier             = module.consumer_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.service_network.id
  security_group_ids         = [aws_security_group.vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options = {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com"]
  }
}

# Data resource to determine the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# EC2 instances
resource "aws_instance" "ec2_instance" {
  count = 2

  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = false
  ipv6_address_count          = 1
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  subnet_id                   = values({ for k, v in module.consumer_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })[count.index]
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.id

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "consumer-instance-${count.index + 1}-${var.identifier}"
  }
}

# Security Group: EC2 instance
resource "aws_security_group" "instance_sg" {
  name        = "consumer-vpc-instance-security-group-${var.identifier}"
  description = "EC2 Instance Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_any_ipv4_consumer" {
  security_group_id = aws_security_group.instance_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_any_ipv6_consumer" {
  security_group_id = aws_security_group.instance_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

# Security Group: VPC Lattice service network association
resource "aws_security_group" "vpc_lattice_sg" {
  name        = "consumer-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_ec2instance" {
  security_group_id = aws_security_group.vpc_lattice_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.instance_sg.id
}

# ---------- IAM ROLE (EC2 INSTANCE) ----------
# IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile-${var.identifier}"
  role = aws_iam_role.role_ec2.id
}

# IAM role
resource "aws_iam_role" "role_ec2" {
  name               = "ec2-ssm-role-${var.identifier}"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.policy_document.json
}

data "aws_iam_policy_document" "policy_document" {
  statement {
    sid     = "1"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

  }
}

# Policies Attachment to Role
resource "aws_iam_policy_attachment" "ssm_iam_role_policy_attachment" {
  name       = "ssm-iam-role-policy-attachment-${var.identifier}"
  roles      = [aws_iam_role.role_ec2.id]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
