# Amazon VPC Lattice - Centralized VPC Endpoints (AWS CloudFormation)

CloudFormation implementation of the Centralized VPC Endpoints pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Installed and configured with credentials
- **Permissions required**:
  - CloudFormation
  - VPC Lattice: Service networks, resource gateways, resource configurations
  - EC2: VPC, subnets, instances, security groups, VPC endpoints
  - IAM: Create roles and policies
- **Make**: Installed

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/3-advanced_architectures/1-centralized_vpc_endpoints/cloudformation

# Deploy everything
make deploy

# Or deploy step-by-step:
make deploy-endpoints  # centralized VPC endpoints VPC
make deploy-consumer   # consumer VPC and EC2 instances
```

> **Note**: EC2 instances and VPC endpoints will be deployed in all the Availability Zones configured for each VPC. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Delete everything
make undeploy
```

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<stack-name>`) is part of the consumer stack and is removed when the stacks are deleted — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the service network records a log entry for every request that flows through it and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the consumer stack.

- **Where to find the logs**: CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<stack-name>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<stack-name> --follow
  ```

- **How to interpret them**: each entry records one request through the service network (source, target, response code, timing) — useful for observability of traffic to the centralized resources.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). For this demo it is a small ongoing cost while the stack is deployed.

## Testing

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to a consumer instance via Systems Manager and confirm AWS service endpoints resolve and respond through VPC Lattice.
