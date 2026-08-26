---
name: vpc-lattice-blueprints
description: Select, explain, and implement deployable Amazon VPC Lattice architectures from the Amazon VPC Lattice Blueprints catalog (CloudFormation and Terraform). Use when a user asks about VPC Lattice service networks, services, target groups, listeners, resource configurations or resource gateways, auth policies or SigV4 signing, service-to-service connectivity across VPCs or AWS accounts, connecting VPCs with overlapping CIDRs, replacing internal load balancers or proxies, reaching a database such as RDS or Aurora over TCP from another VPC or account, comparing VPC Lattice with PrivateLink, ALB, Transit Gateway, or Cloud WAN, or wants a VPC Lattice proof of concept, pattern, or IaC example.
---

<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# Amazon VPC Lattice Blueprints

Reason about **Amazon VPC Lattice** and map user requests to the **complete, tested, deployable patterns** in the Amazon VPC Lattice Blueprints repository. Most patterns ship both **CloudFormation and Terraform** — `blueprint.yaml` declares per-entry support (for example, EKS is Terraform-only, and the auth-policies section is a reference toolkit rather than a deployable pattern). Patterns are PoC / learning / starting-point material, **not** production-ready as-is.

## Fit assessment

This skill also applies to **comparison questions** (VPC Lattice vs PrivateLink, ALB, NLB, Transit Gateway, Cloud WAN) — activate it even when the right answer turns out not to be VPC Lattice. VPC Lattice is **not the default** when the need is: internet-facing load balancing (ALB), ultra-low-latency L4 or static IPs (NLB), one-way single-endpoint exposure with strict provider/consumer separation (PrivateLink alone may be simpler), or general IP routing between networks (VPC peering / Transit Gateway / Cloud WAN — which, unlike VPC Lattice, require non-overlapping CIDRs). Rule of thumb: **ALB for client-to-application inside a VPC; VPC Lattice for secure, observable service-to-service across VPCs and accounts.**

## Operating principles

1. **The manifest is the authority.** `blueprint.yaml` (resolved below) is the source of truth for which patterns exist, their sub-patterns, per-entry IaC support, and `status` (`coming_soon` = deferred; absent = published). Never claim a pattern, template, parameter, or file path exists without checking it. When suggesting an integration or adaptation outside the catalog, label it as such and verify current AWS service support instead of inferring unsupported wiring. If current documentation is unavailable, state the verified catalog result and the verification limitation without suggesting nearest patterns, integrations, workarounds, or design alternatives. You may ask for clarification or request a verified follow-up.
2. **Patterns compose.** They are building blocks, not mutually exclusive products. A real design often combines them (e.g. a multi-account share plus centralized VPC endpoints, or an HTTP service and a VPC-resource database from the same consumer). Start from the closest pattern and layer in pieces from others.
3. **Ask about authentication explicitly.** Every service-exposing pattern ships `AuthType = AWS_IAM` with an **open (allow-all) policy**. It works out of the box but enforces nothing and permits anonymous requests. If the user hasn't said, ask whether they want to restrict access; if so, apply a policy from `patterns/4-auth_policies/policies/` and point at `patterns/4-auth_policies/signing/` for SigV4/SigV4A. Auth policies apply to **services only**, never to VPC resources.
4. **Surface cost and cleanup.** Every pattern provisions real, billable resources. VPC Lattice charges can include provisioned service or resource-configuration hours, data processing, and HTTP requests or TLS connections. Patterns can also provision EC2 and CloudWatch Logs, Aurora for the RDS and multi-account patterns, and an EKS control plane, nodes, and a NAT gateway for the most expensive pattern. Patterns are multi-AZ by default. Recommend a non-production account and the pattern README's Cleanup steps.

## Content resolution

Resolve the catalog and patterns in this order, and **state which source you used**:

1. **Repository checkout available:** inspect only the current working directory and its parents for an `amazon-vpc-lattice-blueprints` checkout containing both `blueprint.yaml` and `patterns/`. Use that checkout's canonical manifest and pattern tree. Do not derive this path from the installed skill directory, recursively search sibling/descendant directories, or choose an unrelated checkout elsewhere on disk.
2. **Standalone install:** if no checkout is available, use this package's bundled `assets/blueprint.yaml` snapshot for pattern selection. Tell the user that deployable templates require cloning https://github.com/aws-samples/amazon-vpc-lattice-blueprints at the manifest source revision recorded in this package's README.
3. **Neither source available:** ask the user to clone the repository or install the full skill package. Do **not** fabricate a pattern, and do not silently fetch content from the network.

## Workflow

1. **Normalize the request.** Establish: topology (service-to-service vs client-to-app), VPC/account boundaries, consumer vs provider sides, protocol (HTTP/HTTPS vs raw TCP), compute type, auth posture, IaC language, single- vs multi-account.
2. **Check fit** using *Fit assessment* above before recommending VPC Lattice.
3. **Select the pattern(s):** read the manifest, filter by scope and IaC support. For ambiguous or composite requests, read `references/pattern-selection.md`.
4. **Design** the target architecture. For the full design workflow (service/target-group mapping, listeners, service-network segmentation, consumer boundary, auth, logging, DNS), read `references/architecting.md`.
5. **Point at the concrete implementation:** the pattern directory under `patterns/<category>/<pattern>/` and its README. For deploy, test, teardown, and cost specifics, read `references/deploy-and-test.md`.
6. **Deliver an output contract:** selected pattern(s) and why they match, prerequisites, the pattern path, deploy steps, how to validate connectivity, auth posture chosen, and cost/cleanup caveats. Always state the **routing consequences**: direct VPC-association traffic needs no customer route-table changes and allows provider/consumer CIDR overlap; service-network VPC endpoints use addresses in the endpoint VPC and require ordinary routes, symmetric return paths, and non-overlapping addressing between external clients and the endpoint VPC unless translation is provided.

## Core mental model

VPC Lattice is a fully managed application networking service for **service-to-service** communication across VPCs and accounts. For direct service-network association traffic, it removes the need to operate load balancers, proxies, sidecars, NAT, or routed connectivity between consumer and provider VPCs. Targets still use VPC subnets and security groups, and service-network VPC endpoints use ordinary VPC routing. The mental shift for directly associated VPCs is to think about **services and who may call them**, rather than routes, CIDRs, and peering. A consumer resolves a service's DNS name to a **VPC Lattice-managed address** that lives in no VPC; the Lattice data plane intercepts and delivers the traffic. The consumer and provider VPCs exchange no routes, so their CIDRs can fully overlap. Every pattern in this repository deliberately uses `10.0.0.0/16` on both sides.

Seven constructs compose almost every design:

| Construct | Role |
|---|---|
| **Service network** | Logical boundary: services + resource configurations + the VPCs allowed to reach them. Auth policy and access logging attach here. RAM-shareable across accounts. |
| **Service** | An exposed application: generated FQDN (or custom domain), listeners + target groups. |
| **Listener** | HTTP, HTTPS, or TLS pass-through. Managed TLS on the generated FQDN; bring ACM for custom domains. gRPC rides an HTTPS listener via the gRPC target-group protocol version. |
| **Target group** | INSTANCE, IP (ECS tasks / EKS pods via the Gateway API Controller), LAMBDA, or ALB. |
| **VPC association** | Connects a consumer VPC to a service network (one direct association per VPC). |
| **VPC resource** (resource gateway + resource configuration) | Raw-TCP path to a native resource (e.g. RDS/Aurora), domain, or IP in another VPC/account. Not governed by auth policies. |
| **Service network VPC endpoint** | PrivateLink endpoint reaching a service network from **outside** the local VPC (peering, TGW, DX, VPN — hybrid and cross-Region access). Uses real VPC IPs. |

## Quick-reference facts

| Fact | Value |
|------|-------|
| Service DNS resolves to | IPv4 `169.254.171.0/24` (link-local), IPv6 `fd00:ec2:80::/64` |
| VPC resource access uses | IPv4 `129.224.0.0/17`, IPv6 `fd00:ec2:80::/64` |
| Consumer & provider VPC CIDR in every pattern | `10.0.0.0/16` (fully overlapping, on purpose) |
| Listener protocols | HTTP, HTTPS, TLS pass-through (gRPC via an HTTPS listener + gRPC target-group protocol version) |
| Target types | INSTANCE, IP (ECS/EKS), LAMBDA, ALB |
| TCP/database backends | resource gateway + resource configuration (VPC resources) |
| Cross-account sharing | AWS RAM (centralized or distributed) |
| Authorization | `AuthType` `NONE` or `AWS_IAM` + auth policy + SigV4/SigV4A; repo default is `AWS_IAM` + open policy |
| Security groups on targets | reference the per-Region **VPC Lattice managed prefix lists** (IPv4 + IPv6), don't hardcode ranges |
| Per-pattern IaC support | declared per entry in `blueprint.yaml` (e.g. EKS is Terraform-only) |

## Read on demand

Load a reference only when its trigger applies — do not read them all:

- **Mapping a request to patterns, or composing several** → `references/pattern-selection.md`
- **Designing an architecture** (the 8-step workflow: services, listeners, segmentation, consumer boundary, auth posture, logging, DNS) → `references/architecting.md`
- **Deploying, testing, tearing down, or estimating cost** (repo layout, Terraform/CloudFormation drivers, connectivity tests, troubleshooting) → `references/deploy-and-test.md`
- **Editing or extending the repository's patterns** (naming, version pins, IaC parity, secure defaults, scan suppressions) → `references/contributing-conventions.md`

## Authoritative references

- VPC Lattice user guide: https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html
- Auth policies: https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html · SigV4: https://docs.aws.amazon.com/vpc-lattice/latest/ug/sigv4-authenticated-requests.html
- VPC resources: https://docs.aws.amazon.com/vpc-lattice/latest/ug/vpc-resources.html · RAM sharing: https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html
- Access logs: https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html
- Repository: `README.md` · `blueprint.yaml` · `CONVENTIONS.md` · `CONTRIBUTING.md`
