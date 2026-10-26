# Amazon VPC Lattice - Direct Agent Connectivity (AWS CloudFormation)

CloudFormation implementation of the Direct Agent Connectivity pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

| Template | Stack | Resources |
|----------|-------|-----------|
| `common.yaml` | `vpclattice-agentic-direct-common` | Amazon ECR repositories, the S3 bucket for packaged Lambda code, Amazon ECS cluster, application log group and IAM roles |
| `central.yaml` | `vpclattice-agentic-direct-central` | Service network and access logging; endpoints VPC, interface VPC endpoints, resource gateway and one single resource configuration per endpoint (with their resource associations) |
| `backends.yaml` | `vpclattice-agentic-direct-backends` | MCP server, REST API and triage agent, each published as a VPC Lattice service with its custom domain name and its own auth policy, and the provider VPC |
| `agent_registry.yaml` | `vpclattice-agentic-direct-registry` | AWS Agent Registry and its records (MCP server, REST API, A2A agent) |
| `consumer.yaml` | `vpclattice-agentic-direct-consumer` | Consumer VPC A (VPC association) with the self-hosted agent on Amazon ECS, and consumer VPC B (service network endpoint) with the agent on AgentCore Runtime |
| `dns.yaml` | `vpclattice-agentic-direct-dns` | Private hosted zones for the services' custom domain names (one per consumer VPC). A separate stack, because the services' DNS names on the service network endpoint are only known after `consumer.yaml` is deployed |

## Prerequisites

- **AWS Account**: With appropriate IAM permissions, and Amazon Bedrock model access for `MODEL_ID`
- **AWS CLI**: Installed and configured, with the Session Manager plugin (for ECS Exec in the tests)
- **Docker**: With `buildx`, to build `linux/arm64` images
- **Make**: Installed
- **Custom domain and certificate**: a domain for the services (`HOSTED_ZONE_NAME`) and an ACM certificate that covers `*.<HOSTED_ZONE_NAME>` (`CERTIFICATE_ARN`), in the account and Region you deploy to

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/5-agentic_architectures/1-direct_agent_connectivity/cloudformation

# Deploy everything: HOSTED_ZONE_NAME and CERTIFICATE_ARN are required; REGION, IDENTIFIER and MODEL_ID can be overridden
make deploy HOSTED_ZONE_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:eu-west-1:111122223333:certificate/<id>
```

`make deploy` runs the steps in order: `deploy-common`, `build-push` (ARM64 images), `deploy-central`, `deploy-backends` (packages the Lambda code with `aws cloudformation package`), `deploy-registry`, `deploy-consumer`, `deploy-dns` (reads the services' DNS names on the service network endpoint), and `submit-records` (submits the AWS Agent Registry records, which the registry approves automatically).

## Testing

Run the [Testing Connectivity](../README.md#testing-connectivity) steps by chatting with each agent:

```bash
make chat AGENT=ecs       # agent-ecs, through ECS Exec
make chat AGENT=runtime   # agent-runtime, through InvokeAgentRuntime
```

## Cleanup

```bash
make undeploy
```

> **Note**: AgentCore Runtime ENIs can remain in consumer VPC B for some hours after the agent is deleted (see [AgentCore Runtime VPC](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-vpc.html)). If the `consumer` stack fails to delete, run `make undeploy` again later. The access-logging log group is part of the stacks and is removed with them.

## Observability: Access logging

The service network logs to `/aws/vpclattice/<identifier>` (7-day retention): the `SERVICE` log type records every request to the VPC Lattice services (caller principal, auth decision, path and status code), and the `RESOURCE` log type records the connections to the central endpoints.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage).
