<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Amazon Bedrock AgentCore Gateway (Terraform)

Terraform implementation of the Amazon Bedrock AgentCore Gateway pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

| File | Resources |
|------|-----------|
| `main.tf` | Common items: Amazon ECR repositories, Amazon ECS cluster, IAM roles (including the AgentCore Gateway service role) |
| `central.tf` | The service network and its access logging; endpoints VPC, interface VPC endpoints (including the AgentCore Gateway endpoint), resource gateway and one single resource configuration per endpoint, associated with the service network |
| `gateway.tf` | The AgentCore Gateway, its policy engine and Cedar policies, and its targets: directory (AWS Lambda), model (Amazon Bedrock), tickets (MCP server) and triage (A2A agent) with self-managed private endpoints |
| `agent_registry.tf` | AWS Agent Registry and its records (AgentCore Gateway's MCP, A2A and model endpoints) |
| `consumer.tf` | Consumer VPC A (VPC association) with the self-hosted agent on Amazon ECS, and the agent on AgentCore Runtime (no VPC) |
| `backends.tf` | The directory API (AWS Lambda); the tickets and triage VPCs, each with its backend on Amazon ECS behind an internal Application Load Balancer, a resource gateway and a resource configuration, and a VPC association for the central endpoints |
| `deploy.sh` / `chat.sh` | Deployment in three steps (images first), and the chat client for the [tests](../README.md#testing-connectivity) |

## Prerequisites

- **AWS Account**: With appropriate IAM permissions, and Amazon Bedrock model access for `model_id`
- **Terraform**: >= 1.3.0 installed
- **AWS CLI**: Configured with credentials, with the Session Manager plugin (for ECS Exec in the tests)
- **Docker**: With `buildx`, to build `linux/arm64` images
- **Custom domain and certificate**: a domain for the VPC-hosted backends (`domain_name`) and an ACM public certificate that covers `*.<domain_name>` (`certificate_arn`), in the account and Region you deploy to
- **Permissions required**:
  - VPC Lattice: Service networks, resource gateways, resource configurations, and the permissions AgentCore uses to associate a self-managed resource configuration with its own service network (see [self-managed Lattice resources](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/vpc-egress-private-endpoints.html))
  - EC2: VPC, subnets, security groups, VPC endpoints
  - Elastic Load Balancing, ECS, ECR, Lambda, IAM, CloudWatch Logs
  - Amazon Bedrock AgentCore (Gateway, Policy, Runtime) and AWS Agent Registry

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/5-agentic_architectures/3-agentcore_gateway/terraform

# Configure variables in terraform.tfvars: domain_name and certificate_arn (required); identifier, aws_region, model_id (optional)

# Deploy: ECR repositories, then the ARM64 images, then the rest of the pattern and the registry record submission
./deploy.sh
```

The script runs three steps: it creates the Amazon ECR repositories, builds and pushes the agent, triage and tickets images (`linux/arm64`), and deploys the rest of the pattern. It then submits the AWS Agent Registry records, which the registry approves automatically.

## Testing

Run the [Testing Connectivity](../README.md#testing-connectivity) steps by chatting with each agent:

```bash
./chat.sh ecs       # agent-ecs, through ECS Exec
./chat.sh runtime   # agent-runtime, through InvokeAgentRuntime
```

## Cleanup

```bash
terraform destroy
```

The access-logging log groups are managed by this pattern and are removed with it.

## Observability: Access logging

The service network logs to `/aws/vpclattice/service-network-<identifier>` (7-day retention): the `RESOURCE` log type records every connection to the central endpoints, including agent-ecs's connections to AgentCore Gateway. Each VPC-hosted backend's resource configuration logs to `/aws/vpclattice/resource-config-<backend>-<identifier>`, which records every connection from AgentCore Gateway to that backend. AgentCore Gateway's application logs (requests, tool calls, target errors and policy decisions) go to `/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/<gateway-id>` (output `gateway_log_group`).

> **Cost note**: This pattern runs Amazon ECS Fargate tasks and two internal Application Load Balancers while deployed, and access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage).

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.70.0 |
| <a name="requirement_awscc"></a> [awscc](#requirement\_awscc) | >= 1.106.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.12.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.7.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.70.0 |
| <a name="provider_awscc"></a> [awscc](#provider\_awscc) | >= 1.106.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.12.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_agent_ecs_vpc"></a> [agent\_ecs\_vpc](#module\_agent\_ecs\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_endpoints_vpc"></a> [endpoints\_vpc](#module\_endpoints\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_tickets_vpc"></a> [tickets\_vpc](#module\_tickets\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_triage_vpc"></a> [triage\_vpc](#module\_triage\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | ../../../tf_modules/vpc_endpoints | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_agentregistry_registry.registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/agentregistry_registry) | resource |
| [aws_bedrockagentcore_agent_runtime.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_agent_runtime) | resource |
| [aws_bedrockagentcore_gateway.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway) | resource |
| [aws_bedrockagentcore_gateway_target.directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway_target) | resource |
| [aws_bedrockagentcore_gateway_target.model](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway_target) | resource |
| [aws_bedrockagentcore_gateway_target.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway_target) | resource |
| [aws_bedrockagentcore_gateway_target.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_gateway_target) | resource |
| [aws_bedrockagentcore_policy.callers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_policy) | resource |
| [aws_bedrockagentcore_policy_engine.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_policy_engine) | resource |
| [aws_cloudwatch_log_delivery.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery) | resource |
| [aws_cloudwatch_log_delivery_destination.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_destination) | resource |
| [aws_cloudwatch_log_delivery_source.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_source) | resource |
| [aws_cloudwatch_log_group.applications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.gateway_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.tickets_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.triage_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_repository.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecs_cluster.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.api_directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lb.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.agent_ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.agent_ecs_vpc_lattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.resource_gateway_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tickets_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tickets_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tickets_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tickets_vpc_lattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.triage_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.triage_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.triage_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.triage_vpc_lattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.agent_ecs_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.tickets_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.triage_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.agent_ecs_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.resource_gateway_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.tickets_alb_to_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.tickets_resource_gateway_to_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.tickets_tasks_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.triage_alb_to_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.triage_resource_gateway_to_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.triage_tasks_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.agent_ecs_vpc_lattice_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.tickets_alb_from_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.tickets_tasks_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.tickets_vpc_lattice_from_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.triage_alb_from_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.triage_tasks_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.triage_vpc_lattice_from_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_access_log_subscription.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_access_log_subscription.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_resource_configuration.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_configuration.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_configuration.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_gateway.resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_vpclattice_resource_gateway.tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_vpclattice_resource_gateway.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_vpclattice_service_network.service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network) | resource |
| [aws_vpclattice_service_network_resource_association.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_resource_association) | resource |
| [aws_vpclattice_service_network_vpc_association.agent_ecs_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [aws_vpclattice_service_network_vpc_association.tickets_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [aws_vpclattice_service_network_vpc_association.triage_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [awscc_agentregistry_registry_record.gateway_llm](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [awscc_agentregistry_registry_record.gateway_tools](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [awscc_agentregistry_registry_record.gateway_triage](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [time_sleep.gateway_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [archive_file.api_directory](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_tasks_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.gateway_consumer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of the AWS Certificate Manager (ACM) public certificate for the backends' load balancers. It must cover *.<domain\_name>, and be in the account and Region you deploy to. | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain of the VPC-hosted backends' names (for example, example.com gives tickets.example.com and triage.example.com). The gateway calls the backends by these names; no hosted zone is needed. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to build the pattern. | `string` | `"eu-west-1"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Pattern identifier. | `string` | `"agentic-core"` | no |
| <a name="input_model_id"></a> [model\_id](#input\_model\_id) | Model ID the gateway's inference target serves, as listed by Amazon Bedrock's OpenAI-compatible endpoint (bedrock-mantle). Use a model your organization approves for your use case. | `string` | `"anthropic.claude-haiku-4-5"` | no |
| <a name="input_vpc_endpoints"></a> [vpc\_endpoints](#input\_vpc\_endpoints) | AWS services centralized in the endpoints VPC (key = short name used in resource names, value = interface endpoint service suffix and DNS name). | <pre>map(object({<br/>    service     = string<br/>    domain_name = string<br/>  }))</pre> | <pre>{<br/>  "ecr-api": {<br/>    "domain_name": "api.ecr.<region>.amazonaws.com",<br/>    "service": "ecr.api"<br/>  },<br/>  "ecr-dkr": {<br/>    "domain_name": "<account>.dkr.ecr.<region>.amazonaws.com",<br/>    "service": "ecr.dkr"<br/>  },<br/>  "gateway": {<br/>    "domain_name": "<gateway-id>.gateway.bedrock-agentcore.<region>.amazonaws.com",<br/>    "service": "bedrock-agentcore.gateway"<br/>  },<br/>  "logs": {<br/>    "domain_name": "logs.<region>.amazonaws.com",<br/>    "service": "logs"<br/>  },<br/>  "registry": {<br/>    "domain_name": "agent-registry.<region>.api.aws",<br/>    "service": "agent-registry"<br/>  },<br/>  "ssm-msgs": {<br/>    "domain_name": "ssmmessages.<region>.amazonaws.com",<br/>    "service": "ssmmessages"<br/>  },<br/>  "sts": {<br/>    "domain_name": "sts.<region>.amazonaws.com",<br/>    "service": "sts"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_ecs_service"></a> [agent\_ecs\_service](#output\_agent\_ecs\_service) | Amazon ECS service of the self-hosted agent (agent-ecs). |
| <a name="output_agent_runtime_arn"></a> [agent\_runtime\_arn](#output\_agent\_runtime\_arn) | ARN of the agent on AgentCore Runtime (agent-runtime). |
| <a name="output_backend_resource_configurations"></a> [backend\_resource\_configurations](#output\_backend\_resource\_configurations) | VPC Lattice resource configurations of the VPC-hosted backends (the gateway's self-managed private endpoints). |
| <a name="output_ecs_cluster"></a> [ecs\_cluster](#output\_ecs\_cluster) | Amazon ECS cluster running the self-hosted agent (agent-ecs) and the tickets and triage backends. |
| <a name="output_gateway_log_group"></a> [gateway\_log\_group](#output\_gateway\_log\_group) | CloudWatch Logs group with AgentCore Gateway's application logs (requests, tool calls, target errors). |
| <a name="output_gateway_url"></a> [gateway\_url](#output\_gateway\_url) | AgentCore Gateway URL, the same from every caller. |
| <a name="output_registry"></a> [registry](#output\_registry) | AWS Agent Registry ID and the IDs of its records (deploy.sh submits them for approval). |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Amazon ECR repositories for the agent, triage and tickets images (deploy.sh builds and pushes them). |
<!-- END_TF_DOCS -->
