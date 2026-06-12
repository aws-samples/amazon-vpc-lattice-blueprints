# Amazon VPC Lattice - Amazon RDS (Aurora) VPC Resource (AWS CloudFormation)

CloudFormation implementation of the RDS / VPC Resources pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **AWS CLI**: Installed and configured with credentials (also used to retrieve the Secrets Manager credentials during testing)
- **Make**: Installed
- **Permissions required**:
  - CloudFormation
  - VPC Lattice: Service networks, resource gateways, resource configurations, associations, access log subscriptions
  - EC2: VPC, subnets, instances, security groups, EC2 Instance Connect endpoint
  - RDS: Aurora clusters and instances, DB subnet groups
  - Secrets Manager: RDS-managed primary user secret
  - CloudWatch Logs: Log groups
  - IAM: Create roles and policies

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the CloudFormation directory
cd patterns/1-simple_architectures/6-rds/cloudformation

# Deploy everything
make deploy

# Or deploy step-by-step:
make deploy-sn        # service network + access logging
make deploy-consumer  # consumer VPC and EC2 instances
make deploy-provider  # provider VPC, Aurora cluster and VPC Lattice resource configuration
```

The `make deploy-consumer` and `make deploy-provider` targets automatically read the `VpcLatticeServiceNetworkId` output from the `vpclattice-rds-networking` stack and pass it to each stack as the `ServiceNetworkId` parameter. The consumer stack is deployed with `--capabilities CAPABILITY_IAM` because it creates an EC2 instance role.

All stacks deploy to `eu-west-1` by default; edit the `--region` value in the `Makefile` to use a different Region.

> **Note**: EC2 instances and the Aurora cluster are deployed across both Availability Zones. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Delete everything
make undeploy
```

> **Note**: The Aurora cluster is created with `DeletionPolicy: Delete` / `UpdateReplacePolicy: Delete`, so no final snapshot is taken on delete and the RDS-managed primary user secret in AWS Secrets Manager is removed with the cluster. The access-logging CloudWatch Logs log group (`/aws/vpclattice/<stack-name>`) is part of the service-network stack and is removed when the stacks are deleted — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the service network records a log entry for every request that flows through it and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<stack-name>` (7-day retention), created as part of the service-network stack.

- **Where to find the logs**: CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<stack-name>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<stack-name> --follow
  ```

- **How to interpret them**: each entry records one request through the service network/service (source, target, response code, timing) — useful for observability and, for auth-enabled services, for confirming auth allow/deny decisions.

> **Cost note**: This pattern runs an Amazon Aurora cluster (instance hours + storage) and uses CloudWatch Logs vended-logs pricing for access logging (ingestion + storage). Both are ongoing costs while the stacks are deployed — tear them down with `make undeploy` when you are done.

## Testing

After successful deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to the consumer instance, resolve the Aurora endpoint (link-local) through VPC Lattice, and connect to Aurora with a MySQL client using the Secrets Manager credentials.
