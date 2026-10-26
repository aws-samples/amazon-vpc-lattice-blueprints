<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Direct Agent Connectivity (Terraform)

Terraform implementation of the Direct Agent Connectivity pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

| File | Resources |
|------|-----------|
| `main.tf` | Common items: Amazon ECR repositories, Amazon ECS cluster, IAM roles |
| `central.tf` | Service network and access logging; endpoints VPC, interface VPC endpoints, resource gateway and one single resource configuration per endpoint (with their resource associations); private hosted zones for the services' custom domain names (one per consumer VPC) |
| `agent_registry.tf` | AWS Agent Registry and its records (MCP server, REST API, A2A agent) |
| `consumer.tf` | Consumer VPC A (VPC association) with the self-hosted agent on Amazon ECS, and consumer VPC B (service network endpoint) with the agent on AgentCore Runtime |
| `backends.tf` | The provider applications, each published as a VPC Lattice service with its own auth policy: the MCP server and the REST API (AWS Lambda), and the triage A2A agent (Amazon ECS) in the provider VPC |
| `deploy.sh` / `chat.sh` | Deployment in three steps (images first), and the chat client for the [tests](../README.md#testing-connectivity) |

## Prerequisites

- **AWS Account**: With appropriate IAM permissions, and Amazon Bedrock model access for `model_id`
- **Terraform**: >= 1.3.0 installed
- **AWS CLI**: Configured with credentials, with the Session Manager plugin (for ECS Exec in the tests)
- **Docker**: With `buildx`, to build `linux/arm64` images
- **Custom domain and certificate**: a domain for the services (`hosted_zone_name`) and an ACM certificate that covers `*.<hosted_zone_name>` (`certificate_arn`), in the account and Region you deploy to
- **Permissions required**:
  - VPC Lattice: Service networks, services, target groups, resource gateways, resource configurations
  - EC2: VPC, subnets, security groups, VPC endpoints
  - Route 53: private hosted zones and records
  - ECS, ECR, Lambda, IAM, CloudWatch Logs
  - Amazon Bedrock AgentCore (Runtime) and AWS Agent Registry

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/5-agentic_architectures/1-direct_agent_connectivity/terraform

# Configure variables in terraform.tfvars: hosted_zone_name and certificate_arn (required); identifier, aws_region, model_id (optional)

# Deploy: ECR repositories, then the ARM64 images, then the rest of the pattern and the registry record submission
./deploy.sh
```

The script runs three steps: it creates the Amazon ECR repositories, builds and pushes the agent and triage images (`linux/arm64`), and deploys the rest of the pattern. It then submits the AWS Agent Registry records, which the registry approves automatically.

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

> **Note**: AgentCore Runtime ENIs can remain in consumer VPC B for some hours after the agent is deleted (see [AgentCore Runtime VPC](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-vpc.html)). If `terraform destroy` fails on that VPC, run it again later. The access-logging log group is managed by this pattern and is removed with it.

## Observability: Access logging

The service network logs to `/aws/vpclattice/<identifier>` (7-day retention): the `SERVICE` log type records every request to the VPC Lattice services (caller principal, auth decision, path and status code), and the `RESOURCE` log type records the connections to the central endpoints.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage).

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.69.0 |
| <a name="requirement_awscc"></a> [awscc](#requirement\_awscc) | >= 1.106.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.7.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.69.0 |
| <a name="provider_awscc"></a> [awscc](#provider\_awscc) | >= 1.106.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_agent_ecs_vpc"></a> [agent\_ecs\_vpc](#module\_agent\_ecs\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_agent_runtime_vpc"></a> [agent\_runtime\_vpc](#module\_agent\_runtime\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_agent_triage_service"></a> [agent\_triage\_service](#module\_agent\_triage\_service) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |
| <a name="module_api_directory_service"></a> [api\_directory\_service](#module\_api\_directory\_service) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |
| <a name="module_endpoints_vpc"></a> [endpoints\_vpc](#module\_endpoints\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_mcp_tickets_service"></a> [mcp\_tickets\_service](#module\_mcp\_tickets\_service) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |
| <a name="module_provider_vpc"></a> [provider\_vpc](#module\_provider\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | ../../../tf_modules/vpc_endpoints | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_agentregistry_registry.registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/agentregistry_registry) | resource |
| [aws_bedrockagentcore_agent_runtime.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_agent_runtime) | resource |
| [aws_cloudwatch_log_group.applications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_repository.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecs_cluster.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_infrastructure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_infrastructure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.api_directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.mcp_tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_route53_record.consumer_vpc_a_agent_triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_a_agent_triage_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_a_api_directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_a_api_directory_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_a_mcp_tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_a_mcp_tickets_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_agent_triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_agent_triage_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_api_directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_api_directory_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_mcp_tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.consumer_vpc_b_mcp_tickets_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.consumer_vpc_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53_zone.consumer_vpc_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.agent_ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.agent_ecs_vpc_lattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.agent_runtime_endpoint_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.provider_vpc_lattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.resource_gateway_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.triage_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.agent_ecs_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.agent_runtime_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.agent_runtime_service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.provider_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.agent_ecs_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.agent_runtime_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.resource_gateway_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.triage_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.agent_ecs_vpc_lattice_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.agent_runtime_endpoint_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.provider_vpc_lattice_from_triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.triage_from_vpclattice](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.service_network_resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_access_log_subscription.service_network_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_auth_policy.agent_triage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_auth_policy) | resource |
| [aws_vpclattice_auth_policy.api_directory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_auth_policy) | resource |
| [aws_vpclattice_auth_policy.mcp_tickets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_auth_policy) | resource |
| [aws_vpclattice_auth_policy.service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_auth_policy) | resource |
| [aws_vpclattice_resource_configuration.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_gateway.resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_vpclattice_service_network.service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network) | resource |
| [aws_vpclattice_service_network_resource_association.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_resource_association) | resource |
| [aws_vpclattice_service_network_vpc_association.agent_ecs_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [aws_vpclattice_service_network_vpc_association.provider_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [awscc_agentregistry_registry_record.agent_triage](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [awscc_agentregistry_registry_record.api_directory](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [awscc_agentregistry_registry_record.mcp_tickets](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/agentregistry_registry_record) | resource |
| [archive_file.api_directory](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.mcp_tickets](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ec2_managed_prefix_list.vpclattice](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_iam_policy_document.agent_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.agent_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.agent_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_tasks_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.invoke_models](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_vpc_endpoint_associations.agent_runtime_service_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint_associations) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of the AWS Certificate Manager (ACM) certificate for the services' HTTPS listeners. It must cover *.<hosted\_zone\_name>. | `string` | n/a | yes |
| <a name="input_hosted_zone_name"></a> [hosted\_zone\_name](#input\_hosted\_zone\_name) | Domain of the VPC Lattice services' custom domain names (for example, example.com gives mcp-tickets.example.com). Each consumer VPC gets a private hosted zone with this name. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to build the pattern. | `string` | `"eu-west-1"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Pattern identifier. | `string` | `"agentic-direct"` | no |
| <a name="input_model_id"></a> [model\_id](#input\_model\_id) | Amazon Bedrock model (or inference profile) ID used by the agents. Use a model your organization approves for your use case. | `string` | `"eu.anthropic.claude-haiku-5-5"` | no |
| <a name="input_vpc_endpoints"></a> [vpc\_endpoints](#input\_vpc\_endpoints) | AWS services centralized in the endpoints VPC (key = short name used in resource names, value = interface endpoint service suffix and DNS name). | <pre>map(object({<br/>    service     = string<br/>    domain_name = string<br/>  }))</pre> | <pre>{<br/>  "agentcore": {<br/>    "domain_name": "bedrock-agentcore.<region>.amazonaws.com",<br/>    "service": "bedrock-agentcore"<br/>  },<br/>  "bedrock": {<br/>    "domain_name": "bedrock-runtime.<region>.amazonaws.com",<br/>    "service": "bedrock-runtime"<br/>  },<br/>  "ecr-api": {<br/>    "domain_name": "api.ecr.<region>.amazonaws.com",<br/>    "service": "ecr.api"<br/>  },<br/>  "ecr-dkr": {<br/>    "domain_name": "<account>.dkr.ecr.<region>.amazonaws.com",<br/>    "service": "ecr.dkr"<br/>  },<br/>  "logs": {<br/>    "domain_name": "logs.<region>.amazonaws.com",<br/>    "service": "logs"<br/>  },<br/>  "registry": {<br/>    "domain_name": "agent-registry.<region>.api.aws",<br/>    "service": "agent-registry"<br/>  },<br/>  "ssm-msgs": {<br/>    "domain_name": "ssmmessages.<region>.amazonaws.com",<br/>    "service": "ssmmessages"<br/>  },<br/>  "sts": {<br/>    "domain_name": "sts.<region>.amazonaws.com",<br/>    "service": "sts"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_ecs_service"></a> [agent\_ecs\_service](#output\_agent\_ecs\_service) | Amazon ECS service of the self-hosted agent (agent-ecs). |
| <a name="output_agent_runtime_arn"></a> [agent\_runtime\_arn](#output\_agent\_runtime\_arn) | ARN of the agent on AgentCore Runtime (agent-runtime). |
| <a name="output_ecs_cluster"></a> [ecs\_cluster](#output\_ecs\_cluster) | Amazon ECS cluster running the self-hosted agent (agent-ecs) and the triage agent. |
| <a name="output_registry"></a> [registry](#output\_registry) | AWS Agent Registry ID and the IDs of its records (deploy.sh submits them for approval). |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Amazon ECR repositories for the agent and triage images (deploy.sh builds and pushes them). |
| <a name="output_service_urls"></a> [service\_urls](#output\_service\_urls) | VPC Lattice service URLs (custom domain names), the same from both consumer VPCs. |
<!-- END_TF_DOCS -->
