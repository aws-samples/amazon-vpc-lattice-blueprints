# Amazon VPC Lattice Blueprints

Welcome to Amazon VPC Lattice Blueprints!

This project contains a collection of Amazon VPC Lattice patterns implemented in [AWS CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) and [Terraform](https://developer.hashicorp.com/terraform) that demonstrate how to configure and deploy application networking using [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/).

> [!TIP]
> **Building with an AI agent?** Install the [agent skill package](./skills/vpc-lattice-blueprints/): copy `skills/vpc-lattice-blueprints/` into your runtime's skills directory (for example `~/.kiro/skills/` or `~/.claude/skills/` — see the [package README](./skills/vpc-lattice-blueprints/README.md)). It teaches the agent how to reason about VPC Lattice and how to use these blueprints to design and deploy real architectures — grounded in this repository's conventions. The legacy single-file [`SKILLS.md`](./SKILLS.md) still works as pasted context but is deprecated in favor of the package.

## Motivation

Amazon VPC Lattice simplifies service-to-service communication by providing a fully managed application networking service that connects, secures, and monitors services across multiple accounts and VPCs. While VPC Lattice eliminates the need to manage load balancers, proxies, or complex networking configurations, understanding all the service's capabilities can be overwhelming, especially when designing production-grade architectures.

AWS customers have asked for practical examples and best practices that demonstrate how to leverage VPC Lattice's full potential. These blueprints provide real-world use cases with complete, tested implementations that teams can use for:

- **Proof of Concepts (PoCs)**: Quickly validate VPC Lattice capabilities in your environment.
- **Testing and learning**: Understand how different features work together through hands-on examples.
- **Starting point**: Use as a foundation for your application networking configurations.
- **Best practices**: Learn recommended patterns for common service-to-service communication scenarios.

With VPC Lattice Blueprints, customers can configure and deploy service-to-service architectures at scale in days, rather than spending weeks or months figuring out the optimal configuration.

## Why VPC Lattice?

### Why VPC Lattice over load balancers?

VPC Lattice and load balancers solve different problems. An Application Load Balancer is built for **client-to-application** traffic and lives inside a single VPC: you provision it, manage its listeners and target groups, and wire up your own connectivity (peering, transit gateways, PrivateLink) whenever traffic needs to cross a VPC or account boundary. VPC Lattice is built for **service-to-service** connectivity *across* VPCs and accounts, and it is fully managed (there are no load balancers or proxies for you to run). On top of that connectivity it adds the capabilities you would otherwise have to assemble yourself:

- **Connectivity without infrastructure to manage**: connect services across VPCs and accounts without standing up and operating load balancers, proxies, or NAT.
- **Identity-based access control**: gate every service with [auth policies](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html) and SigV4 request signing, so authorization is based on IAM identity rather than network location. See the [Auth Policies & SigV4 toolkit](./patterns/4-auth_policies/).
- **Built-in observability**: [access logging](https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html) for every request (client, path, status, auth result) with no sidecars to deploy.
- **Cross-account sharing**: share a service network across accounts with [AWS Resource Access Manager (RAM)](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html) for centralized or distributed governance. See the [Multi-AWS Account pattern](./patterns/2-multi_account/).

In short: reach for an ALB when you need internet-facing or VPC-internal application load balancing; reach for VPC Lattice when you need a secure, observable service mesh that spans VPCs and accounts.

### Connect services across VPCs with overlapping CIDRs — no peering required

VPC Lattice connects services across VPCs **without** VPC peering, AWS transit gateways, AWS Cloud WAN, or any CIDR coordination. Traffic is brokered by VPC Lattice over managed addresses that don't live inside either VPC — **VPC Lattice services** use [link-local addresses](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html) (the `169.254.171.x/24` range), while **VPC resources** (e.g. a database reached over TCP) use the `129.224.0.x/17` range; IPv6 is `fd00:ec2:80::/64` for both. Because these aren't addresses inside either VPC, the consumer and provider VPCs never exchange routes and their address spaces never have to be reconciled.

To make this concrete, **every pattern in this repository intentionally uses `10.0.0.0/16` for both the consumer and the provider VPC.** The two VPCs have *identical, fully overlapping* CIDRs, and connectivity still works, because a service or resource is reached through a VPC Lattice-managed address rather than an address inside either VPC. When you run a pattern's testing steps and see a `169.254.171.x` (service) or `129.224.0.x` (VPC resource) address come back from DNS, that is the overlapping-CIDR benefit in action.

## Consumption

Amazon VPC Lattice Blueprints have been designed to be consumed in the following manners:

1. **Reference**: Users can refer to the patterns and snippets provided to help guide them to their desired solution. Users will typically view how the pattern or snippet is configured to achieve the desired end result and then replicate that in their environment.

2. **Copy & Paste**: Users can copy and paste the patterns and snippets into their own environment, using VPC Lattice Blueprints as the starting point for their implementation. Users can then adapt the initial pattern to customize it to their specific needs.

**Amazon VPC Lattice Blueprints are not intended to be consumed as-is directly from this project**. The patterns provided only contain `variables` when certain information is required to deploy the pattern and generally use local variables. If you wish to deploy the patterns into a different AWS Region or with other changes, it is recommended that you make those modifications locally before applying the pattern.

## Patterns

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. Simple Architectures](./patterns/1-simple_architectures/) | Single-account VPC Lattice fundamentals across target types: EC2 instances, Auto Scaling groups, Lambda functions, ECS, EKS, and RDS / VPC Resources | CloudFormation, Terraform (EKS is Terraform-only) |
| [2. Multi-AWS Account](./patterns/2-multi_account/) | Cross-account sharing of a Lambda service and an Aurora resource configuration via AWS RAM, in centralized and distributed models | CloudFormation, Terraform |
| [3. Advanced Architectures](./patterns/3-advanced_architectures/) | Real-world architectures that go beyond the basic consumer–producer setup, composing VPC Lattice into larger designs | CloudFormation, Terraform |
| [4. Auth Policies & SigV4](./patterns/4-auth_policies/) | Reference toolkit (not a deployable pattern) for identity-based access control: how to SigV4-sign requests and a cookbook of auth policies to apply to any pattern. Every service-exposing pattern ships `AWS_IAM` auth with an open policy, ready to lock down | Reference |

## Which pattern do I need?

Browse the [Patterns](#patterns) table above to see what's available: patterns 1-3 are complete, deployable examples with testing and cleanup steps, and pattern 4 is a reference toolkit you apply on top of any of them.

To match your **specific** use case to the right pattern, the fastest path is to ask your preferred AI agent and model: install the [agent skill](./skills/vpc-lattice-blueprints/) (or give it [`SKILLS.md`](./SKILLS.md) and [`blueprint.yaml`](./blueprint.yaml) as pasted context — see the tip at the top of this README) and describe your scenario. With that context the agent can reason about VPC Lattice, recommend the pattern that fits, and explain how to compose or secure it. In a repository checkout the skill reads the canonical catalog directly; a standalone installation uses the versioned catalog snapshot documented in the [package README](./skills/vpc-lattice-blueprints/README.md).

## Infrastructure as Code Considerations

Amazon VPC Lattice Blueprints do not intend to teach users the recommended practices for Infrastructure as Code (IaC) tools nor does it offer guidance on how users should structure their IaC projects. The patterns provided are intended to show users how they can achieve a defined architecture or configuration in a way that they can quickly and easily get up and running to start interacting with that pattern. Therefore, there are a few considerations users should be aware of when using VPC Lattice Blueprints:

1. We recognize that most users will already have existing VPCs in separate IaC projects or stacks. However, the patterns provided come complete with VPCs to ensure stable, deployable examples that have been tested and validated.

2. Patterns are not intended to be consumed in-place in the same manner that one would consume a reusable module. Therefore, we do not provide extensive parameters and outputs to expose various levels of configuration for the examples. Users can modify the pattern locally after cloning to suit their requirements.

3. The patterns use local variables (Terraform) or parameters (CloudFormation) with sensible defaults. If you wish to deploy patterns into different regions or with other changes, modify these values before deploying.

4. For production deployments, we recommend separating your infrastructure into multiple projects or stacks (e.g., network infrastructure, application services, monitoring resources) to follow IaC best practices and enable independent lifecycle management.

### IaC support

Every pattern provides **both** a CloudFormation and a Terraform implementation, with one exception: the [EKS pattern](./patterns/1-simple_architectures/5-eks/) is **Terraform-only** (the AWS Gateway API Controller is installed via Helm and driven by Kubernetes Gateway API CRDs, which don't map cleanly to pure CloudFormation — see its [`Why Terraform-only`](./patterns/1-simple_architectures/5-eks/README.md#why-terraform-only) note). The **"IaC Support"** column in the [Patterns table](#patterns) is authoritative for what each pattern provides.

## Amazon VPC Lattice Fundamentals

[Amazon VPC Lattice](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html) is a fully managed application networking service that you use to connect, secure, and monitor services across multiple accounts and VPCs. VPC Lattice simplifies connectivity between your services by eliminating the need to manage load balancers, proxies, or complex networking configurations.

### Key concepts

These are the building blocks the patterns compose. For the full configuration of each, follow the link to the AWS documentation.

| Concept | What it is |
|---------|------------|
| [Service network](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-networks.html) | The logical boundary grouping services (and resource configurations) plus the VPCs allowed to reach them. Auth policy and access logging attach here; shareable across accounts via [AWS RAM](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html). |
| [Service](https://docs.aws.amazon.com/vpc-lattice/latest/ug/services.html) | An application/microservice you expose, reached via a generated FQDN or a [custom domain name](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-custom-domain-name.html). Holds listeners and target groups. |
| [Listener](https://docs.aws.amazon.com/vpc-lattice/latest/ug/listeners.html) | How a service accepts requests: **HTTP, HTTPS, gRPC, or TLS pass-through**. HTTPS on the generated FQDN is managed for you; bring an [ACM](https://aws.amazon.com/certificate-manager/) certificate for custom domains. |
| [Target group](https://docs.aws.amazon.com/vpc-lattice/latest/ug/target-groups.html) | Where a listener routes traffic, with health checks. Types: **INSTANCE**, **IP** (ECS tasks / EKS pods via the [AWS Gateway API Controller](https://www.gateway-api-controller.eks.aws.dev/latest/)), **LAMBDA**, and **ALB**. |
| [VPC association](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-network-associations.html#service-network-vpc-associations) | Connects a consumer VPC to a service network so its workloads can call the network's services (one direct association per VPC). |
| [VPC resource](https://docs.aws.amazon.com/vpc-lattice/latest/ug/vpc-resources.html) (resource gateway + resource configuration) | Reach a native AWS resource (e.g. [Amazon RDS](https://aws.amazon.com/rds/)), a domain name, or an IP over **raw TCP** through the service network. |
| [Service network VPC endpoint](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-network-associations.html#service-network-vpc-endpoint-associations) | An AWS PrivateLink endpoint that reaches a service network from **outside** the VPC — over VPC peering, Transit Gateway, Direct Connect, or VPN — for hybrid and cross-Region access. |
| [Auth policy](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html) | IAM resource-based policy at service-network and/or service scope for identity-based access control with SigV4 request signing. |
| [Access logging](https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html) | Per-request logs (client, path, status, auth result) to [CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html), [Amazon S3](https://aws.amazon.com/pm/serv-s3/), or [Amazon Data Firehose](https://aws.amazon.com/firehose/). |

For private-DNS behaviour, custom domains, and the full detail of each construct, see the [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html).

## Cost and Cleanup

> **Deploying any pattern in this repository provisions real, billable AWS resources in your account.** These blueprints are designed for proof-of-concept and learning use; deploy them in a non-production account, and **tear them down when you are finished** to stop incurring charges.

### What you pay for

Costs vary by pattern, but the main drivers across the published blueprints are:

- **VPC Lattice**: per-request processing and hourly charges for service networks/services and resource configurations (see [VPC Lattice pricing](https://aws.amazon.com/vpc/lattice/pricing/)).
- **Amazon EC2**: most patterns run consumer (and, where applicable, provider) EC2 instances for testing. These bill per instance-hour while deployed.
- **Data egress / NAT**: the patterns intentionally avoid NAT gateways by using an **IPv6 egress-only internet gateway** for outbound package installs, so there is no NAT hourly/processing charge; standard data-transfer-out rates still apply. The **EKS** pattern is the exception - it provisions a **NAT gateway** (hourly + per-GB processing).
- **Amazon RDS / Aurora** (RDS / VPC Resources **and** both Multi-AWS Account patterns): Aurora instance-hours plus storage and I/O for the cluster.
- **Amazon EKS** (EKS pattern): the **EKS control plane** (per-hour, per-cluster), the **managed node group** EC2 instance-hours, and the **NAT gateway** noted above. This is the most expensive pattern to run.
- **CloudWatch Logs (access logging)**: every pattern that creates a service network and/or service enables [VPC Lattice access logging](https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html) **by default** to a CloudWatch Logs log group (`/aws/vpclattice/<identifier>`). This incurs CloudWatch Logs vended-logs pricing (ingestion + storage) while deployed. The log group is created and destroyed with the pattern.
- **Multiple accounts**: the [Multi-AWS Account](./patterns/2-multi_account/) patterns deploy resources in two or three accounts, so the above costs apply in each account involved.

### Multi-AZ cost note

For stable, realistic examples, **patterns deploy across multiple Availability Zones by default** (for example, an Auto Scaling group or consumer instances spread across every configured AZ). This increases the running cost relative to a single-AZ deployment. For cost-sensitive testing you can reduce the AZ count where a pattern's variables allow it; for production we still recommend at least two AZs for high availability. Each pattern README repeats this note for the resources it deploys.

### Cleaning up

**Tear down each pattern when you're finished** to stop incurring charges. Every deployable pattern documents its exact teardown in its README's **Cleanup** section. Everything a pattern creates, including its access-logging CloudWatch Logs group, is removed by that teardown, so no manual cleanup is required.

## Prerequisites

Before using these blueprints, you should have:

- **AWS Networking Knowledge**: understanding of VPCs, subnets, security groups, and service-to-service communication patterns.
- **Application Networking Concepts**: familiarity with load balancing, service discovery, and application layer protocols.
- **Infrastructure as Code**: experience with AWS CloudFormation or Terraform.
- **AWS Account**: an AWS account with appropriate IAM permissions to create networking resources.

## Support & Feedback

Amazon VPC Lattice Blueprints are maintained by AWS Solution Architects. This is not part of an AWS service and support is provided as best-effort by the VPC Lattice Blueprints community. To provide feedback, please use the [issues templates](https://github.com/aws-samples/amazon-vpc-lattice-blueprints/issues) provided. If you are interested in contributing to VPC Lattice Blueprints, see the [Contribution guide](CONTRIBUTING.md).

## How do I troubleshoot VPC Lattice connectivity?

Most connectivity issues across these patterns fall into a few buckets. Work through them in order, and use the access logs (last item) to see what actually happened.

### A request to a service fails or times out

- Confirm the **VPC association** (consumer VPC ↔ service network) and the **service association** (service ↔ service network) are both in the `Active` state.
- Check **target health** — the target group should report targets as `Healthy` (see "Targets show Unhealthy" below).
- Verify **security groups**: targets must allow the [VPC Lattice managed prefix lists](https://docs.aws.amazon.com/vpc-lattice/latest/ug/security-groups.html) (IPv4 **and** IPv6) on the listener/health-check port, and the consumer must be allowed to reach VPC Lattice on the service port (HTTPS/443 in these patterns).
- For **cross-account** patterns, confirm the [AWS RAM](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html) share has been **accepted** and the service network/service is shared with the correct account(s).

### DNS does not resolve to a VPC Lattice address

From an associated VPC, a **service** name should resolve to a **link-local** address (`169.254.171.x/24`, IPv6 `fd00:ec2:80::/64`), and a **VPC resource** name to the `129.224.0.x/17` range (IPv6 `fd00:ec2:80::/64`). If it doesn't:

- Ensure the VPC has **DNS resolution** and **DNS hostnames** enabled.
- Ensure the consumer VPC's **service network association is `Active`**.
- For **custom domain names** or **VPC resources**, confirm the private hosted zone (or the managed PHZ selected via [DNS preferences](https://docs.aws.amazon.com/vpc-lattice/latest/ug/resource-configuration.html#custom-domain-name-resource-consumers)) is associated to the consumer VPC.

### Targets show Unhealthy

- The target application must be **listening on the configured port**, and on **IPv6** as well, if an IPv6 IP target group is used.
- Security groups must allow **health-check traffic from the VPC Lattice managed prefix lists**.
- The health-check **path, port, and protocol** must match what the target actually serves.

### A signed request returns 403 (auth policies)

- For `AWS_IAM` services, a `403 AccessDeniedException` means the request was **denied by the auth policy** (or was unsigned). Confirm the caller is a principal the [auth policy](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html) allows, and that the request is **SigV4-signed** for the `vpc-lattice-svcs` service.

### Use access logs to see what happened

Every pattern enables [VPC Lattice access logging](https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html) by default to a CloudWatch Logs log group (`/aws/vpclattice/<identifier>`). Each entry records the request — client, target, response code, and auth result — which is the fastest way to confirm whether a request reached VPC Lattice and how it was handled.

## FAQ

**Q: Are more patterns coming?**

A: Yes. We're actively developing the blueprint library. Everything listed in the pattern table is published and ready to deploy. See [CONTRIBUTING](./CONTRIBUTING.md) to provide feedback or request new patterns.

**Q: Can I use these patterns in production?**

A: These patterns are **not ready** for production environments. They should be customized for your specific requirements. Update variables, CIDR blocks, and configurations before deploying to production. Always test in pre-production environments first.

**Q: Do I need separate AWS accounts to use these patterns?**

A: No, most patterns can be deployed in a single AWS account. However, the [Multi-AWS Account pattern](./patterns/2-multi_account/) demonstrates cross-account deployment using AWS Resource Access Manager (RAM).

**Q: Which IaC tool should I use?**

A: Both CloudFormation and Terraform are supported for most patterns. Choose based on your organization's preferences and existing tooling. Terraform patterns use the [AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) and [AWSCC](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs) providers.

**Q: What are the differences between VPC Lattice and Application Load Balancer?**

A: In short, VPC Lattice handles service-to-service communication across VPCs and accounts, while ALB handles client-to-application traffic within a VPC. See [Why VPC Lattice over load balancers?](#why-vpc-lattice-over-load-balancers) near the top of this README for the full comparison (managed cross-account connectivity, identity-based access control, and built-in observability).

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See [LICENSE](LICENSE).
