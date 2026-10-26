# Amazon VPC Lattice - Self-Hosted AI Gateway (AWS CloudFormation)

CloudFormation implementation of the Self-Hosted AI Gateway pattern (LiteLLM). For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

| Template | Stack | Resources |
|----------|-------|-----------|
| `common.yaml` | `vpclattice-agentic-gateway-common` | Amazon ECR repositories, the S3 bucket for packaged Lambda code, Amazon ECS cluster, application log group, IAM roles, the deploy-time secrets (LiteLLM master key and one virtual key per caller) and the VPC Lattice managed prefix list lookup |
| `central.yaml` | `vpclattice-agentic-gateway-central` | The `agents` and `backends` service networks and their access logging; endpoints VPC, interface VPC endpoints, resource gateway and one single resource configuration per endpoint (associated with the networks that use it); the gateway VPC and its VPC association to `backends` |
| `agent_registry.yaml` | `vpclattice-agentic-gateway-registry` | AWS Agent Registry and its records (the gateway's MCP, A2A and model endpoints) |
| `backends.yaml` | `vpclattice-agentic-gateway-backends` | MCP server, REST API and triage agent, each published as a VPC Lattice service in `backends` with its custom domain name and auth policy, and the provider VPC (VPC association to `agents`) |
| `gateway.yaml` | `vpclattice-agentic-gateway-gateway` | The AI gateway (LiteLLM on Amazon ECS), its database (Amazon RDS for PostgreSQL), the private hosted zone for the backends' custom domain names (gateway VPC), and the `ai-gateway` service with its custom domain name, auth policy and the callers' permission to invoke it |
| `consumer.yaml` | `vpclattice-agentic-gateway-consumer` | Consumer VPC A (VPC association) with the self-hosted agent on Amazon ECS, and consumer VPC B (service network endpoint) with the agent on AgentCore Runtime |
| `dns.yaml` | `vpclattice-agentic-gateway-dns` | Private hosted zones for the `ai-gateway` custom domain name (consumer VPC A and the provider VPC, and consumer VPC B). A separate stack, because the service's DNS name on the service network endpoint is only known after `consumer.yaml` is deployed |

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
cd patterns/5-agentic_architectures/2-self_hosted_ai_gateway/cloudformation

# Deploy everything: HOSTED_ZONE_NAME and CERTIFICATE_ARN are required; REGION, IDENTIFIER and MODEL_ID can be overridden
make deploy HOSTED_ZONE_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:eu-west-1:111122223333:certificate/<id>
```

`make deploy` runs the steps in order: `deploy-common`, `build-push` (ARM64 images), `deploy-central`, `deploy-registry`, `submit-records` (submits the AWS Agent Registry records, which the registry approves automatically; the triage agent needs the gateway's model record to start), `deploy-backends` (packages the Lambda code with `aws cloudformation package`), `deploy-gateway`, `deploy-consumer`, and `deploy-dns` (reads the `ai-gateway` DNS name on the service network endpoint).

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

> **Note**: AgentCore Runtime ENIs can remain in consumer VPC B for some hours after the agent is deleted (see [AgentCore Runtime VPC](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-vpc.html)). If the `consumer` stack fails to delete, run `make undeploy` again later. The access-logging log groups are part of the stacks and are removed with them.

## Observability: Access logging

Each service network logs to its own `/aws/vpclattice/<network>-<identifier>` group (7-day retention): the `agents` group records the hop to the gateway, and the `backends` group records the gateway's hop to the backends. The `SERVICE` log type records every request to the VPC Lattice services (caller principal, auth decision, path and status code), and the `RESOURCE` log type records the connections to the central endpoints. LiteLLM's own logs add the virtual key, model and cost of each request.

> **Cost note**: This pattern runs an Amazon RDS for PostgreSQL instance and Amazon ECS Fargate tasks while deployed, and access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage).
