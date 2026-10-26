/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/backends.tf ---

# The three provider applications the agents call, each published as its own VPC Lattice service (with its own auth
# policy): the tickets MCP server, the directory REST API, and the triage A2A agent.

# ========== MCP SERVER: TICKETS (AWS LAMBDA) ==========
# MCP sends every call as a POST to one path, so the auth policy allows or denies the MCP server as a whole.

# ---------- VPC LATTICE SERVICE (MCP SERVER) ----------
# Service, HTTPS listener, service network association, and Lambda target group (with its target)
module "mcp_tickets_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.service_network.id
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

# Auth policy. Both agents may call the MCP server
resource "aws_vpclattice_auth_policy" "mcp_tickets" {
  resource_identifier = module.mcp_tickets_service.services["mcp-tickets"].attributes.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBothAgents"
      Effect    = "Allow"
      Principal = { AWS = [aws_iam_role.agent_ecs.arn, aws_iam_role.agent_runtime.arn] }
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "${module.mcp_tickets_service.services["mcp-tickets"].attributes.arn}/*"
    }]
  })
}

# ---------- MCP SERVER (AWS LAMBDA) ----------
# AWS Lambda function
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
# The auth policy decides per agent role and HTTP method.

# ---------- VPC LATTICE SERVICE (REST API) ----------
# Service, HTTPS listener, service network association, and Lambda target group (with its target)
module "api_directory_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.service_network.id
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

# Auth policy. agent-ecs may read and write, agent-runtime may only read (GET)
resource "aws_vpclattice_auth_policy" "api_directory" {
  resource_identifier = module.api_directory_service.services["api-directory"].attributes.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEcsAgentReadWrite"
        Effect    = "Allow"
        Principal = { AWS = [aws_iam_role.agent_ecs.arn] }
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "${module.api_directory_service.services["api-directory"].attributes.arn}/*"
      },
      {
        Sid       = "AllowRuntimeAgentReadOnly"
        Effect    = "Allow"
        Principal = { AWS = [aws_iam_role.agent_runtime.arn] }
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "${module.api_directory_service.services["api-directory"].attributes.arn}/*"
        Condition = {
          StringEquals = { "vpc-lattice-svcs:RequestMethod" = "GET" }
        }
      }
    ]
  })
}

# ---------- REST API (AWS LAMBDA) ----------
# AWS Lambda function
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
# Provider VPC: the triage tasks are a VPC Lattice target, and the VPC also joins the service network as a consumer
# so the triage agent reaches Amazon Bedrock, Amazon ECR and Amazon CloudWatch Logs through the central endpoints.
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
# Service, HTTPS listener, service network association, and IP target group. The ECS service registers
# the triage tasks in the target group.
module "agent_triage_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = aws_vpclattice_service_network.service_network.id
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

# Auth policy. Both agents may call the triage agent
resource "aws_vpclattice_auth_policy" "agent_triage" {
  resource_identifier = module.agent_triage_service.services["agent-triage"].attributes.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBothAgents"
      Effect    = "Allow"
      Principal = { AWS = [aws_iam_role.agent_ecs.arn, aws_iam_role.agent_runtime.arn] }
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "${module.agent_triage_service.services["agent-triage"].attributes.arn}/*"
    }]
  })
}

# ---------- VPC LATTICE CONNECTIVITY (PROVIDER VPC) ----------
resource "aws_vpclattice_service_network_vpc_association" "provider_vpc" {
  vpc_identifier             = module.provider_vpc.vpc_attributes.id
  service_network_identifier = aws_vpclattice_service_network.service_network.id
  security_group_ids         = [aws_security_group.provider_vpc_lattice_sg.id]

  private_dns_enabled = true
  dns_options {
    private_dns_preference        = "SPECIFIED_DOMAINS_ONLY"
    private_dns_specified_domains = ["*.amazonaws.com"]
  }
}

# ---------- SECURITY GROUPS (PROVIDER VPC) ----------
data "aws_ec2_managed_prefix_list" "vpclattice" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

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
    # TCP keepalives below the VPC Lattice idle timeout for resources, so the model client's pooled connection to
    # the centralized bedrock-runtime endpoint stays open between requests
    systemControls = [{ namespace = "net.ipv4.tcp_keepalive_time", value = "60" }]
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "MODEL_ID", value = var.model_id },
      { name = "PUBLIC_URL", value = "${local.service_urls["agent-triage"]}/" },
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

  # The tasks pull their image and write logs through the central endpoints; ECS registers them in the target group
  # with the infrastructure role, so its policy must be attached first
  depends_on = [aws_vpclattice_service_network_resource_association.endpoints, aws_vpclattice_service_network_vpc_association.provider_vpc, aws_vpc_endpoint.provider_s3, aws_iam_role_policy_attachment.ecs_infrastructure]
}
