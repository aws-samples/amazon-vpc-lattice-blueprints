# Amazon VPC Lattice - Multi-Account: Centralized Service Network (Terraform)

Terraform implementation of the Centralized Service Network pattern, with one module per account (`provider-account/`, `service-network-account/`, `consumer-account/`). For the architecture, account structure, and connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **Three AWS Accounts**: Network account (central), provider account, and consumer account.
- **AWS Organizations**: All accounts must be part of the same AWS Organization.
- **Terraform**: >= 1.3.0 installed.
- **AWS CLI**: Configured with credentials for each account.
- **Permissions required** (per account):
  - VPC Lattice: Service networks, services, target groups.
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

> **Note**: this step provisions an Aurora cluster, so the apply takes several minutes longer than the other accounts.

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

### Step 2: Network Account - Deploy Service Network

**AWS Account**: Network Account (Central)

Deploy the VPC Lattice service network and associate the shared service:

```bash
# Navigate to the service network account directory
cd ../service-network-account

# Configure AWS credentials for network account
export AWS_PROFILE=network-account

# Update variables.tf or create terraform.tfvars with:
# - aws_region = "eu-west-1" (default - change if you want to use another region)

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the resources
terraform apply
```

### Step 3: Consumer Account - Deploy VPCs and Associations

**AWS Account**: Consumer Account

Deploy consumer VPCs, EC2 instances, and VPC associations:

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

### Step 2: Network Account

```bash
cd ../service-network-account
export AWS_PROFILE=network-account
terraform destroy
```

### Step 3: Provider Account

```bash
cd ../provider-account
export AWS_PROFILE=provider-account
terraform destroy
```

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) is created in the **Network Account** (it owns the service network). `terraform destroy` in that account removes it — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. The **Network Account** owns the service network, so its access log subscription records a log entry for every request that flows through the network and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<identifier>` (7-day retention) in that account.

- **Where to find the logs**: in the Network Account, CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<identifier>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<identifier> --follow
  ```

- **How to interpret them**: each entry records one request through the service network (source, target, response code, timing) — useful for observability and, because the service network uses `AWS_IAM` auth, for confirming auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). For this demo it is a small ongoing cost while the pattern is deployed.

## Account-Specific Documentation

For detailed technical documentation about each account's resources:

| Account | Documentation |
|---------|---------------|
| **Provider Account** | [provider-account/README.md](./provider-account/README.md) |
| **Network Account (Central)** | [service-network-account/README.md](./service-network-account/README.md) |
| **Consumer Account** | [consumer-account/README.md](./consumer-account/README.md) |

## Testing

After deploying all three accounts, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to a consumer instance and verify cross-account connectivity to the shared service.
