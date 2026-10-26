/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/3-agentcore_gateway/terraform/outputs.tf ---

output "repository_urls" {
  description = "Amazon ECR repositories for the agent, triage and tickets images (deploy.sh builds and pushes them)."
  value = {
    agent   = aws_ecr_repository.agent.repository_url
    triage  = aws_ecr_repository.triage.repository_url
    tickets = aws_ecr_repository.tickets.repository_url
  }
}

output "ecs_cluster" {
  description = "Amazon ECS cluster running the self-hosted agent (agent-ecs) and the tickets and triage backends."
  value       = aws_ecs_cluster.cluster.name
}

output "agent_ecs_service" {
  description = "Amazon ECS service of the self-hosted agent (agent-ecs)."
  value       = aws_ecs_service.agent_ecs.name
}

output "agent_runtime_arn" {
  description = "ARN of the agent on AgentCore Runtime (agent-runtime)."
  value       = aws_bedrockagentcore_agent_runtime.agent.agent_runtime_arn
}

output "gateway_url" {
  description = "AgentCore Gateway URL, the same from every caller."
  value       = local.gateway_url
}

output "gateway_log_group" {
  description = "CloudWatch Logs group with AgentCore Gateway's application logs (requests, tool calls, target errors)."
  value       = aws_cloudwatch_log_group.gateway_logs.name
}

output "backend_resource_configurations" {
  description = "VPC Lattice resource configurations of the VPC-hosted backends (the gateway's self-managed private endpoints)."
  value = {
    tickets = aws_vpclattice_resource_configuration.tickets.arn
    triage  = aws_vpclattice_resource_configuration.triage.arn
  }
}

output "registry" {
  description = "AWS Agent Registry ID and the IDs of its records (deploy.sh submits them for approval)."
  value = {
    registry_id = aws_agentregistry_registry.registry.registry_id
    record_ids  = [awscc_agentregistry_registry_record.gateway_tools.record_id, awscc_agentregistry_registry_record.gateway_triage.record_id, awscc_agentregistry_registry_record.gateway_llm.record_id]
  }
}
