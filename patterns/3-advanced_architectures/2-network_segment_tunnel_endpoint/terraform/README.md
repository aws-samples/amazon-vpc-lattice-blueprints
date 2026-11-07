<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Network Segment Access with Tunnel Endpoints (Terraform)

Terraform implementation of the Network Segment Access pattern. For the architecture, what gets deployed, and the connectivity testing steps, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account**: With appropriate IAM permissions
- **Terraform**: >= 1.3.0 installed
- **AWS CLI**: Configured with credentials (used to connect to the consumer instances during testing)
- **Permissions required**:
  - VPC Lattice: Resource gateways, resource configurations, access log subscriptions
  - EC2: VPC, subnets, instances, security groups, VPC endpoints, EC2 Instance Connect endpoint
  - CloudWatch Logs: Log groups

## Deployment

```bash
# Clone the repository
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git

# Navigate to the Terraform directory
cd patterns/3-advanced_architectures/2-network_segment_tunnel_endpoint/terraform

# Initialize Terraform
terraform init

# (Optional) Review the planned changes
terraform plan

# Deploy the resources
terraform apply
```

> **Note**: The VPCs, the segment hosts and the consumer instances are deployed across all the Availability Zones configured for the VPCs. Keep this in mind when testing this environment from a cost perspective - for production environments, we recommend the use of at least 2 AZs for high-availability. Both VPCs must use the same `number_azs`, because the tunnel endpoint has to be in the resource gateway's Availability Zones.

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

> **Note**: The access-logging CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) is managed by this pattern, so `terraform destroy` removes it — no manual cleanup is required.

## Observability: Access logging

This pattern enables VPC Lattice **access logging** by default. An access log subscription on the resource configuration sends a log entry for each connection to the network segment to a CloudWatch Logs log group named `/aws/vpclattice/<identifier>` (where `<identifier>` is the `identifier` variable; 7-day retention).

```bash
aws logs tail /aws/vpclattice/<identifier> --follow
```

> **Cost note**: This pattern runs EC2 instances in both VPCs and a tunnel VPC endpoint (hourly + per GB processed), the resource gateway charges per GB processed, and access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage). Tear it down with `terraform destroy` when you are done.

## Testing

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README. The `consumer_instance_ids` and `segment_host_ips` outputs give you the values the steps need.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.71.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.71.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_consumer_vpc"></a> [consumer\_vpc](#module\_consumer\_vpc) | aws-ia/vpc/aws | = 4.9.0 |
| <a name="module_provider_vpc"></a> [provider\_vpc](#module\_provider\_vpc) | aws-ia/vpc/aws | = 4.9.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.vpclattice_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ec2_instance_connect_endpoint.consumer_eic_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_connect_endpoint) | resource |
| [aws_instance.consumer_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.segment_host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.consumer_eic_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.consumer_instance_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.provider_instance_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.provider_resource_gateway_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.tunnel_endpoint_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.tunnel](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.consumer_egress_any](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.consumer_egress_any_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.consumer_eic_egress_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.provider_allowing_egress_segment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consumer_ingress_eic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consumer_ingress_geneve](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.provider_allowing_ingress_resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.tunnel_endpoint_ingress_geneve](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.resource_configuration_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [aws_vpclattice_resource_configuration.network_segment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_configuration) | resource |
| [aws_vpclattice_resource_gateway.resource_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_resource_gateway) | resource |
| [aws_ami.amazon_linux](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_network_interface.tunnel_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/network_interface) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to build the pattern. | `string` | `"eu-west-1"` | no |
| <a name="input_consumer_vpc"></a> [consumer\_vpc](#input\_consumer\_vpc) | Consumer VPC. | `any` | <pre>{<br/>  "cidr_block": "10.0.0.0/16",<br/>  "endpoints_subnet_netmask": 24,<br/>  "instance_type": "t3.micro",<br/>  "number_azs": 2,<br/>  "workload_subnet_netmask": 24<br/>}</pre> | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Project identifier. | `string` | `"network-segment"` | no |
| <a name="input_provider_vpc"></a> [provider\_vpc](#input\_provider\_vpc) | Provider VPC. | `any` | <pre>{<br/>  "cidr_block": "10.1.0.0/16",<br/>  "instance_type": "t3.micro",<br/>  "number_azs": 2,<br/>  "resourcegateway_subnet_cidrs": [<br/>    "10.1.0.0/24",<br/>    "10.1.1.0/24"<br/>  ],<br/>  "workload_subnet_cidrs": [<br/>    "10.1.2.0/24",<br/>    "10.1.3.0/24"<br/>  ]<br/>}</pre> | no |
| <a name="input_segment_port"></a> [segment\_port](#input\_segment\_port) | TCP port the segment hosts listen on, and the only port the resource configuration shares. | `number` | `80` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_consumer_instance_ids"></a> [consumer\_instance\_ids](#output\_consumer\_instance\_ids) | Consumer EC2 instance IDs (use with EC2 Instance Connect). |
| <a name="output_segment_host_ips"></a> [segment\_host\_ips](#output\_segment\_host\_ips) | Private IPv4 addresses of the web hosts inside the shared network segment. |
<!-- END_TF_DOCS -->
