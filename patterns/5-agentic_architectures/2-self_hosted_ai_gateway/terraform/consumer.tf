/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/consumer.tf ---

# ========== CONSUMER A: SELF-HOSTED AGENT (AMAZON ECS) ==========

# ---------- VPC RESOURCES (CONSUMER VPC A) ----------
module "agent_ecs_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "consumer-vpc-a-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload = { netmask = 24 }
  }
}

# Amazon S3 gateway endpoint (Amazon ECR image layers)
resource "aws_vpc_endpoint" "agent_ecs_s3" {
  vpc_id            = module.agent_ecs_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.agent_ecs_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE CONNECTIVITY (CONSUMER VPC A) ----------
# VPC association to the 'agents' service network: the ai-gateway service (its custom domain name, central.tf) and the central endpoints
resource "aws_vpclattice_service_network_vpc_association" "agent_ecs_vpc" {
  vpc_identifier             = module.agent_ecs_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.agents.id
  security_group_ids         = [aws_security_group.agent_ecs_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com", "*.api.aws"]
  }
}

# ---------- SECURITY GROUPS (CONSUMER VPC A) ----------
resource "aws_security_group" "agent_ecs_tasks" {
  name        = "consumer-vpc-a-agent-security-group-${var.identifier}"
  description = "Self-hosted agent tasks"
  vpc_id      = module.agent_ecs_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "agent_ecs_https" {
  security_group_id = aws_security_group.agent_ecs_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_security_group" "agent_ecs_vpc_lattice_sg" {
  name        = "consumer-vpc-a-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.agent_ecs_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "agent_ecs_vpc_lattice_https" {
  security_group_id = aws_security_group.agent_ecs_vpc_lattice_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.agent_ecs_tasks.id
}

# ---------- AGENT (AMAZON ECS) ----------
resource "aws_ecs_task_definition" "agent_ecs" {
  family                   = "agent-ecs-${var.identifier}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.agent_ecs.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "agent"
    image        = "${aws_ecr_repository.agent.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AGENT_NAME", value = "agent-ecs" },
      { name = "CONNECTIVITY_MODE", value = "self_hosted_gateway" },
      # No gateway URL or model: the agent finds the gateway's endpoints in AWS Agent Registry
      { name = "REGISTRY_ID", value = aws_agentregistry_registry.registry.registry_id },
      { name = "REGISTRY_ENDPOINT_URL", value = local.registry_endpoint_url },
      { name = "LITELLM_API_KEY_SECRET_ARN", value = aws_secretsmanager_secret.virtual_keys["agent-ecs"].arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.applications.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "agent-ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "agent_ecs" {
  name                   = "agent-ecs-${var.identifier}"
  cluster                = aws_ecs_cluster.cluster.id
  task_definition        = aws_ecs_task_definition.agent_ecs.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = values({ for k, v in module.agent_ecs_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.agent_ecs_tasks.id]
    assign_public_ip = false
  }

  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.agent_ecs_vpc, aws_vpc_endpoint.agent_ecs_s3]
}

# ========== CONSUMER B: AGENT ON AGENTCORE RUNTIME ==========

# ---------- VPC RESOURCES (CONSUMER VPC B) ----------
module "agent_runtime_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "consumer-vpc-b-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload = { netmask = 24 }
    endpoint = { netmask = 24 }
  }
}

# Amazon S3 gateway endpoint (AgentCore Runtime image layers from Amazon S3)
resource "aws_vpc_endpoint" "agent_runtime_s3" {
  vpc_id            = module.agent_runtime_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.agent_runtime_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE CONNECTIVITY (CONSUMER VPC B) ----------
# Service network endpoint to the 'agents' service network
resource "aws_vpc_endpoint" "agent_runtime_service_network" {
  vpc_id              = module.agent_runtime_vpc.vpc_attributes.id
  vpc_endpoint_type   = "ServiceNetwork"
  service_network_arn = aws_vpclattice_service_network.agents.arn
  subnet_ids          = values({ for k, v in module.agent_runtime_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "endpoint" })
  security_group_ids  = [aws_security_group.agent_runtime_endpoint_sg.id]
  private_dns_enabled = true

  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com", "*.api.aws"]
  }

  tags = {
    Name = "service-network-endpoint-${var.identifier}"
  }
}

# ---------- SECURITY GROUPS (CONSUMER VPC B) ----------
resource "aws_security_group" "agent_runtime" {
  name        = "consumer-vpc-b-runtime-security-group-${var.identifier}"
  description = "AgentCore Runtime ENIs"
  vpc_id      = module.agent_runtime_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "agent_runtime_https" {
  security_group_id = aws_security_group.agent_runtime.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_security_group" "agent_runtime_endpoint_sg" {
  name        = "consumer-vpc-b-endpoint-security-group-${var.identifier}"
  description = "Service network endpoint Security Group"
  vpc_id      = module.agent_runtime_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "agent_runtime_endpoint_https" {
  security_group_id = aws_security_group.agent_runtime_endpoint_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.agent_runtime.id
}

# ---------- AGENT (AGENTCORE RUNTIME, VPC MODE) ----------
resource "aws_bedrockagentcore_agent_runtime" "agent" {
  agent_runtime_name = "agent_runtime_${replace(var.identifier, "-", "_")}"
  description        = "Helpdesk agent (agent-runtime)"
  role_arn           = aws_iam_role.agent_runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:latest"
    }
  }

  network_configuration {
    network_mode = "VPC"
    network_mode_config {
      subnets         = values({ for k, v in module.agent_runtime_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
      security_groups = [aws_security_group.agent_runtime.id]
    }
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  environment_variables = {
    AGENT_NAME        = "agent-runtime"
    CONNECTIVITY_MODE = "self_hosted_gateway"
    # No gateway URL or model: the agent finds the gateway's endpoints in AWS Agent Registry
    REGISTRY_ID                = aws_agentregistry_registry.registry.registry_id
    REGISTRY_ENDPOINT_URL      = local.registry_endpoint_url
    LITELLM_API_KEY_SECRET_ARN = aws_secretsmanager_secret.virtual_keys["agent-runtime"].arn
  }

  depends_on = [aws_iam_role_policy.agent_runtime, aws_vpc_endpoint.agent_runtime_s3]
}
