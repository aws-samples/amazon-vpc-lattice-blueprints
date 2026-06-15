/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/5-eks/terraform/main.tf ---

# ---------- DATA SOURCES ----------
data "aws_caller_identity" "current" {}

# VPC Lattice managed prefix lists (IPv4 + IPv6), used by the node SG ingress rules below so VPC Lattice can reach the EKS pods (IP-type targets).
data "aws_ec2_managed_prefix_list" "vpclattice_ipv4" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpclattice_ipv6" {
  name = "com.amazonaws.${var.aws_region}.ipv6.vpc-lattice"
}

locals {
  # Workload subnet IDs (EKS nodes + control-plane ENIs).
  workload_subnet_ids = values({
    for k, v in module.provider_vpc.private_subnet_attributes_by_az :
    split("/", k)[1] => v.id if split("/", k)[0] == "workload"
  })

  # Controller install location (the Pod Identity association is scoped to this namespace/service-account pair).
  controller_namespace       = "aws-application-networking-system"
  controller_service_account = "gateway-api-controller"

  # Rendered Kubernetes manifests: the plain YAML files under ../kubernetes, concatenated, with the two non-static values substituted - the ECR image and the Gateway name (which must equal the Terraform service network name).
  rendered_manifest = replace(
    replace(
      join("\n---\n", [for f in ["nodepool", "app", "gateway"] : file("${path.module}/../kubernetes/${f}.yaml")]),
      "{{APP_IMAGE}}", "${aws_ecr_repository.eks_app.repository_url}:latest"
    ),
    "{{SERVICE_NETWORK_NAME}}", module.service_network.service_network.name
  )

  # Gateway API resources only (GatewayClass/Gateway/HTTPRoute). Used on destroy
  rendered_gateway = replace(
    file("${path.module}/../kubernetes/gateway.yaml"),
    "{{SERVICE_NETWORK_NAME}}", module.service_network.service_network.name
  )
}

# ---------- VPC LATTICE SERVICE NETWORK ----------
# Open (allow-all) auth policy.
locals {
  auth_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "*"
        Effect    = "Allow"
        Principal = "*"
        Resource  = "*"
      }
    ]
  })
}

module "service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name        = "service-network-${var.identifier}"
    auth_type   = "AWS_IAM"
    auth_policy = local.auth_policy
  }
}

# ---------- VPC LATTICE ACCESS LOGGING ----------
# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (service network scope - covers all associated services)
resource "aws_vpclattice_access_log_subscription" "service_network_access_logs" {
  resource_identifier = module.service_network.service_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}

# ---------- ECR REPOSITORY ----------
resource "aws_ecr_repository" "eks_app" {
  name                 = "eksapplication"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------- PROVIDER VPC ----------
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "provider-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  subnets = {
    public = {
      netmask                   = var.vpc.public_subnet_netmask
      nat_gateway_configuration = "all_azs"
    }
    workload = {
      netmask                         = var.vpc.private_subnet_netmask
      connect_to_public_natgw         = true
      assign_ipv6_cidr                = true
      assign_ipv6_address_on_creation = true
    }
  }
}

# ---------- EKS CLUSTER ----------
# Cluster IAM role
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "eks-cluster-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# EKS cluster in Auto Mode
resource "aws_eks_cluster" "this" {
  # checkov:skip=CKV_AWS_39:Public API endpoint is required so the operator's local helm provider + kubectl apply can reach the cluster; demo convenience.
  # checkov:skip=CKV_AWS_38:Public endpoint open (0.0.0.0/0) is acceptable for this demo - restrict public_access_cidrs in production.
  # checkov:skip=CKV_AWS_58:Demo cluster stores no sensitive Kubernetes Secrets; KMS envelope encryption omitted for simplicity.
  # checkov:skip=CKV_AWS_37:Control-plane logging omitted to avoid CloudWatch cost in this demo; set enabled_cluster_log_types in production.
  name                          = "eks-cluster-${var.identifier}"
  version                       = var.cluster_version
  role_arn                      = aws_iam_role.cluster.arn
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = local.workload_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Node IAM role (Auto Mode)
data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "eks-node-role-${var.identifier}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Allow the VPC Lattice managed prefix lists (IPv4 + IPv6) inbound on the cluster security group
resource "aws_vpc_security_group_ingress_rule" "nodes_from_vpclattice_ipv4" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "Allow VPC Lattice (IPv4) to reach EKS pods (IP targets)"

  ip_protocol    = "-1"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_vpclattice_ipv6" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "Allow VPC Lattice (IPv6) to reach EKS pods (IP targets)"

  ip_protocol    = "-1"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_ipv6.id
}

# ---------- AWS GATEWAY API CONTROLLER IAM (POD IDENTITY) ----------
data "aws_iam_policy_document" "controller" {
  statement {
    sid    = "VpcLatticeControllerActions"
    effect = "Allow"
    actions = [
      "vpc-lattice:*",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeSecurityGroups",
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:DescribeLogGroups",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "tag:GetResources",
      "firehose:TagDeliveryStream",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "tag:TagResources",
      "tag:UntagResources",
      "acm:ListCertificates",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CreateVpcLatticeServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/vpc-lattice.amazonaws.com/AWSServiceRoleForVpcLattice"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["vpc-lattice.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateLogDeliveryServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/delivery.logs.amazonaws.com/AWSServiceRoleForLogDelivery"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["delivery.logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "controller" {
  name        = "VPCLatticeControllerIAMPolicy-${var.identifier}"
  description = "Permissions for the AWS Gateway API Controller to manage VPC Lattice (recommended upstream policy)."
  policy      = data.aws_iam_policy_document.controller.json
}

# Controller role trust = EKS Pod Identity. The association below binds it to the exact namespace/service-account pair.
data "aws_iam_policy_document" "controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "vpc-lattice-controller-${var.identifier}"
  description        = "Pod Identity role for the AWS Gateway API Controller (VPC Lattice)."
  assume_role_policy = data.aws_iam_policy_document.controller_assume.json
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}

# Pod Identity association: binds the controller IAM role to its Kubernetes ServiceAccount (created by the Helm chart) in its namespace.
resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.controller_namespace
  service_account = local.controller_service_account
  role_arn        = aws_iam_role.controller.arn
}

# ---------- AWS GATEWAY API CONTROLLER (HELM) ----------
resource "helm_release" "gateway_api_controller" {
  name             = "gateway-api-controller"
  repository       = "oci://public.ecr.aws/aws-application-networking-k8s"
  chart            = "aws-gateway-controller-chart"
  version          = "v1.1.0"
  namespace        = local.controller_namespace
  create_namespace = true

  # Auto Mode provisions a node on demand for the controller pod and pulls the image (public ECR, via NAT)
  timeout = 600

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = local.controller_service_account
  }
  set {
    name  = "awsRegion"
    value = var.aws_region
  }
  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }
  set {
    name  = "awsAccountId"
    value = data.aws_caller_identity.current.account_id
  }
  set {
    name  = "clusterVpcId"
    value = module.provider_vpc.vpc_attributes.id
  }
  # Empty: the controller uses the existing Terraform-created service network.
  set {
    name  = "defaultServiceNetwork"
    value = ""
  }
  set {
    name  = "log.level"
    value = "info"
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_pod_identity_association.controller,
    aws_iam_role_policy_attachment.controller,
    aws_vpc_security_group_ingress_rule.nodes_from_vpclattice_ipv4,
    aws_vpc_security_group_ingress_rule.nodes_from_vpclattice_ipv6,
  ]
}

# ---------- GATEWAY API CRDS + GATEWAY/HTTPROUTE + SAMPLE APP ----------
resource "terraform_data" "kubernetes_manifest" {
  input = {
    cluster_name     = aws_eks_cluster.this.name
    region           = var.aws_region
    manifest         = local.rendered_manifest
    gateway_manifest = local.rendered_gateway
    crds_version     = var.gateway_api_crds_version
  }

  triggers_replace = [local.rendered_manifest]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<EOT
set -euo pipefail
aws eks update-kubeconfig --name ${self.input.cluster_name} --region ${self.input.region}
for crd in gatewayclasses gateways httproutes referencegrants grpcroutes; do
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${self.input.crds_version}/config/crd/standard/gateway.networking.k8s.io_$${crd}.yaml"
done
cat <<'MANIFEST' | kubectl apply -f -
${self.input.manifest}
MANIFEST
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<EOT
set -uo pipefail
aws eks update-kubeconfig --name ${self.input.cluster_name} --region ${self.input.region} || true
# Delete only the controller-finalized GatewayClass/Gateway/HTTPRoute
cat <<'MANIFEST' | kubectl delete -f - --ignore-not-found --timeout=300s || true
${self.input.gateway_manifest}
MANIFEST
EOT
  }

  depends_on = [
    helm_release.gateway_api_controller,
    aws_eks_pod_identity_association.controller,
  ]
}

# ---------- CONSUMER VPC AND EC2 INSTANCES ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  vpc_lattice = {
    service_network_identifier = module.service_network.service_network.id
    security_group_ids         = [aws_security_group.vpclattice_sg.id]
  }

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
    }
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

module "consumer_instances" {
  source = "../../../tf_modules/consumer_instance"

  identifier      = var.identifier
  vpc_name        = "consumer-vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# Security Group (VPC Lattice VPC association)
resource "aws_security_group" "vpclattice_sg" {
  name        = "consumer-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_instances_https" {
  security_group_id = aws_security_group.vpclattice_sg.id

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}
