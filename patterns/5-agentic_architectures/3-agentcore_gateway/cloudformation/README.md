# Amazon VPC Lattice - Amazon Bedrock AgentCore Gateway (AWS CloudFormation)

CloudFormation implementation of the Amazon Bedrock AgentCore Gateway pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

| Template | Stack | Resources |
|----------|-------|-----------|
| `common.yaml` | `vpclattice-agentic-core-common` | Amazon ECR repositories, the S3 bucket for packaged Lambda code, Amazon ECS cluster, application log group and IAM roles, including the AgentCore Gateway service role (a stack before the gateway, so IAM has propagated it when AgentCore checks the role's policy engine permissions) |
| `gateway.yaml` | `vpclattice-agentic-core-gateway` | The AgentCore Gateway, its policy engine, its native targets (directory on AWS Lambda, and the model on Amazon Bedrock), its application logs, and the callers' permission to invoke it |
| `central.yaml` | `vpclattice-agentic-core-central` | The service network and its access logging; endpoints VPC, interface VPC endpoints (including the AgentCore Gateway endpoint), resource gateway and one single resource configuration per endpoint, associated with the service network |
| `agent_registry.yaml` | `vpclattice-agentic-core-registry` | AWS Agent Registry and its records (AgentCore Gateway's MCP, A2A and model endpoints) |
| `backends.yaml` | `vpclattice-agentic-core-backends` | The tickets and triage VPCs, each with its backend on Amazon ECS behind an internal Application Load Balancer, a resource gateway and a resource configuration, and a VPC association for the central endpoints |
| `targets.yaml` | `vpclattice-agentic-core-targets` | AgentCore Gateway's VPC-hosted targets (tickets and triage, self-managed private endpoints) and its Cedar policies. A separate stack, because the targets need the backends' resource configurations, and the policy engine validates each policy against every target |
| `consumer.yaml` | `vpclattice-agentic-core-consumer` | Consumer VPC A (VPC association) with the self-hosted agent on Amazon ECS, and the agent on AgentCore Runtime (no VPC) |

## Prerequisites

- **AWS Account**: With appropriate IAM permissions, and Amazon Bedrock model access for `MODEL_ID`
- **AWS CLI**: Installed and configured, with the Session Manager plugin (for ECS Exec in the tests)
- **Docker**: With `buildx`, to build `linux/arm64` images
- **Make**: Installed
- **Custom domain and certificate**: a domain for the VPC-hosted backends (`DOMAIN_NAME`) and an ACM public certificate that covers `*.<DOMAIN_NAME>` (`CERTIFICATE_ARN`), in the account and Region you deploy to

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/5-agentic_architectures/3-agentcore_gateway/cloudformation

# Deploy everything: DOMAIN_NAME and CERTIFICATE_ARN are required; REGION, IDENTIFIER and MODEL_ID can be overridden
make deploy DOMAIN_NAME=example.com CERTIFICATE_ARN=arn:aws:acm:eu-west-1:111122223333:certificate/<id>
```

`make deploy` runs the steps in order: `deploy-common`, `build-push` (ARM64 images), `deploy-gateway` (packages the Lambda code with `aws cloudformation package`), `deploy-central` (the gateway's DNS name, which contains its ID, is the custom domain name of its resource configuration), `deploy-registry`, `submit-records` (submits the AWS Agent Registry records, which the registry approves automatically; the triage agent needs the gateway's model record to start), `deploy-backends`, `deploy-targets`, and `deploy-consumer`.

## Testing

Run the [Testing Connectivity](../README.md#testing-connectivity) steps by chatting with each agent:

```bash
make chat AGENT=ecs       # agent-ecs, through ECS Exec
make chat AGENT=runtime   # agent-runtime, through InvokeAgentRuntime
```

The gateway's application logs are in the `GatewayLogGroup` output of the `gateway` stack.

## Cleanup

```bash
make undeploy
```

The access-logging and gateway log groups are part of the stacks and are removed with them.

## Observability: Access logging

The service network logs to `/aws/vpclattice/service-network-<identifier>` (7-day retention): the `RESOURCE` log type records every connection to the central endpoints, including agent-ecs's connections to AgentCore Gateway. Each VPC-hosted backend's resource configuration logs to `/aws/vpclattice/resource-config-<backend>-<identifier>`, which records every connection from AgentCore Gateway to that backend. AgentCore Gateway's application logs (requests, tool calls, target errors and policy decisions) go to `/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/<gateway-id>`.

> **Cost note**: This pattern runs Amazon ECS Fargate tasks and two internal Application Load Balancers while deployed, and access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage).
