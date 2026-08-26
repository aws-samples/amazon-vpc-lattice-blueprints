<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# Architecting with VPC Lattice

Read this when designing an architecture: mapping applications to services and target groups, choosing listeners, segmenting service networks, deciding the consumer boundary, setting the authorization posture, and planning DNS.

## Construct details

Beyond the summary table in `SKILL.md`:

- **Service network** — a service or resource configuration can be associated to **more than one** service network, so you can run multiple networks for segmentation (per environment, tenant, or trust domain). This is also what makes distributed, multi-owner topologies possible.
- **Listener** — protocols are **HTTP, HTTPS, and TLS pass-through**. gRPC is supported through an **HTTPS listener** with the **gRPC target-group protocol version** (INSTANCE and IP targets only; Lambda targets are not supported for gRPC). Listener and target protocols need not match — VPC Lattice manages protocol upgrades/downgrades.
- **VPC resources** — the raw-TCP path has its own constructs:
  - **Resource gateway**: data-path ingress into the *provider* VPC with security groups and selected subnets. A resource gateway can use IPv4, IPv6, or dual-stack addresses; its subnets and the resource must support the selected address type. The repository patterns use dedicated subnets, but the service does not require them.
  - **Resource configuration**: declares the resource behind the gateway. Identified by an **ARN** (AWS-provisioned resources like RDS), a **domain name**, or an **IP**; types are `SINGLE`, `GROUP`, `CHILD`, or `ARN`. The `Name` is capped at 40 characters.
  - **Resource association**: attaches a resource configuration to a service network, optionally with private DNS.
  - A resource configuration is RAM-shareable cross-account; a service-network **auth policy does not apply to it**.
- **Service network VPC endpoint** — a VPC has only one direct association but can connect to **multiple** service networks via endpoints. The endpoint uses IP addresses from its own VPC, not the Lattice-managed association ranges. Traffic arriving over VPC peering, Transit Gateway, Direct Connect, or VPN must be routable to those endpoint addresses.

## Key capabilities to reason about

- **Identity-based access control (auth policies + SigV4).** `AuthType = NONE` is open within the network. `AWS_IAM` applies an IAM resource-based auth policy. An `AWS_IAM` policy can deliberately allow anonymous, unsigned requests. Authorization by IAM identity requires callers to **SigV4- or SigV4A-sign** requests. Requests denied by the effective service-network and service policies receive `403 AccessDeniedException`; passing authorization does not guarantee a `200` response from the target. Policies support condition keys for IAM identity and request attributes such as HTTP method, path, or source VPC. Auth decisions appear in access logs. Auth policies apply to **services**, not VPC resources.
- **Cross-account sharing (AWS RAM).** Share a **service network** (centralized: one account owns/shares it; distributed: each account shares its own), a **service**, or a **resource configuration**. For least privilege, share to specific account IDs or OUs rather than an entire AWS Organization in production.
- **Built-in observability (access logging).** Per-request logs (timestamp, client, path, method, status, processing time, auth result) to CloudWatch Logs, S3, or Data Firehose, at network or service scope — no sidecars.
- **Overlapping CIDRs with direct associations.** Services resolve to Lattice-managed addresses outside either VPC, so directly associated consumer and provider VPCs can have identical CIDRs. This is not possible with ordinary peering, Transit Gateway, or Cloud WAN routing.

## Design workflow

1. **Identify the service(s) and their compute.** Map each logical application to a VPC Lattice **service**, and each backend to a **target group** whose type matches the compute (INSTANCE, IP for ECS/EKS, LAMBDA, ALB) — or a **resource configuration** if it's a raw-TCP resource like RDS. A single service can route to **multiple target groups** via listener rules (by path, header, or method), and those target groups can span different VPCs and target types provided they're in the **same account** as the service. Group backends behind one service when they form one application; use separate services when they are distinct applications.
2. **Define the listener.** HTTP/HTTPS for app services (gRPC via HTTPS + target-group protocol version); TLS pass-through if the app terminates TLS. Use HTTPS + ACM for custom domains.
3. **Place services in a service network.** One network is usually enough for a domain of services; use **multiple** networks when you need segmentation (per environment, tenant, or trust domain). Associate each service to the network (service association).
4. **Decide the consumer boundary.** Single account/VPC → associate the consumer VPC. Multiple accounts → share the network with **RAM** (centralized vs distributed). On-prem or cross-Region consumers → **service network VPC endpoint**. Prefer one service network per VPC — it keeps access control and visibility clean; reach for multiple networks (via endpoints) only with a real segmentation need.
5. **Choose the authorization posture.** Open within the network (`NONE`) for a quick PoC, an anonymous allow policy where intentional, or `AWS_IAM` + a restrictive auth policy + SigV4 for identity-based control. Start least-privilege.
6. **Turn on access logging** at the owning scope from day one.
7. **Plan DNS.** Use the generated FQDN for PoCs. For **VPC resources**, enable **private DNS** on the VPC association/endpoint (preference `VERIFIED_DOMAINS_ONLY` is the most secure; alternatives are `ALL_DOMAINS`, `SPECIFIED_DOMAINS_ONLY`, `VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS`) so the resource resolves automatically from the consumer VPC. For **services with a custom domain**, create the **ALIAS record** yourself pointing at the service's generated FQDN — VPC Lattice does not create it — or automate at scale with the [automated DNS configuration Guidance](https://docs.aws.amazon.com/solutions/amazon-vpc-lattice-automated-dns-configuration-on-aws/).
8. **Evaluate overlap for the chosen access path.** Provider and consumer CIDRs can overlap for direct VPC-association traffic. Clients reaching a service-network VPC endpoint over peering, Transit Gateway, Direct Connect, or VPN still need unambiguous routing to the endpoint VPC.

## Routing consequences to state in every design

- Traffic through a **direct VPC association** needs no customer route-table changes. Consumers resolve to `169.254.171.0/24` for services or `129.224.0.0/17` for VPC resources, and the Lattice data plane intercepts the traffic in-VPC. Consumer and provider VPCs exchange no routes and can use overlapping CIDRs.
- A **service network VPC endpoint** consumes addresses in the endpoint VPC. External clients reaching those addresses use ordinary peering, Transit Gateway, Direct Connect, or VPN routing. Identify every route table involved, preserve return-path symmetry, and ensure the external source and endpoint VPC have non-overlapping address space unless a translation design resolves the conflict.
- **Security groups**: targets must allow the per-Region **VPC Lattice managed prefix lists** (IPv4 and IPv6) on listener and health-check ports; consumers must be able to reach VPC Lattice on the service port.
