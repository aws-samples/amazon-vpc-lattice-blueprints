# Amazon VPC Lattice - Multi-Account: Distributed Service Networks (AWS CloudFormation)

CloudFormation implementation of the Distributed Service Networks pattern (two accounts). For the architecture, account structure, and connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **Two AWS Accounts**: Provider account and consumer account.
- **AWS Organizations**: All accounts must be part of the same AWS Organization.
- **AWS CLI**: Installed and configured with credentials for each account.
- **Permissions required** (per account):
  - CloudFormation: Create and manage stacks.
  - VPC Lattice: Service networks, services, target groups, resource gateways, resource configurations.
  - AWS RAM (Resource Access Manager): Create and manage resource shares.
  - AWS Organizations: Read access to describe organization.
  - IAM: Create roles and policies.
  - EC2: VPC, subnets, instances, security groups, VPC endpoints (consumer account).
  - Secrets Manager: Read the cross-account shared secret (consumer account).
  - Lambda: Create functions and execution roles (provider account).
  - RDS: Aurora cluster + DB subnet group, Secrets Manager-managed secret (provider account).
  - KMS: Create a customer-managed key for the Aurora secret (provider account).

## Deployment

> **Important**: Resources must be deployed in a specific order due to cross-account dependencies. Each step must be completed in the specified AWS Account.

### Step 1: Provider Account - Deploy the Service and Aurora Resource Configuration

**AWS Account**: Provider Account

Deploy the Lambda + VPC Lattice service and the provider VPC hosting Aurora + the resource gateway + resource configuration (both the service and the resource configuration are shared via RAM):

> **Note**: this stack provisions an Aurora cluster, so it takes several minutes longer than the consumer stack.

```bash
# Configure AWS credentials for the provider account
export AWS_PROFILE=provider-account

# Deploy the service and Aurora resource configuration
aws cloudformation deploy \
  --template-file provider-account.yaml \
  --stack-name vpclattice-distributed-provider \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-west-1
```

### Step 2: Consumer Account - Deploy Service Network, VPCs, and Associations

**AWS Account**: Consumer Account

Deploy the service network (owned by the consumer), associate the shared service and resource configuration, and deploy the consumer VPC, EC2 instances, and VPC association:

```bash
# Configure AWS credentials for consumer account
export AWS_PROFILE=consumer-account

# Deploy consumer resources
aws cloudformation deploy \
  --template-file consumer-account.yaml \
  --stack-name vpclattice-distributed-consumer \
  --capabilities CAPABILITY_IAM \
  --region eu-west-1
```

> **Note**: The consumer EC2 instances are deployed across all the Availability Zones configured for the consumer VPC, and resources are deployed across multiple accounts. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

> **Important**: Delete resources in reverse order to avoid dependency issues.

### Step 1: Consumer Account

```bash
export AWS_PROFILE=consumer-account
aws cloudformation delete-stack --stack-name vpclattice-distributed-consumer --region eu-west-1
aws cloudformation wait stack-delete-complete --stack-name vpclattice-distributed-consumer --region eu-west-1
```

### Step 2: Provider Account

```bash
export AWS_PROFILE=provider-account
aws cloudformation delete-stack --stack-name vpclattice-distributed-provider --region eu-west-1
aws cloudformation wait stack-delete-complete --stack-name vpclattice-distributed-provider --region eu-west-1
```

> **Note**: Each account creates its own access-logging CloudWatch Logs log group (`/aws/vpclattice/<stack-name>`): the **Consumer Account** stack owns the service-network-scoped log group and the **Provider Account** stack owns the service-scoped one. Each log group is part of that account's stack and is removed when the stack is deleted — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default in both accounts, each at the scope it owns:

- **Consumer Account** (owns the service network): an access log subscription at the service-network scope sends logs to `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the consumer stack.
- **Provider Account** (owns the VPC Lattice service): an access log subscription at the service scope sends logs to `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the provider stack.

- **Where to find the logs**: in each account, CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<stack-name>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<stack-name> --follow
  ```

- **How to interpret them**: each entry records one request (source, target, response code, timing) — useful for observability and, because the service network uses `AWS_IAM` auth, for confirming auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). This pattern creates a log group in each account, so the cost applies in both — a small ongoing cost while the stacks are deployed.

## Testing

After deploying both accounts, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to a consumer instance and verify cross-account connectivity to the shared service and Aurora resource configuration.
