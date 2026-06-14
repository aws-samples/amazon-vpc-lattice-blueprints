# Amazon VPC Lattice Blueprints - Advanced Architectures

## Overview

This section demonstrates advanced Amazon VPC Lattice patterns that go beyond standard service-to-service connectivity, addressing enterprise scenarios where VPC Lattice solves more complex networking challenges.

**Use this section to**:

- Explore practical applications of VPC Lattice beyond basic service connectivity.
- Learn implementation patterns for complex enterprise requirements.
- Understand how to adapt VPC Lattice to unique architectural needs.

> **Note**: These patterns assume familiarity with VPC Lattice basics. If you're new to VPC Lattice, start with [Simple Architectures](../1-simple_architectures/) and [Multi-Account Patterns](../2-multi_account/).

## Architecture Patterns

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. Centralized VPC Endpoints](./1-centralized_vpc_endpoints/) | Centralize interface VPC endpoints in a shared VPC and reach them from consumer VPCs through VPC Lattice VPC Resources | CloudFormation, Terraform |

## Next Steps

After exploring these advanced architectures, check how to implement granular controls for service-to-service communication - **[Auth Policies & SigV4](../4-auth_policies/)**.
