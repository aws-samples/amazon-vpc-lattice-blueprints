<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Amazon ECS Target (Terraform)

Terraform implementation of the ECS Fargate pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **Terraform**: >= 1.3.0 installed
- **AWS CLI**: Configured with credentials
- **Docker**: Installed and running on your local machine
- **Permissions required**:
  - VPC Lattice: Service networks, services, target groups
  - EC2: VPC, subnets, security groups, VPC endpoints
  - ECS: Clusters, task definitions, services
  - ECR: Repository management, image push/pull
  - IAM: Create roles and policies
  - CloudWatch: Log groups

## Deployment

### Option 1: Automated Deployment (Recommended)

Use the provided `deploy.sh` script for a streamlined deployment:

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/1-simple_architectures/4-ecs/terraform

# Run the automated deployment script
./deploy.sh
```

The script automatically:

1. Deploys the ECR repository
2. Detects your system architecture (ARM64 or X86\_64)
3. Builds and pushes the Docker image with matching architecture
4. Deploys the remaining infrastructure (VPC, ECS, VPC Lattice)

### Option 2: Step-by-Step Deployment

If you prefer manual control over each step:

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/1-simple_architectures/4-ecs/terraform

# Initialize Terraform
terraform init

# Deploy ECR repository only
terraform apply -target=aws_ecr_repository.ecr_repository

# Get repository URL
export REPOSITORY_URL=$(terraform output -raw repository_url)

# Build and push Docker image
REGION=$(echo $REPOSITORY_URL | cut -d'.' -f4)
AWS_ACCOUNT_ID=$(echo $REPOSITORY_URL | cut -d'.' -f1)
PLATFORM=$(uname -m)

if [ "$PLATFORM" = "arm64" ] || [ "$PLATFORM" = "aarch64" ]; then
    DOCKER_PLATFORM="--platform linux/arm64"
else
    DOCKER_PLATFORM="--platform linux/amd64"
fi

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

cd ../application
docker build ${DOCKER_PLATFORM} -t ${REPOSITORY_URL}:latest .
docker push ${REPOSITORY_URL}:latest
cd ../terraform

# Deploy remaining infrastructure
terraform apply
```

> **Note**: The Terraform configuration automatically detects your system architecture and configures the ECS task definition accordingly. The Docker image must be built for the same architecture. EC2 instances and ECS Fargate will be deployed in all the Availability Zones configured for the VPC. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

> **Note**: The ECR repository is configured with `force_delete = true`, so it will be deleted even if it contains images.

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) is managed by this pattern, so `terraform destroy` removes it — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the service network records a log entry for every request that flows through it and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<identifier>` (where `<identifier>` is the `identifier` variable; 7-day retention).

- **Where to find the logs**: CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<identifier>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<identifier> --follow
  ```

- **How to interpret them**: each entry records one request through the service network/service (source, target, response code, timing) — useful for observability and, for auth-enabled services, for confirming auth allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). For this demo it is a small ongoing cost while the pattern is deployed.

## Testing

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to verify connectivity between consumer instances and ECS tasks through VPC Lattice.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.27.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.27.0 |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.3.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_consumer_instances"></a> [consumer\_instances](#module\_consumer\_instances) | ../../../tf_modules/consumer_instance | n/a |
| <a name="module_consumer_vpc"></a> [consumer\_vpc](#module\_consumer\_vpc) | aws-ia/vpc/aws | = 4.7.3 |
| <a name="module_provider_vpc"></a> [provider\_vpc](#module\_provider\_vpc) | aws-ia/vpc/aws | = 4.7.3 |
| <a name="module_service"></a> [service](#module\_service) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |
| <a name="module_service_network"></a> [service\_network](#module\_service\_network) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | ../../../tf_modules/vpc_endpoints | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_repository.ecr_repository](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecs_cluster.ecs_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.ecs_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.ecs_infrastructure_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_infrastructure_role_policy_attachment_vpclattice](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_role_policy_attachment_vpclattice](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpclattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_any](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_any_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_http_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_http_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_https_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_https_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_instances_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.service_network_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_ec2_managed_prefix_list.vpclattice_pl_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_ec2_managed_prefix_list.vpclattice_pl_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_iam_policy_document.ecs_infrastructure_role_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_task_execution_role_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_task_role_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [external_external.system_architecture](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to use in the example. | `string` | `"eu-west-1"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Project identifier. | `string` | `"ecs-target"` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | Information about the VPCs. | `any` | <pre>{<br/>  "cidr_block": "10.0.0.0/16",<br/>  "endpoints_subnet_netmask": 24,<br/>  "instance_type": "t3.micro",<br/>  "number_azs": 2,<br/>  "private_subnet_netmask": 24<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_consumer_instance_ids"></a> [consumer\_instance\_ids](#output\_consumer\_instance\_ids) | Consumer EC2 Instance IDs |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | Amazon ECR repository URL. |
| <a name="output_vpclattice_service_domain_name"></a> [vpclattice\_service\_domain\_name](#output\_vpclattice\_service\_domain\_name) | VPC Lattice service domain name. |
<!-- END_TF_DOCS -->
