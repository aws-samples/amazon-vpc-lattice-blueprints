<!-- BEGIN_TF_DOCS -->
# Amazon VPC Lattice - Amazon EKS Target (Terraform)

Terraform implementation of the EKS pattern. For the architecture, what gets deployed, the Gateway API → VPC Lattice mapping, and connectivity testing, see the [pattern README](../README.md).

## Prerequisites

- **AWS Account** with appropriate IAM permissions
- **Terraform** >= 1.4.0 (uses the `terraform_data` resource)
- **AWS CLI** configured (used for `aws eks get-token` exec auth, the image build/push in `deploy.sh`, and `aws eks update-kubeconfig` during testing)
- **kubectl** (the apply-time provisioner installs the Gateway API CRDs and applies the manifest; also used during testing)
- **Docker** (used by `deploy.sh` to build/push the sample app image)
- **Permissions required**:
  - VPC Lattice: Service networks, services, target groups
  - EC2: VPC, subnets, security groups, VPC endpoints
  - EKS: Auto Mode clusters, Pod Identity associations
  - ECR: Repository management, image push/pull
  - IAM: Create roles and policies
  - CloudWatch: Log groups

## Deployment

Deploy with `deploy.sh`. The sample app pulls its image from ECR, so the image must exist before the workload manifest is applied. `deploy.sh` creates the ECR repository first (`terraform apply -target=aws_ecr_repository.eks_app`), builds and pushes the `linux/arm64` image (for the Graviton nodes), then runs a full `terraform apply` for the rest — the Auto Mode cluster, controller, Graviton NodePool, and Gateway API manifest (whose apply/teardown stay Terraform-managed):

```bash
git clone https://github.com/aws-samples/amazon-vpc-lattice-blueprints.git
cd amazon-vpc-lattice-blueprints/patterns/1-simple_architectures/5-eks/terraform
./deploy.sh
```

> **Note**: Requires Docker (the build runs `docker build --platform linux/arm64`). A bare `terraform apply` without first pushing the image leaves the app pods in `ImagePullBackOff`. The pattern deploys an EKS Auto Mode cluster with NAT gateway access.

## Cleanup

Tear down when finished to stop ongoing costs (Auto Mode control plane + compute, the NAT gateways (hourly + data processing), the consumer instance, and CloudWatch access-log ingestion). From this `terraform/` directory:

```bash
terraform destroy
```

Terraform tears down in the right order automatically: the `terraform_data` manifest `depends_on` the controller, so on destroy it deletes the `GatewayClass`/`Gateway`/`HTTPRoute` first — letting the controller remove the VPC Lattice service + target group it created — before the controller, cluster, and VPCs. The destroy step deletes only those Gateway API objects (not the app/NodePool, which go away with the cluster) and uses a **bounded `--timeout`**, so it cannot hang indefinitely on stuck finalizers.

> **⚠️ Verify afterwards.** The controller deletes asynchronously. In the rare case it is unavailable during teardown (e.g. its node is replaced and cannot pull the controller image), the bounded delete times out and can leave an orphaned VPC Lattice service/target group (a leftover association can also block the service network + consumer VPC). Confirm the service (`sample-service`) and its target group are gone; if not, delete the service-network association → service → target group, clear any stuck `Gateway`/`HTTPRoute` finalizers (`kubectl patch ... -p '{"metadata":{"finalizers":[]}}' --type=merge`), and re-run `terraform destroy`.

> **Service-linked role.** `AWSServiceRoleForVpcLattice` is not managed here (an account-global singleton, auto-created on first use) and is left in place; remove it only if no other VPC Lattice resources remain.

## Observability: Access logging

Access logging is enabled by default: an access log subscription on the service network sends a log entry for every request to a CloudWatch Logs log group `/aws/vpclattice/<identifier>` (7-day retention).

```bash
aws logs tail /aws/vpclattice/<identifier> --follow
```

Each entry records one request (source, target, response code, timing) — useful for observability and, for auth-enabled services, confirming allow/deny decisions.

> **Cost note**: Access logging uses CloudWatch Logs vended-logs pricing (ingestion + storage) — a small ongoing cost while deployed.

## Testing

After deployment, follow the [Testing Connectivity](../README.md#testing-connectivity) steps in the pattern README to connect to the consumer instance, read the controller-assigned Lattice service DNS name, resolve it (link-local) through VPC Lattice, and `curl` the EKS-backed Flask service over HTTPS.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.27.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.17 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.27.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 2.17 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

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
| [aws_ecr_repository.eks_app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.vpclattice_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.allowing_ingress_instances_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nodes_from_vpclattice_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nodes_from_vpclattice_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpclattice_access_log_subscription.service_network_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_access_log_subscription) | resource |
| [helm_release.gateway_api_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [terraform_data.kubernetes_manifest](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ec2_managed_prefix_list.vpclattice_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_ec2_managed_prefix_list.vpclattice_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_iam_policy_document.cluster_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controller_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region to use in the example. | `string` | `"eu-west-1"` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version for the EKS cluster. | `string` | `"1.35"` | no |
| <a name="input_gateway_api_crds_version"></a> [gateway\_api\_crds\_version](#input\_gateway\_api\_crds\_version) | Upstream Kubernetes Gateway API standard CRD bundle version to install (gateway.networking.k8s.io). | `string` | `"v1.1.0"` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Project identifier. | `string` | `"eks"` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | Information about the VPCs. | `any` | <pre>{<br/>  "cidr_block": "10.0.0.0/16",<br/>  "endpoints_subnet_netmask": 24,<br/>  "instance_type": "t3.micro",<br/>  "number_azs": 2,<br/>  "private_subnet_netmask": 24,<br/>  "public_subnet_netmask": 28<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Amazon EKS cluster name. |
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Command to update your kubeconfig for kubectl access to the EKS cluster. |
| <a name="output_consumer_instance_ids"></a> [consumer\_instance\_ids](#output\_consumer\_instance\_ids) | Consumer EC2 instance IDs (use with EC2 Instance Connect to curl the EKS-backed service through VPC Lattice). |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | Amazon ECR repository URL. |
<!-- END_TF_DOCS -->
