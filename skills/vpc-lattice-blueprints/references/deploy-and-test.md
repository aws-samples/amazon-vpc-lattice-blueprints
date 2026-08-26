<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# Deploy, test, and tear down

Read this when deploying a pattern, verifying connectivity, cleaning up, or estimating cost.

## Repository layout

```
patterns/<category>/<pattern>/
├── terraform/         # main.tf, variables.tf, outputs.tf, providers.tf, .header.md, README.md (generated)
└── cloudformation/    # *.yaml templates, Makefile, README.md
```

Shared Terraform modules live only in `patterns/tf_modules/`. The one exception to the layout is `patterns/4-auth_policies/`: a **reference toolkit**, not a deployable pattern — `policies/` (copy-paste auth policy snippets) and `signing/` (SigV4/SigV4A signing examples) instead of IaC directories.

## Deploy and tear down

- **Terraform:** set local variables / `identifier` as needed, then `terraform init` → `terraform plan` → `terraform apply`. Tear down with `terraform destroy` (multi-account patterns deploy/destroy per account, in reverse order).
- **CloudFormation:** use the pattern's `Makefile` (`make deploy` / `make undeploy`), or the documented per-account `aws cloudformation` steps for multi-account patterns. Note the Makefiles pin a Region — edit before deploying elsewhere.
- Each pattern's README has the exact deploy, **testing**, and **cleanup** steps.

## Testing connectivity

The typical test: connect to a consumer EC2 instance (via EC2 Instance Connect), resolve the service or resource DNS name, then `curl` the service or connect to the database. Expect a VPC Lattice-managed address back from DNS — an address from `169.254.171.0/24` (link-local) for services, or from `129.224.0.0/17` for VPC resources — that is the overlapping-CIDR benefit in action, since both VPCs use `10.0.0.0/16`.

If a request fails, work through: association states (VPC and service associations `Active`), target health, security groups (targets must allow the **VPC Lattice managed prefix lists**, IPv4 and IPv6, on listener/health-check ports), and — for cross-account patterns — RAM share acceptance. Every pattern enables **access logging** to a CloudWatch Logs group (`/aws/vpclattice/<identifier>`); each entry records client, target, response code, and auth result, which is the fastest way to see how a request was handled. A `403 AccessDeniedException` on an `AWS_IAM` service means the auth policy denied the request or it was unsigned. The repository README's troubleshooting section covers these cases in full.

## Cost and safety

Deploying any pattern provisions **real, billable** resources. VPC Lattice charges can include provisioned service or resource-configuration hours, data processing, and HTTP requests or TLS connections. Patterns can also incur EC2 instance-hours and CloudWatch Logs charges, plus Aurora for the RDS and Multi-AWS Account patterns, and the **EKS** control plane, managed nodes, and a **NAT gateway** (EKS is the most expensive). Patterns are **multi-AZ by default**, which raises cost relative to single-AZ testing. Always recommend a non-production account and running the pattern README's **Cleanup** steps when finished. Teardown removes everything the pattern created, including the access-logging log group.
