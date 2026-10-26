/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/gateway.tf ---

# ========== GATEWAY VPC ==========

# ---------- VPC RESOURCES (GATEWAY VPC) ----------
module "gateway_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "gateway-vpc-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload = { netmask = 24 } # LiteLLM tasks and the database
  }
}

# Amazon S3 gateway endpoint (Amazon ECR image layers)
resource "aws_vpc_endpoint" "gateway_s3" {
  vpc_id            = module.gateway_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.gateway_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE CONNECTIVITY (GATEWAY VPC) ----------
# The gateway reaches the backends (their custom domain names, central.tf) and the central AWS endpoints (private DNS)
resource "aws_vpclattice_service_network_vpc_association" "gateway_vpc" {
  vpc_identifier             = module.gateway_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.backends.id
  security_group_ids         = [aws_security_group.gateway_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com"]
  }
}

# ---------- SECURITY GROUPS (GATEWAY VPC) ----------
data "aws_ec2_managed_prefix_list" "vpclattice" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

resource "aws_security_group" "gateway_tasks" {
  name        = "gateway-vpc-litellm-security-group-${var.identifier}"
  description = "LiteLLM gateway tasks"
  vpc_id      = module.gateway_vpc.vpc_attributes.id
}

# VPC Lattice reaches the LiteLLM tasks (ai-gateway target group, port 4000)
resource "aws_vpc_security_group_ingress_rule" "gateway_from_vpclattice" {
  security_group_id = aws_security_group.gateway_tasks.id

  ip_protocol    = "tcp"
  from_port      = 4000
  to_port        = 4000
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice.id
}

resource "aws_vpc_security_group_egress_rule" "gateway_https" {
  security_group_id = aws_security_group.gateway_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "gateway_to_database" {
  security_group_id = aws_security_group.gateway_tasks.id

  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.database.id
}

resource "aws_security_group" "gateway_vpc_lattice_sg" {
  name        = "gateway-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.gateway_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "gateway_vpc_lattice_https" {
  security_group_id = aws_security_group.gateway_vpc_lattice_sg.id

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.gateway_tasks.id
}

resource "aws_security_group" "database" {
  name        = "gateway-vpc-database-security-group-${var.identifier}"
  description = "LiteLLM database"
  vpc_id      = module.gateway_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_gateway" {
  security_group_id = aws_security_group.database.id

  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.gateway_tasks.id
}

# ========== GATEWAY STATE: DATABASE AND SECRETS ==========

# ---------- DATABASE (AMAZON RDS FOR POSTGRESQL) ----------
resource "aws_db_subnet_group" "litellm" {
  name       = "gateway-db-subnet-group-${var.identifier}"
  subnet_ids = values({ for k, v in module.gateway_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# Small single-AZ instance for the demo. AWS Secrets Manager manages the master password; the gateway task reads it as DATABASE_PASSWORD from the managed secret's 'password' key
resource "aws_db_instance" "litellm" {
  # checkov:skip=CKV_AWS_157:Single-AZ is deliberate for a short-lived demo database
  # checkov:skip=CKV2_AWS_30:Query logging is operational hardening out of scope for the demo database
  # checkov:skip=CKV2_AWS_60:Copy-tags-to-snapshots is irrelevant - the demo uses skip_final_snapshot
  # checkov:skip=CKV_AWS_129:RDS log exports are operational hardening out of scope for the demo database
  # checkov:skip=CKV_AWS_161:IAM DB authentication off - the demo connects using the Secrets Manager managed master password
  # checkov:skip=CKV_AWS_293:Deletion protection off - intentional so the demo can be torn down cleanly
  identifier                  = "gateway-db-${var.identifier}"
  engine                      = "postgres"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  db_name                     = "litellm"
  username                    = "litellm"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.litellm.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  storage_encrypted           = true
  skip_final_snapshot         = true
  apply_immediately           = true
}

# ---------- DEPLOY-TIME SECRETS (LITELLM MASTER KEY AND ONE VIRTUAL KEY PER CALLER) ----------
resource "random_password" "litellm_master_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "litellm_master_key" {
  # checkov:skip=CKV2_AWS_57:Demo deploy-time key; rotation would require re-issuing virtual keys, out of scope
  # checkov:skip=CKV_AWS_149:Default AWS-managed encryption is used; a customer-managed CMK is out of scope for the demo
  name                    = "gateway-litellm-master-key-${var.identifier}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "litellm_master_key" {
  secret_id     = aws_secretsmanager_secret.litellm_master_key.id
  secret_string = "sk-${random_password.litellm_master_key.result}"
}

# The gateway creates the keys with these values at start-up (applications/litellm/entrypoint.py), and each caller reads its own key
resource "random_password" "virtual_keys" {
  for_each = toset(["agent-ecs", "agent-runtime", "agent-triage"])

  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "virtual_keys" {
  # checkov:skip=CKV2_AWS_57:Demo deploy-time key; rotation would require re-issuing virtual keys, out of scope
  # checkov:skip=CKV_AWS_149:Default AWS-managed encryption is used; a customer-managed CMK is out of scope for the demo
  for_each = random_password.virtual_keys

  name                    = "gateway-${each.key}-key-${var.identifier}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "virtual_keys" {
  for_each = random_password.virtual_keys

  secret_id     = aws_secretsmanager_secret.virtual_keys[each.key].id
  secret_string = "sk-${each.value.result}"
}

# ========== AI GATEWAY ==========

# ---------- VPC LATTICE SERVICE (AI GATEWAY) ----------
# Service, HTTPS listener, 'agents' service network association, and IP target group. The ECS service registers the LiteLLM tasks in the target group.
module "ai_gateway_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.agents.id
  }

  services = {
    ai-gateway = {
      name               = "service-ai-gateway-${var.identifier}"
      auth_type          = "AWS_IAM"
      custom_domain_name = "ai-gateway.${var.hosted_zone_name}"
      certificate_arn    = var.certificate_arn

      listeners = {
        https = {
          name     = "https-listener"
          protocol = "HTTPS"
          port     = 443
          default_action_forward = {
            target_groups = {
              ecs = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    ecs = {
      name = "target-group-ai-gateway-${var.identifier}"
      type = "IP"
      config = {
        port             = 4000
        protocol         = "HTTP"
        protocol_version = "HTTP1"
        vpc_identifier   = module.gateway_vpc.vpc_attributes.id
        ip_address_type  = "IPV4"
      }
      health_check = {
        enabled  = true
        path     = "/health/liveliness"
        protocol = "HTTP"
      }
    }
  }
}

# Auth policy. Only the two helpdesk agents and the triage agent may call the gateway; the gateway then applies each caller's virtual key
resource "aws_vpclattice_auth_policy" "ai_gateway" {
  resource_identifier = module.ai_gateway_service.services["ai-gateway"].attributes.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGatewayCallers"
      Effect    = "Allow"
      Principal = { AWS = [aws_iam_role.agent_ecs.arn, aws_iam_role.agent_runtime.arn, aws_iam_role.triage.arn] }
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "${module.ai_gateway_service.services["ai-gateway"].attributes.arn}/*"
    }]
  })
}

# ---------- LITELLM (AMAZON ECS) ----------
resource "aws_ecs_task_definition" "gateway" {
  family                   = "gateway-${var.identifier}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.gateway.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "gateway"
    image        = "${aws_ecr_repository.gateway.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 4000, protocol = "tcp", name = "litellm" }]
    # TCP keepalives below the VPC Lattice idle timeouts, so pooled connections to the backends and to the centralized bedrock-runtime endpoint stay open between requests
    systemControls = [{ namespace = "net.ipv4.tcp_keepalive_time", value = "60" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "MODEL_ID", value = var.model_id },
      # The backends the gateway exposes (gateway configuration, not the agents')
      { name = "TICKETS_URL", value = "${local.backend_urls["mcp-tickets"]}/mcp" },
      { name = "DIRECTORY_URL", value = local.backend_urls["api-directory"] },
      { name = "TRIAGE_URL", value = "${local.backend_urls["agent-triage"]}/" },
      { name = "DATABASE_HOST", value = aws_db_instance.litellm.address },
      { name = "DATABASE_NAME", value = aws_db_instance.litellm.db_name },
      { name = "DATABASE_USERNAME", value = aws_db_instance.litellm.username },
    ]
    secrets = [
      { name = "LITELLM_MASTER_KEY", valueFrom = aws_secretsmanager_secret.litellm_master_key.arn },
      { name = "AGENT_ECS_KEY", valueFrom = aws_secretsmanager_secret.virtual_keys["agent-ecs"].arn },
      { name = "AGENT_RUNTIME_KEY", valueFrom = aws_secretsmanager_secret.virtual_keys["agent-runtime"].arn },
      { name = "AGENT_TRIAGE_KEY", valueFrom = aws_secretsmanager_secret.virtual_keys["agent-triage"].arn },
      { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.litellm.master_user_secret[0].secret_arn}:password::" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.applications.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "gateway"
      }
    }
  }])
}

resource "aws_ecs_service" "gateway" {
  name            = "gateway-${var.identifier}"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values({ for k, v in module.gateway_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.gateway_tasks.id]
    assign_public_ip = false
  }

  vpc_lattice_configurations {
    role_arn         = aws_iam_role.ecs_infrastructure.arn
    target_group_arn = module.ai_gateway_service.target_groups["ecs"].arn
    port_name        = "litellm"
  }

  # The gateway pulls its image, reads its secrets and writes logs through the central endpoints, reaches the database and resolves the backends' domain names; ECS registers the tasks in the target group with the infrastructure role
  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.gateway_vpc, aws_vpc_endpoint.gateway_s3, aws_db_instance.litellm, aws_route53_record.gateway_vpc_backends, aws_iam_role_policy_attachment.ecs_infrastructure]
}
