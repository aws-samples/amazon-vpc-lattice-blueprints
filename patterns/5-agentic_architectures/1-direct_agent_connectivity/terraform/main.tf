/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/main.tf ---

# Common items. The rest of the pattern is split by role:
# - central.tf: service network, centralized AWS service endpoints and DNS resolution of the VPC Lattice services
# - agent_registry.tf: AWS Agent Registry and its records
# - consumer.tf: consumer VPC A (agent-ecs, VPC association) and consumer VPC B (agent-runtime, service network endpoint)
# - backends.tf: the MCP server, REST API and triage agent (provider VPC), each with its own VPC Lattice service and auth policy

data "aws_caller_identity" "current" {}

locals {
  # The URL of each backend's VPC Lattice service (its custom domain name), the same from both consumer VPCs: each
  # consumer VPC's private hosted zone resolves it to its own way into the service network (central.tf)
  service_urls = {
    mcp-tickets   = "https://${module.mcp_tickets_service.services["mcp-tickets"].attributes.custom_domain_name}"
    api-directory = "https://${module.api_directory_service.services["api-directory"].attributes.custom_domain_name}"
    agent-triage  = "https://${module.agent_triage_service.services["agent-triage"].attributes.custom_domain_name}"
  }
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

# ---------- AMAZON ECS CLUSTER AND APPLICATION LOGS ----------
resource "aws_ecs_cluster" "cluster" {
  name = "cluster-${var.identifier}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Application logs (agents and triage)
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

# ---------- POLICY DOCUMENTS (RE-USED BY THE AGENT ROLES) ----------
# Every agent (agent-ecs, agent-runtime, triage) invokes Amazon Bedrock models
data "aws_iam_policy_document" "invoke_models" {
  statement {
    sid       = "InvokeModels"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["*"]
  }
}

# The two consuming agents also call the VPC Lattice services and discover them in the AWS Agent Registry
data "aws_iam_policy_document" "agent_permissions" {
  source_policy_documents = [data.aws_iam_policy_document.invoke_models.json]

  statement {
    sid       = "InvokeVpcLatticeServices"
    actions   = ["vpc-lattice-svcs:Invoke"]
    resources = ["*"]
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
  source_policy_documents = [data.aws_iam_policy_document.agent_permissions.json]

  # A2A to the agent on AgentCore Runtime
  statement {
    sid       = "InvokeAgentRuntime"
    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = [aws_bedrockagentcore_agent_runtime.agent.agent_runtime_arn, "${aws_bedrockagentcore_agent_runtime.agent.agent_runtime_arn}/*"]
  }

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
  source_policy_documents = [data.aws_iam_policy_document.agent_permissions.json]

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
resource "aws_iam_role" "triage" {
  name               = "triage-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy" "triage" {
  # checkov:skip=CKV_AWS_355:Amazon Bedrock model and inference profile ARNs vary by model and Region; the demo grants invoke on all models
  name   = "invoke-models"
  role   = aws_iam_role.triage.id
  policy = data.aws_iam_policy_document.invoke_models.json
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
