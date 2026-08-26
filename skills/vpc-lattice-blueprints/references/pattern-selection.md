<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# Pattern selection

Read this when mapping a user's request to catalog patterns, or when one pattern alone doesn't cover the design. The catalog itself is `blueprint.yaml` (resolve it per the *Content resolution* section of `SKILL.md`).

## When to recommend VPC Lattice

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
- **General IP routing between networks** (not just service access) → **VPC peering / AWS Transit Gateway / AWS Cloud WAN**. (These require non-overlapping CIDRs; VPC Lattice does not.)

## Find the right pattern

1. Read `blueprint.yaml` — the canonical catalog of categories, sub-patterns, per-entry IaC support, and `status` (a `coming_soon` entry is deferred; absence of the field means published).
2. Map the user's goal to a pattern using the *Core mental model* in `SKILL.md` and the design workflow in `references/architecting.md`.
3. Open the pattern directory under `patterns/<category>/<pattern>/` and follow its README.

Selection heuristics by request shape:

- **Single account, first Lattice architecture, specific compute type** → *Simple Architectures*; pick the sub-pattern matching the compute (EC2, ASG, Lambda, ECS, EKS) or *RDS / VPC Resources* for a database over raw TCP.
- **Multiple AWS accounts** → *Multi-AWS Account*: **Centralized Service Network** when one networking account owns the service network; **Distributed** when each consumer account owns its own network and associates shared services/resources.
- **Many VPCs each duplicating interface endpoints** → *Advanced Architectures / Centralized VPC Endpoints*.
- **Restricting who can call a service** → overlay *Auth Policies & SigV4* (`patterns/4-auth_policies/`) on whichever pattern was chosen; it is a reference toolkit, not a deployable pattern.

## Composing patterns

The patterns are building blocks, not mutually exclusive products. Typical compositions:

- A **multi-account share** (Centralized or Distributed) *plus* the **Centralized VPC Endpoints** layout.
- An **HTTP service** *and* a **VPC-resource database** reached from the same consumer VPC.
- Any service-exposing pattern *plus* a restrictive **auth policy** from the cookbook.

Start from the closest pattern, then layer in pieces from the others rather than assuming a single directory must cover everything. Never combine a pattern with one that `blueprint.yaml` marks `coming_soon` — recommend only published building blocks.
