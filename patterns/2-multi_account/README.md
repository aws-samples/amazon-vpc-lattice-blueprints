# Amazon VPC Lattice Blueprints - Multi-Account Architectures

## Overview

This section demonstrates how Amazon VPC Lattice operates **across multiple AWS accounts**, using [AWS Resource Access Manager](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html) (RAM) to share **service networks**, **services**, and **resource configurations** between AWS accounts. It shows the two governance models you choose between when a network team and application teams live in different accounts.

**Use this section to**:

- Share VPC Lattice service networks, services, and resource configurations across accounts with AWS RAM.
- Compare **centralized** governance (a network account owns the service network) vs. **distributed** ownership (each consumer owns its own service network).
- Understand the cross-account deployment order and RAM share directions each model requires.

> **Note**: These examples use VPC Lattice-generated domain names; cross-account custom-domain DNS is out of scope. For automated DNS configuration across accounts, see the [Amazon VPC Lattice Automated DNS Configuration Guidance](https://aws.amazon.com/solutions/guidance/amazon-vpc-lattice-automated-dns-configuration-on-aws/).

## Architecture Patterns

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. Centralized Service Network](./1-centralized_service_network/) | A central **network account** owns and shares the service network; a **provider account** shares a service and a resource configuration into it; **consumer accounts** associate their VPCs | CloudFormation, Terraform |
| [2. Distributed Service Networks](./2-distributed/) | A **provider account** shares a service and a resource configuration; each **consumer account** owns its own service network and chooses which services and/or resource configurations to consume | CloudFormation, Terraform |

Both patterns share the same building blocks so the comparison stays focused on the multi-account model: a **provider account** exposing a Lambda-backed VPC Lattice **service** (HTTPS 443 listener) *and* an Aurora **resource configuration** (with its RDS-managed credentials shared cross-account via Secrets Manager + a customer-managed KMS key), and a **consumer VPC** with EC2 instances (1 per AZ) reached through an EC2 Instance Connect endpoint. VPC Lattice **access logging** is enabled by default. The only difference is **who owns the service network** — a central network account (centralized) or each consumer (distributed).

> **RAM sharing scope**: For simplicity these examples share resources with the **entire AWS Organization**. In production, share only with the specific account IDs that need access (least privilege).

## Choosing Between Patterns

| Consideration | Centralized | Distributed |
|---------------|-------------|-------------|
| **Service network ownership** | Network account (central) | Each consumer account |
| **Governance model** | Central team controls the network | Consumers control their own networks |
| **Policy management** | Centralized, consistent | Decentralized, flexible |
| **Operational overhead** | Lower for consumers | Higher for consumers |
| **Best for** | Strong central networking teams | Autonomous application teams |

## Next Steps

After exploring these multi-account architectures:

1. **[Advanced Architectures](../3-advanced_architectures/)** - Centralize VPC endpoints across VPCs
2. **[Auth Policies & SigV4](../4-auth_policies/)** - Add identity-based access control to shared services
