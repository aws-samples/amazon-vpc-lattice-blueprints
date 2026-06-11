# Amazon VPC Lattice - Lambda Function Target (AWS CloudFormation)

CloudFormation implementation of the Lambda Function pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Installed and configured with credentials
- **Permissions required**:
  - CloudFormation
  - VPC Lattice
  - EC2: VPC, subnets, instances, security groups
  - Lambda: Create functions and permissions
  - IAM: Create roles and policies
- **Make**: Installed

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/1-simple_architectures/3-lambda_function/cloudformation

# Deploy everything (Networking + Consumer + Lambda Function)
make deploy

# Or deploy step-by-step:
make deploy-sn        # Deploy networking and service network first
make deploy-consumer  # Then deploy consumer VPC and instances
make deploy-provider  # Finally deploy Lambda function and VPC Lattice service
```

> **Note**: The consumer EC2 instances are deployed in all the Availability Zones configured for the VPC. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Delete everything
make undeploy
```

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<stack-name>`) is part of the service-network stack and is removed when the stacks are deleted — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the service network records a log entry for every request that flows through it and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the stack.

- **Where to find the logs**: CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<stack-name>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<stack-name> --follow
  ```

- **How to interpret them**: each entry records one request through the service network/service (source, target, response code, timing) — useful for observability and, for auth-enabled services, for confirming auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). For this demo it is a small ongoing cost while the stack is deployed.

## Testing

After successful deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to verify connectivity between consumer instances and the Lambda function through VPC Lattice.
