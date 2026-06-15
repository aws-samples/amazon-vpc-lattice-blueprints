<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Multi-Account: Centralized Service Network - Service Network Account (Terraform)

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.27.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.50.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_vpclattice_service_network"></a> [vpclattice\_service\_network](#module\_vpclattice\_service\_network) | aws-ia/amazon-vpc-lattice-module/aws | = 1.1.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_vpclattice_access_log_subscription.service_network_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_service_network_resource_association.resource_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_resource_association) | resource |
| [aws_organizations_organization.org](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |
| [aws_ram_resource_share.provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ram_resource_share) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region. | `string` | `"eu-west-1"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Project identifier. | `string` | `"centralized-share"` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
