/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/2-self_hosted_ai_gateway/terraform/main.tf ---

# Common items. The rest of the pattern is split by role:
# - central.tf: the 'agents' and 'backends' service networks, centralized AWS service endpoints and DNS resolution of the ai-gateway and backend services
# - gateway.tf: the AI gateway (LiteLLM on Amazon ECS), its database, the deploy-time secrets and the ai-gateway service
# - agent_registry.tf: AWS Agent Registry and its records (the gateway's endpoints)
# - consumer.tf: consumer VPC A (agent-ecs, VPC association) and consumer VPC B (agent-runtime, service network endpoint)
# - backends.tf: the MCP server, REST API and triage agent (provider VPC), each a VPC Lattice service in 'backends'

data "aws_caller_identity" "current" {}

locals {
  # The ai-gateway URL (its custom domain name), the same from every VPC that calls it: each one's private hosted zone resolves it to its own way into the 'agents' service network (central.tf)
  gateway_url = "https://${module.ai_gateway_service.services["ai-gateway"].attributes.custom_domain_name}"

  # The backends the gateway calls: each one's VPC Lattice service and the URL of its custom domain name (the gateway VPC's private hosted zone resolves it, central.tf)
  backend_services = {
    mcp-tickets   = module.mcp_tickets_service.services["mcp-tickets"].attributes
    api-directory = module.api_directory_service.services["api-directory"].attributes
    agent-triage  = module.agent_triage_service.services["agent-triage"].attributes
  }
  backend_urls = { for k, v in local.backend_services : k => "https://${v.custom_domain_name}" }

  registry_endpoint_url = "https://${aws_vpclattice_resource_configuration.endpoints["registry"].custom_domain_name}"
}

# ========== CONTAINERS: IMAGES, CLUSTER AND LOGS ==========

# ---------- AMAZON ECR REPOSITORIES ----------
# deploy.sh creates these repositories first, then builds and pushes the images (ARM64)
resource "aws_ecr_repository" "agent" {
  name                 = "agent-${var.identifier}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "triage" {
  name                 = "triage-${var.identifier}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "gateway" {
  name                 = "gateway-${var.identifier}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------- AMAZON ECS CLUSTER AND APPLICATION LOGS ----------
resource "aws_ecs_cluster" "cluster" {
  name = "cluster-${var.identifier}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Application logs (agents, gateway and triage)
resource "aws_cloudwatch_log_group" "applications" {
  name              = "/${var.identifier}/applications"
  retention_in_days = 7
}

# ========== IAM ==========

# ---------- AMAZON ECS ROLES (TASK EXECUTION AND VPC LATTICE TARGET REGISTRATION) ----------
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "task-execution-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The task execution role injects the gateway's secrets (master key, virtual keys, database password) into its task
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "read-gateway-secrets"
  role = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = concat([aws_secretsmanager_secret.litellm_master_key.arn, aws_db_instance.litellm.master_user_secret[0].secret_arn], values(aws_secretsmanager_secret.virtual_keys)[*].arn)
    }]
  })
}

resource "aws_iam_role" "ecs_infrastructure" {
  name = "ecs-infrastructure-role-${var.identifier}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}

# ---------- POLICY DOCUMENTS (RE-USED BY THE ROLES THAT CALL THE GATEWAY) ----------
# The agents and the triage agent call the ai-gateway service and discover the gateway in AWS Agent Registry.
data "aws_iam_policy_document" "gateway_consumer" {
  statement {
    sid       = "InvokeAiGateway"
    actions   = ["vpc-lattice-svcs:Invoke"]
    resources = ["${module.ai_gateway_service.services["ai-gateway"].attributes.arn}/*"]
  }

  statement {
    sid       = "DiscoverRegistryRecords"
    actions   = ["agent-registry:SearchDiscoverableRegistryRecords", "agent-registry:ListDiscoverableRegistryRecords", "agent-registry:GetDiscoverableRegistryRecord"]
    resources = [aws_agentregistry_registry.registry.registry_arn, "${aws_agentregistry_registry.registry.registry_arn}/*"]
  }
}

# Each caller reads only its own virtual key
data "aws_iam_policy_document" "virtual_key" {
  for_each = aws_secretsmanager_secret.virtual_keys

  source_policy_documents = [data.aws_iam_policy_document.gateway_consumer.json]

  statement {
    sid       = "ReadVirtualKey"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [each.value.arn]
  }
}

# ---------- SELF-HOSTED AGENT (ECS TASK ROLE) ----------
resource "aws_iam_role" "agent_ecs" {
  name               = "agent-ecs-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

data "aws_iam_policy_document" "agent_ecs" {
  source_policy_documents = [data.aws_iam_policy_document.virtual_key["agent-ecs"].json]

  # ECS Exec (the tests run commands inside the agent container)
  statement {
    sid       = "EcsExec"
    actions   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "agent_ecs" {
  name   = "agent-ecs-permissions"
  role   = aws_iam_role.agent_ecs.id
  policy = data.aws_iam_policy_document.agent_ecs.json
}

# ---------- AGENT ON AGENTCORE RUNTIME ----------
resource "aws_iam_role" "agent_runtime" {
  name = "agent-runtime-role-${var.identifier}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

data "aws_iam_policy_document" "agent_runtime" {
  source_policy_documents = [data.aws_iam_policy_document.virtual_key["agent-runtime"].json]

  # AgentCore Runtime pulls the agent image and writes its logs with the agent's role
  statement {
    sid       = "PullImage"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [aws_ecr_repository.agent.arn]
  }

  statement {
    sid       = "EcrToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"]
  }
}

resource "aws_iam_role_policy" "agent_runtime" {
  name   = "agent-runtime-permissions"
  role   = aws_iam_role.agent_runtime.id
  policy = data.aws_iam_policy_document.agent_runtime.json
}

# ---------- TRIAGE AGENT (ECS TASK ROLE) ----------
# A backend for the helpdesk agents, and a consumer of the gateway for its own model calls
resource "aws_iam_role" "triage" {
  name               = "triage-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy" "triage" {
  name   = "triage-permissions"
  role   = aws_iam_role.triage.id
  policy = data.aws_iam_policy_document.virtual_key["agent-triage"].json
}

# ---------- AI GATEWAY (ECS TASK ROLE) ----------
# The only identity that calls Amazon Bedrock. Its calls to the backends are not signed (see backends.tf).
resource "aws_iam_role" "gateway" {
  name               = "gateway-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy" "gateway" {
  # checkov:skip=CKV_AWS_355:Amazon Bedrock model and inference profile ARNs vary by model and Region; the demo grants invoke on all models
  name = "invoke-models"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeModels"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "*"
    }]
  })
}

# ---------- LAMBDA FUNCTIONS (MCP SERVER AND REST API) ----------
resource "aws_iam_role" "lambda" {
  name = "lambda-role-${var.identifier}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
