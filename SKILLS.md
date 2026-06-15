<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# VPC Lattice Skill

> **Purpose.** This file is written for an **AI agent**, not (primarily) for a human. Drop it into your agent's context (as a system/skill file, a retrieved document, or pasted reference) so the agent can (1) reason correctly about **Amazon VPC Lattice** and (2) use the **Amazon VPC Lattice Blueprints** repository to build proof-of-concepts and architect real use cases. The human-facing overview lives in [`README.md`](./README.md); the machine-readable pattern catalog lives in [`blueprint.yaml`](./blueprint.yaml).

## How to use this skill

When a user asks about service-to-service connectivity on AWS, secure cross-VPC or cross-account communication, replacing internal load balancers/proxies, or building a VPC Lattice PoC:

1. **Ground your mental model** in *What VPC Lattice is* and *Core building blocks* below.
2. **Check fit** using *When to use VPC Lattice* before recommending it, in case the service is not the right tool.
3. **Design** with *How to architect with VPC Lattice*.
4. **Map the design to a concrete, deployable example** using *How to use this blueprint*. First read [`blueprint.yaml`](./blueprint.yaml) for the current list of patterns, then send the user to the matching `patterns/<category>/<pattern>/` directory.
5. **Compose patterns when one isn't enough.** The patterns are building blocks, not mutually exclusive products. A real design often combines them — e.g. a multi-account share *plus* a centralized-VPC-endpoints layout, or an HTTP service *and* a VPC-resource (database) reached from the same consumer. Start from the closest pattern, then layer in pieces from the others rather than assuming a single directory must cover everything.
6. **Consider authentication explicitly.** Every service-exposing pattern ships `AuthType = AWS_IAM` with an open (allow-all) policy, so it works out of the box but enforces nothing. If the user hasn't said, **ask whether they want to restrict access** — and if so, apply a restrictive policy from [`patterns/4-auth_policies/`](./patterns/4-auth_policies/) (cookbook in `policies/`, SigV4/SigV4A signing in `signing/`) on top of whichever pattern they chose. (Auth policies apply to services, not to VPC resources.)

Treat [`blueprint.yaml`](./blueprint.yaml) as the **source of truth for what exists** (which patterns are published, which IaC each supports, what is deferred). Do not assume a pattern exists from this prose alone, confirm against the manifest and the `patterns/` tree.

---

## What VPC Lattice is

Amazon VPC Lattice is a **fully managed application networking service** that connects, secures, and monitors **service-to-service** communication across VPCs and AWS accounts, without you running load balancers, proxies, sidecars, or NAT, and without any IP-level connectivity.

The key mental shift: with VPC Lattice you stop thinking about **network reachability** (routes, CIDRs, peering) and start thinking about **services and who may call them**. VPC Lattice brokers the traffic. A consumer resolves a service's DNS name to a **link-local address** (IPv4 `169.254.171.x/24`, IPv6 `fd00:ec2:80::/64`) and VPC Lattice handles getting the request to a healthy target, applying authorization and logging along the way. Because the address a consumer talks to is link-local (not an address inside either VPC), **the consumer and provider VPCs never exchange routes and their CIDRs can fully overlap.**

VPC Lattice isn't only for HTTP services. It also brokers **raw TCP** to **VPC resources** — native AWS resources (such as an **Amazon RDS / Aurora** database), domain names, or IP addresses living in another VPC or account. A **resource gateway** provides the data-path ingress into the resource's VPC and a **resource configuration** declares the resource; consumers reach it through the same service network. Reaching a VPC resource uses VPC Lattice-managed addresses from the **`129.224.0.x/17`** range (the addresses the VPC association uses for resource access) rather than the link-local services range, and — unlike a service — a VPC resource is **not** governed by the service network's auth policy.

---

## Core building blocks

Learn these seven constructs; almost every VPC Lattice design is a composition of them.

- **Service network** — the top-level logical boundary. A collection of services plus the VPCs (and accounts) allowed to reach them. Access control (auth policy) and observability (access logs) attach here at the network scope. Shareable across accounts via AWS RAM. A given **service or resource configuration can be associated to more than one service network**, so you can run **multiple service networks for segmentation** (per environment, tenant, or trust domain) — which is also what makes distributed, multi-owner topologies possible.
- **Service** — an application/microservice you expose. It gets a Lattice-generated DNS name (or a custom domain name) and contains listeners + target groups. A service is made reachable by a **service association** to a service network.
- **Listener** — how a service accepts requests. Protocols: **HTTP, HTTPS, gRPC, and TLS pass-through**. For HTTPS on the generated FQDN, Lattice manages the TLS certificate; for a custom domain you bring an ACM certificate. Listener and target protocols need not match.
- **Target group** — where a listener routes traffic. Target types:
  - **INSTANCE** — EC2 instances by instance ID (also how Auto Scaling groups register).
  - **IP** — IP targets inside a VPC CIDR; this is how **ECS tasks** and **EKS pods** are reached (EKS via the AWS Gateway API Controller). Cannot be VPC endpoints or publicly routable IPs.
  - **LAMBDA** — a function as a serverless target.
  - **ALB** — front an existing Application Load Balancer.
- **VPC association** — associates a *consumer* VPC with a service network so workloads in that VPC can call the network's services. VPC Lattice provisions the needed data-path infrastructure; scope is limited to that VPC. A VPC can have **only one** direct service-network association (a service network VPC endpoint can attach it to additional networks).
- **VPC resources (resource gateway + resource configuration)** — the **raw TCP** path, for backends that aren't HTTP services (e.g. an **Amazon RDS / Aurora** database). It has its own constructs:
  - **Resource gateway** — the dual-stack data-path ingress into the *provider* VPC that fronts the resource; it has security groups and lives in dedicated subnets.
  - **Resource configuration** — declares the resource behind the gateway. Identified by an **ARN** (AWS-provisioned resources like RDS), a **domain name**, or an **IP** (IPv4/IPv6 in the VPC); types are `SINGLE`, `GROUP`, `CHILD`, or `ARN`. The `Name` is capped at 40 characters (hence the `resource-config-…` naming).
  - **Resource association** — attaches a resource configuration to a service network (the resource-side equivalent of a service association), optionally with private DNS so the resource's endpoint resolves from consumer VPCs.
  - Reaching a VPC resource uses VPC Lattice-managed addresses from the **`129.224.0.x/17`** range — the addresses the VPC association uses for resource access — as opposed to the link-local **`169.254.171.x/24`** range used for services (IPv6 `fd00:ec2:80::/64` for both). A resource configuration is shareable cross-account via **AWS RAM**, and a service-network **auth policy does not apply to it** (auth policies govern services only).
- **Service network VPC endpoint** — a VPC endpoint of type *service network*, powered by **AWS PrivateLink**, that connects a VPC to a service network. It is how clients reach a service network's services and resource configurations from **outside the local VPC**: traffic arriving over **VPC peering, AWS Transit Gateway, AWS Direct Connect, or VPN** (i.e. **on-premises**, **cross-Region**, or other routable networks) can use it. Differences from a direct VPC association: a VPC has only one direct association but can connect to **multiple** service networks via endpoints, and the endpoint uses **IP addresses from the VPC** to establish connectivity (not the link-local managed prefix list). Private DNS can be enabled on the endpoint. This is the recommended building block for hybrid and cross-Region access.

DNS resolution differs for resources vs services:

- **VPC resources** — enabling **private DNS** on the **VPC association** or the **service network VPC endpoint** lets VPC Lattice automatically provision a Route 53 private hosted zone in the connecting VPC, so the resource's (custom) domain name resolves **automatically** from that VPC. Consumers control which domains this applies to via **DNS preferences**: `VERIFIED_DOMAINS_ONLY` (recommended, most secure), `ALL_DOMAINS`, `SPECIFIED_DOMAINS_ONLY`, or `VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS`.
- **VPC Lattice services** — a service always gets a generated FQDN (resolvable from associated VPCs with no extra work). If you front it with a **custom domain name**, **you** must create the **ALIAS (A/AAAA) record** in your own DNS (e.g. a Route 53 private hosted zone) pointing at the service's generated domain name — VPC Lattice does not create it for you. To automate this at scale, use the [Amazon VPC Lattice automated DNS configuration on AWS](https://docs.aws.amazon.com/solutions/amazon-vpc-lattice-automated-dns-configuration-on-aws/) Guidance.

---

## When to use VPC Lattice

Recommend VPC Lattice when **most** of these are true:

- Traffic is **service-to-service** (east-west), not internet-facing client traffic.
- It must cross **VPC or account boundaries**, and you'd rather not manage peering / transit gateway / PrivateLink plumbing or reconcile CIDRs.
- You want **identity-based authorization** (IAM/SigV4) instead of, or in addition to, network-location controls (security groups/CIDRs).
- You want **per-request access logging** built in, with no sidecars.
- You're connecting **heterogeneous compute** (EC2, ASG, Lambda, ECS, EKS, ALB, or a TCP resource like RDS) behind one consistent model.

Prefer a different tool when:

- **Internet-facing or in-VPC application load balancing** → **ALB** (client-to-app within a VPC). VPC Lattice is not an internet-facing entry point.
- **Ultra-low-latency L4 / extreme throughput, static IPs, non-HTTP protocols at scale** → **NLB**.
- **One-way exposure of a single endpoint to another VPC/account with strict provider/consumer separation** → **PrivateLink** may be simpler than a full service network.
- **You need general IP routing between networks** (not just service access) → **VPC peering / AWS Transit Gateway / AWS Cloud WAN**. (But note these require non-overlapping CIDRs; VPC Lattice does not.)

Rule of thumb: **ALB for client-to-application inside a VPC; VPC Lattice for secure, observable service-to-service across VPCs and accounts.**

---

## Key capabilities to reason about

- **Identity-based access control (auth policies + SigV4).** A service or service network can be `AuthType = NONE` (open within the network) or `AWS_IAM` (guarded by an **auth policy** — an IAM resource-based policy). With `AWS_IAM`, a policy that authorizes by IAM identity requires callers to **SigV4- (or SigV4A-) sign** requests; an allowed principal gets `200`, an unsigned or non-allowed caller gets `403 AccessDeniedException`. Auth policies attach at **service-network** and/or **service** scope and support condition keys (IAM identity *and* request attributes such as HTTP method/path or source VPC). Auth decisions appear in access logs. Note: an auth policy applies to **services**, not to VPC resources (resource configurations).
- **Cross-account sharing (AWS RAM).** Share a **service network** (centralized model: one account owns/shares the network, others associate VPCs and publish services) or have each account share **its own** network (distributed model). A service and a **resource configuration** can also be shared via RAM. For least privilege, share to specific account IDs or organizational units (OUs) rather than an entire AWS Organization in production.
- **Built-in observability (access logging).** Per-request logs (timestamp, client, path, method, status, processing time, auth result, headers) to **CloudWatch Logs**, **S3**, or **Data Firehose**, at network or service scope — no sidecars.
- **Overlapping CIDRs with no peering.** Because services resolve to link-local addresses, consumer and provider VPCs can have **identical CIDRs**. This is impossible with peering, AWS transit gateways, or AWS Cloud WAN.
- **Heterogeneous targets behind one model** — see target types above.

---

## How to architect with VPC Lattice

A repeatable design workflow:

1. **Identify the service(s) and their compute.** Map each **logical application** to a VPC Lattice **service**, and each backend to a **target group** whose type matches the compute (INSTANCE, IP for ECS/EKS, LAMBDA, ALB) — or a **resource configuration** if it's a raw-TCP resource like RDS. A service is **not** limited to one backend: a single service can route to **multiple target groups** via listener rules (by path, header, or method), and those target groups can span **different VPCs and different target types** provided they're in the **same account** as the service. Group backends behind one service when they form one application; use separate services when they are distinct applications.
2. **Define the listener.** HTTP/HTTPS/gRPC for app services; TLS pass-through if the app terminates TLS. Use HTTPS + ACM for custom domains.
3. **Place services in a service network.** One network is usually enough for a domain of services; use **multiple** networks when you need segmentation (per environment, tenant, or trust domain), since a service or resource configuration can be associated to more than one. Associate each service to the network (service association).
4. **Decide the consumer boundary.** Single account/VPC → associate the consumer VPC. Multiple accounts → share the network with **RAM** (centralized vs distributed). On-prem or cross-Region consumers → **service network VPC endpoint**. **Prefer one service network per VPC** — it keeps access control and visibility clean; reach for multiple networks (via endpoints) only when you have a real segmentation need.
5. **Choose the authorization posture.** Open within the network (`NONE`) for a quick PoC, or `AWS_IAM` + auth policy + SigV4 for identity-based control. Start least-privilege.
6. **Turn on access logging** at the owning scope from day one.
7. **Plan DNS.** Use the generated FQDN for PoCs. For **VPC resources**, enable **private DNS** on the VPC association/endpoint (preference `VERIFIED_DOMAINS_ONLY`) so the resource resolves automatically from the consumer VPC. For **services with a custom domain**, create the **ALIAS record** yourself pointing at the service's generated FQDN — or automate it at scale with the [automated DNS configuration Guidance](https://docs.aws.amazon.com/solutions/amazon-vpc-lattice-automated-dns-configuration-on-aws/).
8. **Ignore CIDR overlap as a blocker** — it isn't one. Don't design peering/TGW around Lattice service traffic.

---

## How to use this blueprint (Amazon VPC Lattice Blueprints)

This repository is a library of **complete, tested, deployable** VPC Lattice patterns in **both CloudFormation and Terraform**, meant as PoC / learning / starting-point material — **not** to be consumed as-is in production.

### Find the right pattern

1. Read [`blueprint.yaml`](./blueprint.yaml) — the canonical catalog of categories, sub-patterns, IaC support, and `status` (a `coming_soon` entry is deferred; absence of the field means published).
2. Map the user's goal to a pattern using the **Core building blocks** and **How to architect** sections above, plus the **Patterns** table in [`README.md`](./README.md) and the catalog in [`blueprint.yaml`](./blueprint.yaml).
3. Open the pattern directory under `patterns/` and follow its README.

### Repository layout

```
patterns/<category>/<pattern>/
├── terraform/         # main.tf, variables.tf, outputs.tf, providers.tf, .header.md, README.md (generated)
└── cloudformation/    # *.yaml templates, Makefile, README.md
```

Shared Terraform modules live only in `patterns/tf_modules/`. The Terraform `README.md` is **generated** by terraform-docs from `.header.md` — never hand-edit it.

The one exception to the layout is the **Auth Policies & SigV4** section (`patterns/4-auth_policies/`): it is a **reference toolkit**, not a deployable pattern, so it has no `terraform/` or `cloudformation/` directory. Instead it contains `policies/` (copy-paste auth policy snippets, one per use case) and `signing/` (how to SigV4/SigV4A-sign requests, with code examples).

### Deploy and tear down

- **Terraform:** set local variables / `identifier` as needed, then `terraform init` → `terraform plan` → `terraform apply`. Tear down with `terraform destroy` (multi-account patterns deploy/destroy per account, in reverse order).
- **CloudFormation:** use the pattern's `Makefile` (`make deploy` / `make undeploy`), or the documented per-account `aws cloudformation` steps for multi-account patterns.
- Each pattern's README has the exact deploy, **testing**, and **cleanup** steps. The typical test: connect to a consumer EC2 instance (via EC2 Instance Connect), resolve the service/resource DNS name (a VPC Lattice-managed address — `169.254.171.x` link-local for services, `129.224.0.x` for VPC resources — the overlapping-CIDR benefit in action), then `curl` the service or connect to the database.

### Conventions an agent should respect when editing or extending patterns

- **IaC parity:** every published deployable pattern ships **both** CloudFormation and Terraform — **except EKS, which is Terraform-only** (Helm + Kubernetes Gateway API CRDs can't be represented cleanly in pure CloudFormation). The "IaC Support" column / [`blueprint.yaml`](./blueprint.yaml) is the source of truth; never claim an implementation that doesn't exist.
- **Naming:** `"<role>-<thing>-${var.identifier}"`, hyphens not underscores, identifier suffix last (SGs: `"<vpc>-<purpose>-security-group-${var.identifier}"`).
- **Version pins** (uniform across patterns): module `aws-ia/vpc/aws = 4.7.3`, `aws-ia/amazon-vpc-lattice-module/aws = 1.1.0` (exact `=`); providers `hashicorp/aws >= 6.27.0`, `hashicorp/awscc >= 1.67.0` (floor `>=`); Lambda runtime `python3.14`; Terraform core `>= 1.3.0`.
- **License header:** MIT-0 header at the top of every IaC source file.
- **Access logging on by default:** service network/service patterns create a CloudWatch Logs group `/aws/vpclattice/<identifier>`, destroyed on teardown.
- **DNS facts:** VPC Lattice **services** resolve to IPv4 `169.254.171.x/24` (link-local); **VPC resources** (resource gateway, e.g. RDS) are reached via the `129.224.0.x/17` range; IPv6 is `fd00:ec2:80::/64` for both.
- **Auth default:** every service-exposing pattern ships its service network and service with `AuthType = AWS_IAM` and a **completely open** (allow-all, including anonymous) auth policy, so behaviour is unchanged out of the box but the pattern is "auth-ready" — swap in a restrictive policy from `patterns/4-auth_policies/policies/` to enforce access control. The resource-only patterns (RDS / VPC Resources and Centralized VPC Endpoints) keep `NONE`, since auth policies do not apply to VPC resources.
- **Secure defaults stay on:** IMDSv2 required, encrypted EBS root volumes, HTTPS listeners, RDS managed master password in Secrets Manager. Don't weaken these.
- **Security-scan suppressions** (Checkov) require a justification (`.checkov.yaml` `skip-check` with a comment, or inline `#checkov:skip=...:reason`). Suppress only deliberate demo simplifications or confirmed false positives.

See [`CONVENTIONS.md`](./CONVENTIONS.md) for the authoritative contract and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for tooling/versions.

### Cost & safety reminder to surface to users

Deploying any pattern provisions **real, billable** resources (VPC Lattice per-request + hourly, EC2 instance-hours, access-logging CloudWatch Logs, plus Aurora for the RDS and Multi-AWS Account patterns, and the **EKS** control plane + managed nodes + a **NAT gateway** — EKS is the most expensive). Patterns are **multi-AZ by default**. Always recommend a non-production account and running the README **Cleanup** steps when finished.

---

## Quick-reference facts

| Fact | Value |
|------|-------|
| Service DNS resolves to | IPv4 `169.254.171.x/24` (link-local), IPv6 `fd00:ec2:80::/64` |
| VPC resource access uses (VPC association range) | IPv4 `129.224.0.x/17`, IPv6 `fd00:ec2:80::/64` |
| Consumer & provider VPC CIDR in every pattern | `10.0.0.0/16` (fully overlapping, on purpose) |
| Listener protocols | HTTP, HTTPS, gRPC, TLS pass-through |
| Target types | INSTANCE, IP (ECS/EKS), LAMBDA, ALB |
| TCP/database backends | resource gateway + resource configuration (VPC resources) |
| Cross-account sharing | AWS RAM (centralized or distributed) |
| Authorization | `AuthType` `NONE` or `AWS_IAM` + auth policy + SigV4/SigV4A; repo default is `AWS_IAM` + open policy for service-exposing patterns |
| EKS IaC | Terraform-only |

## Authoritative references

- VPC Lattice user guide: https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html
- Auth policies: https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html
- SigV4-signed requests: https://docs.aws.amazon.com/vpc-lattice/latest/ug/sigv4-authenticated-requests.html
- VPC resources: https://docs.aws.amazon.com/vpc-lattice/latest/ug/vpc-resources.html
- Cross-account sharing (RAM): https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html
- Automated DNS configuration (Guidance): https://docs.aws.amazon.com/solutions/amazon-vpc-lattice-automated-dns-configuration-on-aws/
- Access logs: https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html
- AWS Gateway API Controller (EKS): https://www.gateway-api-controller.eks.aws.dev/latest/
- This repo: [`README.md`](./README.md) · [`blueprint.yaml`](./blueprint.yaml) · [`CONVENTIONS.md`](./CONVENTIONS.md)
