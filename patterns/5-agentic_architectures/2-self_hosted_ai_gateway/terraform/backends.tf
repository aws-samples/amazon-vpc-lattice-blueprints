/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/backends.tf ---

# The three backends behind the gateway, each published as a VPC Lattice service in the 'backends' service network:
# the tickets MCP server, the directory REST API (exposed to the agents as MCP tools by the gateway), and the triage
# A2A agent. Only the gateway VPC joins 'backends', so the agents can't reach them. Each service has a custom domain
# name, the one in the gateway's configuration, resolved by a private hosted zone in the gateway VPC (central.tf).
#
# The gateway calls the backends without SigV4: VPC Lattice expects requests signed with an unsigned payload, which
# the LiteLLM version in this pattern doesn't send. So each backend authorizes the gateway by the VPC its requests
# come from (vpc-lattice-svcs:SourceVpc) instead of by its IAM role.

# Auth policy of every backend: only requests from the gateway VPC
resource "aws_vpclattice_auth_policy" "backends" {
  for_each = {
    mcp-tickets   = module.mcp_tickets_service.services["mcp-tickets"].attributes.arn
    api-directory = module.api_directory_service.services["api-directory"].attributes.arn
    agent-triage  = module.agent_triage_service.services["agent-triage"].attributes.arn
  }

  resource_identifier = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGatewayVpc"
      Effect    = "Allow"
      Principal = "*"
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "${each.value}/*"
      Condition = { StringEquals = { "vpc-lattice-svcs:SourceVpc" = module.gateway_vpc.vpc_attributes.id } }
    }]
  })
}

# ========== MCP SERVER: TICKETS (AWS LAMBDA) ==========

# ---------- VPC LATTICE SERVICE (MCP SERVER) ----------
# Service, HTTPS listener, service network association, and Lambda target group (with its target)
module "mcp_tickets_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.backends.id
  }

  services = {
    mcp-tickets = {
      name               = "service-mcp-tickets-${var.identifier}"
      auth_type          = "AWS_IAM"
      custom_domain_name = "mcp-tickets.${var.hosted_zone_name}"
      certificate_arn    = var.certificate_arn

      listeners = {
        https = {
          name     = "https-listener"
          protocol = "HTTPS"
          port     = 443
          default_action_forward = {
            target_groups = {
              lambda = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambda = {
      name = "target-group-mcp-tickets-${var.identifier}"
      type = "LAMBDA"
      targets = {
        function = { id = aws_lambda_function.mcp_tickets.arn }
      }
    }
  }
}

# ---------- MCP SERVER (AWS LAMBDA) ----------
data "archive_file" "mcp_tickets" {
  type        = "zip"
  source_file = "${path.module}/../../applications/mcp_tickets/lambda_function.py"
  output_path = "${path.module}/mcp_tickets.zip"
}

resource "aws_lambda_function" "mcp_tickets" {
  function_name    = "mcp-tickets-${var.identifier}"
  filename         = data.archive_file.mcp_tickets.output_path
  source_code_hash = data.archive_file.mcp_tickets.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"
  timeout          = 30
}

# ========== REST API: DIRECTORY (AWS LAMBDA) ==========

# ---------- VPC LATTICE SERVICE (REST API) ----------
# Service, HTTPS listener, service network association, and Lambda target group (with its target)
module "api_directory_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.backends.id
  }

  services = {
    api-directory = {
      name               = "service-api-directory-${var.identifier}"
      auth_type          = "AWS_IAM"
      custom_domain_name = "api-directory.${var.hosted_zone_name}"
      certificate_arn    = var.certificate_arn

      listeners = {
        https = {
          name     = "https-listener"
          protocol = "HTTPS"
          port     = 443
          default_action_forward = {
            target_groups = {
              lambda = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambda = {
      name = "target-group-api-directory-${var.identifier}"
      type = "LAMBDA"
      targets = {
        function = { id = aws_lambda_function.api_directory.arn }
      }
    }
  }
}

# ---------- REST API (AWS LAMBDA) ----------
data "archive_file" "api_directory" {
  type        = "zip"
  source_file = "${path.module}/../../applications/api_directory/lambda_function.py"
  output_path = "${path.module}/api_directory.zip"
}

resource "aws_lambda_function" "api_directory" {
  function_name    = "api-directory-${var.identifier}"
  filename         = data.archive_file.api_directory.output_path
  source_code_hash = data.archive_file.api_directory.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"
  timeout          = 30
}

# ========== A2A AGENT: TRIAGE (AMAZON ECS, PROVIDER VPC) ==========

# ---------- VPC RESOURCES (PROVIDER VPC) ----------
# Provider VPC
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.9.0"

  name       = "provider-vpc-${var.identifier}"
  az_count   = 2
  cidr_block = "10.0.0.0/16"

  subnets = {
    workload = { netmask = 24 }
  }
}

# Amazon S3 gateway endpoint (Amazon ECR image layers are stored in Amazon S3; gateway endpoints are per VPC)
resource "aws_vpc_endpoint" "provider_s3" {
  vpc_id            = module.provider_vpc.vpc_attributes.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values({ for k, v in module.provider_vpc.rt_attributes_by_type_by_az.private : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
}

# ---------- VPC LATTICE SERVICE (TRIAGE AGENT) ----------
module "agent_triage_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.backends.id
  }

  services = {
    agent-triage = {
      name               = "service-agent-triage-${var.identifier}"
      auth_type          = "AWS_IAM"
      custom_domain_name = "agent-triage.${var.hosted_zone_name}"
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
      name = "target-group-agent-triage-${var.identifier}"
      type = "IP"
      config = {
        port             = 9000
        protocol         = "HTTP"
        protocol_version = "HTTP1"
        vpc_identifier   = module.provider_vpc.vpc_attributes.id
        ip_address_type  = "IPV4"
      }
      health_check = {
        enabled  = true
        path     = "/.well-known/agent-card.json"
        protocol = "HTTP"
      }
    }
  }
}

# ---------- VPC LATTICE CONNECTIVITY (PROVIDER VPC) ----------
# The triage agent reaches the ai-gateway service (its custom domain name, central.tf) and the central endpoints
resource "aws_vpclattice_service_network_vpc_association" "provider_vpc" {
  vpc_identifier             = module.provider_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.agents.id
  security_group_ids         = [aws_security_group.provider_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com", "*.api.aws"]
  }
}

# ---------- SECURITY GROUPS (PROVIDER VPC) ----------
resource "aws_security_group" "triage_tasks" {
  name        = "provider-vpc-triage-security-group-${var.identifier}"
  description = "Triage agent tasks"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "triage_from_vpclattice" {
  security_group_id = aws_security_group.triage_tasks.id

  ip_protocol    = "tcp"
  from_port      = 9000
  to_port        = 9000
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice.id
}

resource "aws_vpc_security_group_egress_rule" "triage_https" {
  security_group_id = aws_security_group.triage_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_security_group" "provider_vpc_lattice_sg" {
  name        = "provider-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice VPC association Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "provider_vpc_lattice_from_triage" {
  security_group_id = aws_security_group.provider_vpc_lattice_sg.id

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
    portMappings = [{ containerPort = 9000, protocol = "tcp", name = "a2a" }]
    # TCP keepalives below the VPC Lattice idle timeout, so the model client's pooled connection to the gateway stays open between requests
    systemControls = [{ namespace = "net.ipv4.tcp_keepalive_time", value = "60" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "PUBLIC_URL", value = "${local.backend_urls["agent-triage"]}/" },
      # No model configured: the triage agent finds the gateway's model endpoint in AWS Agent Registry
      { name = "CONNECTIVITY_MODE", value = "self_hosted_gateway" },
      { name = "REGISTRY_ID", value = aws_agentregistry_registry.registry.registry_id },
      { name = "REGISTRY_ENDPOINT_URL", value = local.registry_endpoint_url },
      { name = "LITELLM_API_KEY_SECRET_ARN", value = aws_secretsmanager_secret.virtual_keys["agent-triage"].arn },
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
    subnets          = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
    security_groups  = [aws_security_group.triage_tasks.id]
    assign_public_ip = false
  }

  vpc_lattice_configurations {
    role_arn         = aws_iam_role.ecs_infrastructure.arn
    target_group_arn = module.agent_triage_service.target_groups["ecs"].arn
    port_name        = "a2a"
  }

  # The tasks pull their image and write logs through the central endpoints; ECS registers them in the target group with the infrastructure role, so its policy must be attached first
  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.provider_vpc, aws_vpc_endpoint.provider_s3, aws_iam_role_policy_attachment.ecs_infrastructure]
}
