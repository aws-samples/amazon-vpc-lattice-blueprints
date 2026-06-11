/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/4-ecs/terraform/main.tf ---

# Data source: Detect system architecture for ECS task definition
data "external" "system_architecture" {
  program = ["bash", "-c", "echo '{\"arch\":\"'$(uname -m)'\"}'"]
}

locals {
  # Map system architecture to ECS CPU architecture
  ecs_cpu_architecture = data.external.system_architecture.result.arch == "arm64" || data.external.system_architecture.result.arch == "aarch64" ? "ARM64" : "X86_64"
}

# Data source: Amazon VPC Lattice prefix list (IPv4 and IPv6)
data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv4" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv6" {
  name = "com.amazonaws.${var.aws_region}.ipv6.vpc-lattice"
}

# ---------- VPC LATTICE RESOURCES ----------
# VPC Lattice service network
module "service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name      = "service-network-${var.identifier}"
    auth_type = "NONE"
  }
}

# ---------- VPC LATTICE ACCESS LOGGING ----------
# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (service network scope - covers all associated services)
resource "aws_vpclattice_access_log_subscription" "service_network_access_logs" {
  resource_identifier = module.service_network.service_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}

# VPC Lattice service - VPC Lattice-generated FQDN, HTTPS listener, IP type target
module "service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = module.service_network.service_network.id
  }

  services = {
    service = {
      name      = "service-${var.identifier}"
      auth_type = "NONE"

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              ecstarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    ecstarget = {
      type = "IP"
      config = {
        port             = 80
        protocol         = "HTTP"
        vpc_identifier   = module.provider_vpc.vpc_attributes.id
        ip_address_type  = "IPV4"
        protocol_version = "HTTP1"
      }
      health_check = {
        enabled = true
      }
    }
  }
}

# ---------- CONSUMER VPC AND EC2 INSTANCES ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  vpc_lattice = {
    service_network_identifier = module.service_network.service_network.id
    security_group_ids         = [aws_security_group.vpclattice_sg.id]
  }

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
    }
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

module "consumer_instances" {
  source = "../../../tf_modules/consumer_instance"

  identifier      = var.identifier
  vpc_name        = "consumer-vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# Security Group (VPC Lattice VPC association)
resource "aws_security_group" "vpclattice_sg" {
  name        = "consumer-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_instances_https" {
  security_group_id = aws_security_group.vpclattice_sg.id

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}

# ---------- ECR REPOSITORY ----------
resource "aws_ecr_repository" "ecr_repository" {
  name                 = "ecsapplication"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------- ECS FARGATE ----------
# Provider VPC
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "provider-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  subnets = {
    workload = {
      netmask                         = var.vpc.private_subnet_netmask
      assign_ipv6_cidr                = true
      assign_ipv6_address_on_creation = true
    }
    endpoints = {
      netmask                         = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr                = true
      assign_ipv6_address_on_creation = true
    }
  }
}

# VPC endpoints: S3 (Gateway), ECR API, ECR DKR, LOGS (Interface)
module "vpc_endpoints" {
  source = "../../../tf_modules/vpc_endpoints"

  identifier                 = var.identifier
  vpc                        = module.provider_vpc
  interface_vpc_endpoints    = ["ecr.api", "ecr.dkr", "logs"]
  private_dns                = true
  workload_security_group_id = aws_security_group.ecs_tasks.id
  create_s3_gateway          = true
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "provider-cluster-${var.identifier}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "provider-task-definition-${var.identifier}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = local.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "ecsapplication"
      image     = "${aws_ecr_repository.ecr_repository.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
          name          = "ecsapplication"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "ecs_service" {
  name            = "provider-ecs-service-${var.identifier}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  vpc_lattice_configurations {
    role_arn         = aws_iam_role.ecs_infrastructure_role.arn
    target_group_arn = module.service.target_groups["ecstarget"].arn
    port_name        = "ecsapplication"
  }
}

# Security Group - ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "provider-vpc-ecs-tasks-security-group-${var.identifier}"
  description = "Allow inbound traffic for ECS tasks"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_http_ipv4" {
  security_group_id = aws_security_group.ecs_tasks.id

  from_port      = 80
  to_port        = 80
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_http_ipv6" {
  security_group_id = aws_security_group.ecs_tasks.id

  from_port      = 80
  to_port        = 80
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv6.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_https_ipv4" {
  security_group_id = aws_security_group.ecs_tasks.id

  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_https_ipv6" {
  security_group_id = aws_security_group.ecs_tasks.id

  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv6.id
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any" {
  security_group_id = aws_security_group.ecs_tasks.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any_ipv6" {
  security_group_id = aws_security_group.ecs_tasks.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

# IAM Role (ECS Task Execution)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "provider-task-execution-role-${var.identifier}"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_execution_role_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role (ECS Task)
resource "aws_iam_role" "ecs_task_role" {
  name = "provider-task-role-${var.identifier}"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_role_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_role_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy_attachment_vpclattice" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}

# IAM Role (ECS Infrastructure)
resource "aws_iam_role" "ecs_infrastructure_role" {
  name = "provider-infrastructure-role-${var.identifier}"

  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_role_assume_role.json
}

data "aws_iam_policy_document" "ecs_infrastructure_role_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure_role_policy_attachment_vpclattice" {
  role       = aws_iam_role.ecs_infrastructure_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}
