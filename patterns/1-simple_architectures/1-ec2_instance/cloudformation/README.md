# Amazon VPC Lattice - EC2 Instance Target (AWS CloudFormation)

CloudFormation implementation of the EC2 Instance pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Installed and configured with credentials
- **Permissions required**:
  - CloudFormation
  - VPC Lattice
  - EC2: VPC, subnets, instances, security groups
  - IAM: Create roles and policies
- **Make**: Installed
- **(Optional) Custom Domain Name**: If you want to configure Service2 with a custom domain name:
  - A registered domain name
  - ACM certificate ARN for the domain
  - Route 53 hosted zone name

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/1-simple_architectures/1-ec2_instance/cloudformation

# Set custom domain configuration
export CUSTOM_DOMAIN_NAME="service2.example.com"
export CERTIFICATE_ARN="arn:aws:acm:eu-west-1:123456789012:certificate/xxxxx"
export HOSTED_ZONE_NAME="example.com"

# Deploy everything
make deploy

# Or deploy step-by-step:
make deploy-sn        # service network
make deploy-consumer  # consumer VPC and EC2 instances
make deploy-provider  # provider VPC and VPC Lattice services
```

> **Note**: EC2 instances will be deployed in all the Availability Zones configured for each VPC. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

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

After successful deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to verify both VPC Lattice services.
