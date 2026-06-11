# Amazon VPC Lattice - ECS Fargate Target (AWS CloudFormation)

CloudFormation implementation of the ECS Fargate pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Installed and configured with credentials
- **Permissions required**:
  - CloudFormation
  - VPC Lattice
  - EC2: VPC, subnets, security groups
  - ECS: Cluster, task definition, service
  - ECR: Repository
  - IAM: Create roles and policies
  - Lambda: For custom resources
- **Make**: Installed
- **Docker**: For building and pushing container images to ECR

## Deployment

The Makefile automates the entire deployment process:

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/1-simple_architectures/4-ecs/cloudformation

# Deploy everything (this will take several minutes)
make deploy

# Or specify a different region (default is eu-west-1)
make deploy REGION=us-east-1
```

The `make deploy` command performs the following steps automatically:

1. **Deploy ECR Repository**: Creates the ECR repository
2. **Build & Push Image**: Builds the Docker image and pushes it to ECR
3. **Deploy Service Network**: Creates VPC Lattice service network
4. **Deploy Provider VPC**: Creates the provider VPC, VPC Lattice service, target group, and ECS infrastructure
5. **Deploy Consumer VPC**: Creates the consumer VPC and EC2 instances

### Manual Step-by-Step Deployment

If you prefer to deploy step-by-step:

```bash
# Step 1: Deploy ECR repository
make deploy-repository

# Step 2: Build and push Docker image
make build-push

# Step 3: Deploy VPC Lattice service network
make deploy-sn

# Step 4: Deploy provider VPC, VPC Lattice service, and ECS infrastructure
make deploy-provider

# Step 5: Deploy consumer VPC
make deploy-consumer
```

> **Note**: The Makefile configuration automatically detects your system architecture and configures the ECS task definition accordingly. The Docker image must be built for the same architecture. EC2 instances and ECS Fargate will be deployed in all the Availability Zones configured for the VPC. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Delete all CloudFormation stacks
make undeploy

# Or delete everything including ECR repository and images
make clean
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

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to verify connectivity between consumer instances and ECS tasks through VPC Lattice.
