/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/main.tf ---

# Common items. The rest of the pattern is split by role:
# - central.tf: the service network, centralized AWS service endpoints and the AgentCore Gateway endpoint
# - gateway.tf: the AgentCore Gateway, its policy (Cedar) and its targets
# - agent_registry.tf: AWS Agent Registry and its records (the gateway's endpoints)
# - consumer.tf: consumer VPC A (agent-ecs, VPC association) and agent-runtime (AgentCore Runtime, no VPC)
# - backends.tf: the directory API (AWS Lambda) and the VPC-hosted backends, tickets and triage, each in its own provider VPC

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # The gateway's DNS name, the same from every caller: agent-ecs reaches it through the service network (central.tf), agent-runtime directly
  gateway_host = "${aws_bedrockagentcore_gateway.gateway.gateway_id}.gateway.bedrock-agentcore.${var.aws_region}.amazonaws.com"
  gateway_url  = "https://${local.gateway_host}"

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

resource "aws_ecr_repository" "tickets" {
  name                 = "tickets-${var.identifier}"
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

# Application logs (agent-ecs, tickets and triage)
resource "aws_cloudwatch_log_group" "applications" {
  name              = "/${var.identifier}/applications"
  retention_in_days = 7
}

# ========== IAM ==========

# ---------- AMAZON ECS TASK EXECUTION ROLE ----------
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

# ---------- POLICY DOCUMENT (RE-USED BY THE ROLES THAT CALL THE GATEWAY) ----------
# The agents and the triage agent call the gateway and discover it in AWS Agent Registry. The gateway's policy (gateway.tf) then decides what each one may use.
data "aws_iam_policy_document" "gateway_consumer" {
  statement {
    sid       = "InvokeGateway"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.gateway.gateway_arn]
  }

  statement {
    sid       = "DiscoverRegistryRecords"
    actions   = ["agent-registry:SearchDiscoverableRegistryRecords", "agent-registry:ListDiscoverableRegistryRecords", "agent-registry:GetDiscoverableRegistryRecord"]
    resources = [aws_agentregistry_registry.registry.registry_arn, "${aws_agentregistry_registry.registry.registry_arn}/*"]
  }
}

# ---------- SELF-HOSTED AGENT (ECS TASK ROLE) ----------
resource "aws_iam_role" "agent_ecs" {
  name               = "agent-ecs-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

data "aws_iam_policy_document" "agent_ecs" {
  source_policy_documents = [data.aws_iam_policy_document.gateway_consumer.json]

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
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:*" }
      }
    }]
  })
}

data "aws_iam_policy_document" "agent_runtime" {
  source_policy_documents = [data.aws_iam_policy_document.gateway_consumer.json]

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
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"]
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
  policy = data.aws_iam_policy_document.gateway_consumer.json
}

# ---------- AGENTCORE GATEWAY (SERVICE ROLE) ----------
# The gateway calls its native targets with this role: the directory Lambda function and the model. The VPC-hosted backends don't check the gateway's signature: their network access is decided by VPC Lattice (backends.tf).
resource "aws_iam_role" "gateway" {
  name = "gateway-role-${var.identifier}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gateway" {
  name = "gateway-targets"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeDirectory"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.api_directory.arn
      },
      {
        Sid      = "InvokeModels"
        Effect   = "Allow"
        Action   = ["bedrock-mantle:CreateInference", "bedrock-mantle:GetModel", "bedrock-mantle:ListModels"]
        Resource = "arn:aws:bedrock-mantle:${var.aws_region}:${local.account_id}:project/*"
      },
      # The gateway evaluates its policy engine on every request (the gateway ID starts with its name)
      {
        Sid      = "ReadPolicyEngine"
        Effect   = "Allow"
        Action   = "bedrock-agentcore:GetPolicyEngine"
        Resource = aws_bedrockagentcore_policy_engine.gateway.policy_engine_arn
      },
      {
        Sid      = "AuthorizeWithPolicyEngine"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
        Resource = [aws_bedrockagentcore_policy_engine.gateway.policy_engine_arn, "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:gateway/gateway-${var.identifier}-*"]
      }
    ]
  })
}

# ---------- LAMBDA FUNCTION (REST API) ----------
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
