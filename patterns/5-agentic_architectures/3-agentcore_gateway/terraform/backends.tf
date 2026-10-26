/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/backends.tf ---

# The gateway's backends:
# - directory: a REST API on AWS Lambda, a native target of the gateway (no network configuration)
# - tickets (MCP server) and triage (A2A agent): containers on Amazon ECS, each in its own VPC, as if each had a different owner. Each owner publishes its backend with a VPC Lattice resource gateway and a resource configuration (self-managed), and the gateway's target names that configuration (gateway.tf).
# Each VPC-hosted backend sits behind an internal Application Load Balancer with a public certificate for <backend>.<domain_name>: the gateway requires a publicly trusted certificate on private targets.
# In each backend VPC: resource gateway -> load balancer (443) -> tasks (container port). The tasks reach the central endpoints (images, logs) through a VPC association to the service network.

# ========== REST API: DIRECTORY (AWS LAMBDA) ==========
data "archive_file" "api_directory" {
  type        = "zip"
  source_file = "${path.module}/../../applications/api_directory/lambda_function.py"
  output_path = "${path.module}/api_directory.zip"
}

# gateway_handler: the gateway's Lambda target event (the tool's arguments, and the tool name in the context)
resource "aws_lambda_function" "api_directory" {
  function_name    = "api-directory-${var.identifier}"
  filename         = data.archive_file.api_directory.output_path
  source_code_hash = data.archive_file.api_directory.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "lambda_function.gateway_handler"
  timeout          = 30
}

# ========== MCP SERVER: TICKETS (AMAZON ECS, TICKETS VPC) ==========

# ---------- VPC RESOURCES (TICKETS VPC) ----------
module "tickets_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "tickets-vpc-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload        = { netmask = 24 }
    alb             = { netmask = 24 }
    resourcegateway = { netmask = 24 }
  }
}

# Amazon S3 gateway endpoint (Amazon ECR image layers are stored in Amazon S3; gateway endpoints are per VPC)
resource "aws_vpc_endpoint" "tickets_s3" {
  vpc_id            = module.tickets_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.tickets_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE CONNECTIVITY (TICKETS VPC) ----------
# The backend's way in: the gateway's private endpoint enters the VPC through the resource gateway, to the load balancer. Sharing this resource configuration with AWS RAM is how another account's gateway reaches the backend (see the README).
resource "aws_vpclattice_resource_gateway" "tickets" {
  name                           = "resource-gateway-tickets-${var.identifier}"
  vpc_id                         = module.tickets_vpc.vpc_attributes.id
  subnet_ids                     = values({ for k, v in module.tickets_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type                = "IPV4"
  resource_config_dns_resolution = "IN_VPC"
  security_group_ids             = [aws_security_group.tickets_resource_gateway.id]
}

resource "aws_vpclattice_resource_configuration" "tickets" {
  name                        = "resource-config-tickets-${var.identifier}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.tickets.id
  port_ranges                 = ["443"]
  protocol                    = "TCP"

  resource_configuration_definition {
    dns_resource {
      domain_name     = aws_lb.tickets.dns_name
      ip_address_type = "IPV4"
    }
  }
}

# Self-managed resource configurations are visible to their owner, who can log every connection to them
resource "aws_cloudwatch_log_group" "tickets_access_logs" {
  name              = "/aws/vpclattice/resource-config-tickets-${var.identifier}"
  retention_in_days = 7
}

resource "aws_vpclattice_access_log_subscription" "tickets" {
  resource_identifier = aws_vpclattice_resource_configuration.tickets.arn
  destination_arn     = aws_cloudwatch_log_group.tickets_access_logs.arn
}

# VPC association: the central endpoints the tasks need (images, logs)
resource "aws_vpclattice_service_network_vpc_association" "tickets_vpc" {
  vpc_identifier             = module.tickets_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.service_network.id
  security_group_ids         = [aws_security_group.tickets_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com", "*.api.aws"]
  }
}

# ---------- INTERNAL LOAD BALANCER (TICKETS VPC) ----------
resource "aws_lb" "tickets" {
  # checkov:skip=CKV_AWS_91:Demo load balancer; the resource configuration's access log records every connection from the gateway
  # checkov:skip=CKV_AWS_150:Demo load balancer, deleted with the pattern
  # checkov:skip=CKV2_AWS_28:Internal load balancer reached only through its resource gateway, WAF not needed
  name                       = "alb-tickets-${var.identifier}"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = values({ for k, v in module.tickets_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "alb" })
  security_groups            = [aws_security_group.tickets_alb.id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "tickets" {
  # checkov:skip=CKV_AWS_378:TLS ends at the load balancer; the containers serve HTTP inside the VPC
  name        = "tg-tickets-${var.identifier}"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.tickets_vpc.vpc_attributes.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

# HTTPS with the public certificate for tickets.<domain_name>, the name the gateway calls
resource "aws_lb_listener" "tickets" {
  load_balancer_arn = aws_lb.tickets.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tickets.arn
  }
}

# ---------- SECURITY GROUPS (TICKETS VPC) ----------
resource "aws_security_group" "tickets_resource_gateway" {
  name        = "tickets-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.tickets_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "tickets_resource_gateway_to_alb" {
  security_group_id = aws_security_group.tickets_resource_gateway.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tickets_alb.id
}

resource "aws_security_group" "tickets_alb" {
  name        = "tickets-vpc-alb-security-group-${var.identifier}"
  description = "Internal load balancer"
  vpc_id      = module.tickets_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "tickets_alb_from_resource_gateway" {
  security_group_id = aws_security_group.tickets_alb.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tickets_resource_gateway.id
}

resource "aws_vpc_security_group_egress_rule" "tickets_alb_to_tasks" {
  security_group_id = aws_security_group.tickets_alb.id

  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.tickets_tasks.id
}

resource "aws_security_group" "tickets_tasks" {
  name        = "tickets-vpc-tasks-security-group-${var.identifier}"
  description = "Tickets MCP server tasks"
  vpc_id      = module.tickets_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "tickets_tasks_from_alb" {
  security_group_id = aws_security_group.tickets_tasks.id

  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.tickets_alb.id
}

resource "aws_vpc_security_group_egress_rule" "tickets_tasks_https" {
  security_group_id = aws_security_group.tickets_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_security_group" "tickets_vpc_lattice_sg" {
  name        = "tickets-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.tickets_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "tickets_vpc_lattice_from_tasks" {
  security_group_id = aws_security_group.tickets_vpc_lattice_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tickets_tasks.id
}

# ---------- MCP SERVER (AMAZON ECS) ----------
resource "aws_ecs_task_definition" "tickets" {
  family                   = "tickets-${var.identifier}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "tickets"
    image        = "${aws_ecr_repository.tickets.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8000, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.applications.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "tickets"
      }
    }
  }])
}

resource "aws_ecs_service" "tickets" {
  name            = "tickets-${var.identifier}"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.tickets.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values({ for k, v in module.tickets_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.tickets_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tickets.arn
    container_name   = "tickets"
    container_port   = 8000
  }

  # The tasks pull their image and write logs through the central endpoints
  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.tickets_vpc, aws_vpc_endpoint.tickets_s3, aws_lb_listener.tickets]
}

# ========== A2A AGENT: TRIAGE (AMAZON ECS, TRIAGE VPC) ==========

# ---------- VPC RESOURCES (TRIAGE VPC) ----------
module "triage_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "triage-vpc-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload        = { netmask = 24 }
    alb             = { netmask = 24 }
    resourcegateway = { netmask = 24 }
  }
}

# Amazon S3 gateway endpoint (Amazon ECR image layers)
resource "aws_vpc_endpoint" "triage_s3" {
  vpc_id            = module.triage_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.triage_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE CONNECTIVITY (TRIAGE VPC) ----------
resource "aws_vpclattice_resource_gateway" "triage" {
  name                           = "resource-gateway-triage-${var.identifier}"
  vpc_id                         = module.triage_vpc.vpc_attributes.id
  subnet_ids                     = values({ for k, v in module.triage_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "resourcegateway" })
  ip_address_type                = "IPV4"
  resource_config_dns_resolution = "IN_VPC"
  security_group_ids             = [aws_security_group.triage_resource_gateway.id]
}

resource "aws_vpclattice_resource_configuration" "triage" {
  name                        = "resource-config-triage-${var.identifier}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.triage.id
  port_ranges                 = ["443"]
  protocol                    = "TCP"

  resource_configuration_definition {
    dns_resource {
      domain_name     = aws_lb.triage.dns_name
      ip_address_type = "IPV4"
    }
  }
}

resource "aws_cloudwatch_log_group" "triage_access_logs" {
  name              = "/aws/vpclattice/resource-config-triage-${var.identifier}"
  retention_in_days = 7
}

resource "aws_vpclattice_access_log_subscription" "triage" {
  resource_identifier = aws_vpclattice_resource_configuration.triage.arn
  destination_arn     = aws_cloudwatch_log_group.triage_access_logs.arn
}

# VPC association: the central endpoints the tasks need (images, logs), and the gateway and the registry for the triage agent's model calls
resource "aws_vpclattice_service_network_vpc_association" "triage_vpc" {
  vpc_identifier             = module.triage_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.service_network.id
  security_group_ids         = [aws_security_group.triage_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com", "*.api.aws"]
  }
}

# ---------- INTERNAL LOAD BALANCER (TRIAGE VPC) ----------
resource "aws_lb" "triage" {
  # checkov:skip=CKV_AWS_91:Demo load balancer; the resource configuration's access log records every connection from the gateway
  # checkov:skip=CKV_AWS_150:Demo load balancer, deleted with the pattern
  # checkov:skip=CKV2_AWS_28:Internal load balancer reached only through its resource gateway, WAF not needed
  name                       = "alb-triage-${var.identifier}"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = values({ for k, v in module.triage_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "alb" })
  security_groups            = [aws_security_group.triage_alb.id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "triage" {
  # checkov:skip=CKV_AWS_378:TLS ends at the load balancer; the containers serve HTTP inside the VPC
  name        = "tg-triage-${var.identifier}"
  port        = 9000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.triage_vpc.vpc_attributes.id

  health_check {
    path    = "/.well-known/agent-card.json"
    matcher = "200"
  }
}

# HTTPS with the public certificate for triage.<domain_name>, the name the gateway calls
resource "aws_lb_listener" "triage" {
  load_balancer_arn = aws_lb.triage.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.triage.arn
  }
}

# ---------- SECURITY GROUPS (TRIAGE VPC) ----------
resource "aws_security_group" "triage_resource_gateway" {
  name        = "triage-vpc-resource-gateway-security-group-${var.identifier}"
  description = "Resource Gateway Security Group"
  vpc_id      = module.triage_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "triage_resource_gateway_to_alb" {
  security_group_id = aws_security_group.triage_resource_gateway.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.triage_alb.id
}

resource "aws_security_group" "triage_alb" {
  name        = "triage-vpc-alb-security-group-${var.identifier}"
  description = "Internal load balancer"
  vpc_id      = module.triage_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "triage_alb_from_resource_gateway" {
  security_group_id = aws_security_group.triage_alb.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.triage_resource_gateway.id
}

resource "aws_vpc_security_group_egress_rule" "triage_alb_to_tasks" {
  security_group_id = aws_security_group.triage_alb.id

  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.triage_tasks.id
}

resource "aws_security_group" "triage_tasks" {
  name        = "triage-vpc-tasks-security-group-${var.identifier}"
  description = "Triage agent tasks"
  vpc_id      = module.triage_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "triage_tasks_from_alb" {
  security_group_id = aws_security_group.triage_tasks.id

  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.triage_alb.id
}

resource "aws_vpc_security_group_egress_rule" "triage_tasks_https" {
  security_group_id = aws_security_group.triage_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_security_group" "triage_vpc_lattice_sg" {
  name        = "triage-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.triage_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "triage_vpc_lattice_from_tasks" {
  security_group_id = aws_security_group.triage_vpc_lattice_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.triage_tasks.id
}

# ---------- AGENT (AMAZON ECS) ----------
resource "aws_ecs_task_definition" "triage" {
  family                   = "triage-${var.identifier}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.triage.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "triage"
    image        = "${aws_ecr_repository.triage.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 9000, protocol = "tcp" }]
    # TCP keepalives below the VPC Lattice idle timeout, so the model client's pooled connection to the gateway stays open between requests
    systemControls = [{ namespace = "net.ipv4.tcp_keepalive_time", value = "60" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      # The URL in the agent card: the triage agent through the gateway
      { name = "PUBLIC_URL", value = "${local.gateway_url}/${aws_bedrockagentcore_gateway_target.triage.name}/" },
      # No model configured: the triage agent finds the gateway's model endpoint in AWS Agent Registry
      { name = "CONNECTIVITY_MODE", value = "agentcore_gateway" },
      { name = "REGISTRY_ID", value = aws_agentregistry_registry.registry.registry_id },
      { name = "REGISTRY_ENDPOINT_URL", value = local.registry_endpoint_url },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.applications.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "triage"
      }
    }
  }])
}

resource "aws_ecs_service" "triage" {
  name            = "triage-${var.identifier}"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.triage.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values({ for k, v in module.triage_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.triage_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.triage.arn
    container_name   = "triage"
    container_port   = 9000
  }

  # The tasks pull their image and write logs through the central endpoints
  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.triage_vpc, aws_vpc_endpoint.triage_s3, aws_lb_listener.triage]
}
