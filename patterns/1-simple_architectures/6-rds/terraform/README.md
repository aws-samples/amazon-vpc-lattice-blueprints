<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Amazon RDS (Aurora) VPC Resource (Terraform)

Terraform implementation of the RDS / VPC Resources pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **Terraform**: >= 1.3.0 installed
- **AWS CLI**: Configured with credentials (used to retrieve the Secrets Manager credentials during testing)
- **Permissions required**:
  - VPC Lattice: Service networks, resource gateways, resource configurations, associations, access log subscriptions
  - EC2: VPC, subnets, instances, security groups
  - RDS: Aurora clusters and instances, DB subnet groups
  - Secrets Manager: Read the RDS-managed primary user secret
  - CloudWatch Logs: Log groups
  - IAM: Create roles and policies

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/1-simple_architectures/6-rds/terraform

# Initialize Terraform
terraform init

# (Optional) Review the planned changes
terraform plan

# Deploy the resources
terraform apply
```

> **Note**: The Aurora cluster and the consumer/provider VPCs are deployed across all the Availability Zones configured for the VPCs. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability.

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

> **Note**: The Aurora cluster is created with `skip_final_snapshot = true`, so no final snapshot is taken on destroy. The RDS-managed primary user secret in AWS Secrets Manager is removed with the cluster, and the access-logging CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) is managed by this pattern, so `terraform destroy` removes it — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the service network records a log entry for every request that flows through it and sends it to a CloudWatch Logs log group named `/aws/vpclattice/<identifier>` (where `<identifier>` is the `identifier` variable; 7-day retention).

- **Where to find the logs**: CloudWatch Logs console → **Log groups** → `/aws/vpclattice/<identifier>`, or from the CLI:

  ```bash
  aws logs tail /aws/vpclattice/<identifier> --follow
  ```

- **How to interpret them**: each entry records one request through the service network/service (source, target, response code, timing) — useful for observability and, for auth-enabled services, for confirming auth allow/deny decisions.

> **Cost note**: This pattern runs an Amazon Aurora cluster (instance hours + storage) and uses CloudWatch Logs vended-logs pricing for access logging (ingestion + storage). Both are ongoing costs while the pattern is deployed — tear it down with `terraform destroy` when you are done.

## Testing

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to the consumer instance, resolve the Aurora endpoint through VPC Lattice, and connect to Aurora with a MySQL client using the Secrets Manager credentials.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.27.0 |
| <a name="requirement_awscc"></a> [awscc](#requirement\_awscc) | >= 1.67.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.27.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_consumer_instances"></a> [consumer\_instances](#module\_consumer\_instances) | ../../../tf_modules/consumer_instance | n/a |
| <a name="module_consumer_vpc"></a> [consumer\_vpc](#module\_consumer\_vpc) | aws-ia/vpc/aws | = 4.7.3 |
| <a name="module_provider_vpc"></a> [provider\_vpc](#module\_provider\_vpc) | aws-ia/vpc/aws | = 4.7.3 |
| <a name="module_service_network"></a> [service\_network](#module\_service\_network) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_db_subnet_group.aurora_subnet_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_instance_profile.consumer_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.consumer_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.consumer_read_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_rds_cluster.aurora_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.aurora_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.aurora_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.provider_resource_gateway_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.secretsmanager_endpoint_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpclattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.secretsmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_any_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_any_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_db_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_db_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_instances_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.provider_allowing_ingress_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.secretsmanager_endpoint_ingress_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.service_network_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_resource_configuration.resource_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_gateway.resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_vpclattice_service_network_resource_association.resource_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_resource_association) | resource |
| [aws_vpclattice_service_network_vpc_association.vpc_assocation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [aws_iam_policy_document.consumer_instance_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.consumer_read_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_vpc.provider_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aurora_db_configuration"></a> [aurora\_db\_configuration](#input\_aurora\_db\_configuration) | RDS instance configuration. Primary credentials are managed by RDS in AWS Secrets Manager; no password is stored here. | `map(string)` | <pre>{<br/>  "db_name": "mydb",<br/>  "engine": "aurora-mysql",<br/>  "engine_version": "8.0.mysql_aurora.3.12.0",<br/>  "instance_class": "db.t3.medium",<br/>  "username": "admin"<br/>}</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to use in the example. | `string` | `"eu-west-1"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Project identifier. | `string` | `"vpc-resources-rds"` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | Information about the VPCs. | `any` | <pre>{<br/>  "cidr_block": "10.0.0.0/16",<br/>  "endpoints_subnet_netmask": 24,<br/>  "instance_type": "t3.micro",<br/>  "number_azs": 2,<br/>  "private_subnet_netmask": 24<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aurora"></a> [aurora](#output\_aurora) | Aurora cluster endpoints resolved through VPC Lattice from the consumer VPC. |
| <a name="output_consumer_instance_ids"></a> [consumer\_instance\_ids](#output\_consumer\_instance\_ids) | Consumer EC2 instance IDs (use with Session Manager / EC2 Instance Connect). |
| <a name="output_rds_primary_user_secret_arn"></a> [rds\_primary\_user\_secret\_arn](#output\_rds\_primary\_user\_secret\_arn) | ARN of the RDS-managed primary user secret in AWS Secrets Manager (reference only, not the secret value). |
| <a name="output_resource_configuration"></a> [resource\_configuration](#output\_resource\_configuration) | VPC Lattice resource configuration id and ARN (ARN type, targets the Aurora cluster). |
<!-- END_TF_DOCS -->
