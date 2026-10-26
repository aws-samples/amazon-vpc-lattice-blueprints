/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform/outputs.tf ---

output "repository_urls" {
  description = "Amazon ECR repositories for the agent and triage images (deploy.sh builds and pushes them)."
  value = {
    agent  = aws_ecr_repository.agent.repository_url
    triage = aws_ecr_repository.triage.repository_url
  }
}

output "ecs_cluster" {
  description = "Amazon ECS cluster running the self-hosted agent (agent-ecs) and the triage agent."
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

output "service_urls" {
  description = "VPC Lattice service URLs (custom domain names), the same from both consumer VPCs."
  value       = local.service_urls
}

output "registry" {
  description = "AWS Agent Registry ID and the IDs of its records (deploy.sh submits them for approval)."
  value = {
    registry_id = aws_agentregistry_registry.registry.registry_id
    record_ids  = [awscc_agentregistry_registry_record.mcp_tickets.record_id, awscc_agentregistry_registry_record.api_directory.record_id, awscc_agentregistry_registry_record.agent_triage.record_id]
  }
}
