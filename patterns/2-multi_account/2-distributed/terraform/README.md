# Amazon VPC Lattice - Multi-Account: Distributed Service Networks (Terraform)

Terraform implementation of the Distributed Service Networks pattern, with one module per account (`provider-account/`, `consumer-account/`). For the architecture, account structure, and connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **Two AWS Accounts**: Provider account and consumer account.
- **AWS Organizations**: All accounts must be part of the same AWS Organization.
- **Terraform**: >= 1.3.0 installed.
- **AWS CLI**: Configured with credentials for each account.
- **Permissions required** (per account):
  - VPC Lattice: Service networks, services, target groups, resource gateways, resource configurations.
  - AWS RAM (Resource Access Manager): Create and manage resource shares.
  - AWS Organizations: Read access to describe organization.
  - IAM: Create roles and policies.
  - EC2: VPC, subnets, instances, security groups, VPC endpoints (consumer account)
  - Secrets Manager: Read the cross-account shared secret (consumer account)
  - Lambda: Create functions and execution roles (provider account)
  - RDS: Aurora cluster + DB subnet group, Secrets Manager-managed secret (provider account)
  - KMS: Create a customer-managed key for the Aurora secret (provider account)

## Deployment Order

> **Important**: Resources must be deployed in a specific order due to cross-account dependencies. Each step must be completed in the specified AWS Account.

### Step 1: Provider Account - Deploy the Service and Aurora Resource Configuration

**AWS Account**: Provider Account

Deploy the Lambda + VPC Lattice service and the provider VPC hosting Aurora + the resource gateway + resource configuration (both the service and the resource configuration are shared via RAM):

> **Note**: this step provisions an Aurora cluster, so the apply takes several minutes longer than the consumer account.

```bash
# Navigate to the provider account directory
cd provider-account

# Configure AWS credentials for the provider account
export AWS_PROFILE=provider-account

# Update variables.tf or create terraform.tfvars with:
# - aws_region = "eu-west-1" (default - change if you want to use another region)

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the resources
terraform apply
```

### Step 2: Consumer Account - Deploy Service Network, VPCs, and Associations

**AWS Account**: Consumer Account

Deploy the service network (owned by the consumer), associate the shared service and resource configuration, and deploy the consumer VPC, EC2 instances, and VPC association:

```bash
# Navigate to the consumer account directory
cd ../consumer-account

# Configure AWS credentials for consumer account
export AWS_PROFILE=consumer-account

# Update variables.tf or create terraform.tfvars with:
# - aws_region = "eu-west-1" (default - change if you want to use another region)

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the resources
terraform apply
```

> **Note**: The consumer EC2 instances are deployed across all the Availability Zones configured for the consumer VPC, and resources are deployed across multiple accounts. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

> **Important**: Delete resources in reverse order to avoid dependency issues.

### Step 1: Consumer Account

```bash
cd consumer-account
export AWS_PROFILE=consumer-account
terraform destroy
```

### Step 2: Provider Account

```bash
cd ../provider-account
export AWS_PROFILE=provider-account
terraform destroy
```

> **Note**: Each account creates its own access-logging CloudWatch Logs log group (`/aws/vpclattice/<identifier>`): the **Consumer Account** owns the service-network-scoped log group and the **Provider Account** owns the service-scoped one. `terraform destroy` in each account removes that account's log group — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default in both accounts, each at the scope it owns:

- **Consumer Account** (owns the service network): an access log subscription at the service-network scope sends logs to `/aws/vpclattice/<identifier>` (7-day retention) in that account.
- **Provider Account** (owns the VPC Lattice service): an access log subscription at the service scope sends logs to `/aws/vpclattice/<identifier>` (7-day retention) in that account.

- **Where to find the logs**: in each account, CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<identifier>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<identifier> --follow
  ```

- **How to interpret them**: each entry records one request (source, target, response code, timing) — useful for observability and, because both the service network and service use `AWS_IAM`/`NONE` auth respectively, for confirming routing and auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). This pattern creates a log group in each account, so the cost applies in both — a small ongoing cost while the pattern is deployed.

## Account-Specific Documentation

For detailed technical documentation about each account's resources:

| Account | Documentation |
|---------|---------------|
| **Provider Account** | [provider-account/README.md](./provider-account/README.md) |
| **Consumer Account** | [consumer-account/README.md](./consumer-account/README.md) |

## Testing

After deploying both accounts, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to a consumer instance and verify cross-account connectivity to the shared service.
