# Amazon VPC Lattice - Multi-Account: Centralized Service Network (AWS CloudFormation)

CloudFormation implementation of the Centralized Service Network pattern (three accounts). For the architecture, account structure, and connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **Three AWS Accounts**: Network account (central), provider account, and consumer account.
- **AWS Organizations**: All accounts must be part of the same AWS Organization.
- **AWS CLI**: Installed and configured with credentials for each account.
- **Permissions required** (per account):
  - CloudFormation: Create and manage stacks.
  - VPC Lattice: Service networks, services, target groups.
  - AWS RAM (Resource Access Manager): Create and manage resource shares.
  - AWS Organizations: Read access to describe organization.
  - EC2: VPC, subnets, instances, security groups, VPC endpoints (consumer account).
  - Lambda: Create functions and execution roles (provider account).
  - RDS: Aurora cluster + DB subnet group, Secrets Manager-managed secret (provider account).
  - KMS: Create a customer-managed key for the Aurora secret (provider account).
  - Secrets Manager: Read the cross-account shared secret (consumer account).
  - IAM: Create roles and policies.

## Deployment Order

> **Important**: Resources must be deployed in a specific order due to cross-account dependencies. Each step must be completed in the specified AWS Account.

### Step 1: Provider Account - Deploy the Service and Aurora Resource Configuration

**AWS Account**: Provider Account

Deploy the Lambda + VPC Lattice service and the provider VPC hosting Aurora + the resource gateway + resource configuration (both are shared via one RAM share):

> **Note**: this stack provisions an Aurora cluster, so it takes several minutes longer than the others.

```bash
# Configure AWS credentials for the provider account
export AWS_PROFILE=provider-account

# Deploy the service
aws cloudformation deploy \
  --template-file provider-account.yaml \
  --stack-name vpclattice-centralized-provider \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-west-1
```

### Step 2: Network Account - Deploy Service Network

**AWS Account**: Network Account (Central)

Deploy the VPC Lattice service network and associate the shared service:

```bash
# Configure AWS credentials for network account
export AWS_PROFILE=network-account

# Deploy the service network
aws cloudformation deploy \
  --template-file service-network-account.yaml \
  --stack-name vpclattice-centralized-service-network \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-west-1
```

### Step 3: Consumer Account - Deploy VPCs and Associations

**AWS Account**: Consumer Account

Deploy consumer VPCs, EC2 instances, and VPC associations:

```bash
# Configure AWS credentials for consumer account
export AWS_PROFILE=consumer-account

# Deploy consumer resources
aws cloudformation deploy \
  --template-file consumer-account.yaml \
  --stack-name vpclattice-centralized-consumer \
  --capabilities CAPABILITY_IAM \
  --region eu-west-1
```

> **Note**: The consumer EC2 instances are deployed across all the Availability Zones configured for the consumer VPC, and resources are deployed across multiple accounts. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

> **Important**: Delete resources in reverse order to avoid dependency issues.

### Step 1: Consumer Account

```bash
export AWS_PROFILE=consumer-account
aws cloudformation delete-stack --stack-name vpclattice-centralized-consumer --region eu-west-1
aws cloudformation wait stack-delete-complete --stack-name vpclattice-centralized-consumer --region eu-west-1
```

### Step 2: Network Account

```bash
export AWS_PROFILE=network-account
aws cloudformation delete-stack --stack-name vpclattice-centralized-service-network --region eu-west-1
aws cloudformation wait stack-delete-complete --stack-name vpclattice-centralized-service-network --region eu-west-1
```

### Step 3: Provider Account

```bash
export AWS_PROFILE=provider-account
aws cloudformation delete-stack --stack-name vpclattice-centralized-provider --region eu-west-1
aws cloudformation wait stack-delete-complete --stack-name vpclattice-centralized-provider --region eu-west-1
```

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<stack-name>`) is part of the **Network Account** service-network stack (it owns the service network) and is removed when that stack is deleted — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. The **Network Account** owns the service network, so its access log subscription records a log entry for every request that flows through the network and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the service-network stack.

- **Where to find the logs**: in the Network Account, CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<stack-name>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<stack-name> --follow
  ```

- **How to interpret them**: each entry records one request through the service network (source, target, response code, timing) — useful for observability and, because the service network uses `AWS_IAM` auth, for confirming auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). For this demo it is a small ongoing cost while the stacks are deployed.

## Testing

After deploying all three accounts, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to a consumer instance and verify cross-account connectivity to the shared service.
