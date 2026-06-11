# Amazon VPC Lattice Blueprints - Simple Architectures

## Overview

This pattern demonstrates the fundamental concepts of Amazon VPC Lattice through straightforward single-account architectures. It's designed as an entry point for understanding service networks, services, target groups, and VPC associations.

**Use this pattern to**:

- Learn VPC Lattice basics in a hands-on environment.
- Understand different target types in VPC Lattice (EC2 instances, Auto Scaling groups, Lambda functions, ECS, EKS) and VPC resources (RDS).
- Test service-to-service communication patterns.
- Build a foundation for more complex patterns.

> **Note**: All examples are configured to be deployed in a single AWS Account. For multi-AWS Account examples, see the [Multi-Account Patterns](../2-multi_account/) section.

## Architecture Patterns

This section includes multiple sub-patterns demonstrating different VPC Lattice target types:

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. EC2 Instance](./1-ec2_instance/) | EC2 instances as targets using INSTANCE and IP target types | CloudFormation, Terraform |
| [2. Auto Scaling Group](./2-auto_scaling_group/) | Auto Scaling group as target with automatic instance registration | CloudFormation, Terraform |
| [3. Lambda Function](./3-lambda_function/) | AWS Lambda function as serverless target | CloudFormation, Terraform |
| [4. ECS](./4-ecs/) | Amazon ECS tasks as containerized targets | CloudFormation, Terraform |
| [5. EKS](./5-eks/) | Amazon EKS pods as IP targets via the AWS Gateway API Controller | Terraform |
| [6. RDS / VPC Resources](./6-rds/) | Amazon Aurora (MySQL) as a native TCP resource via VPC Lattice VPC Resources (resource gateway) | CloudFormation, Terraform |

## Next Steps

After mastering these simple architectures, explore:

1. **[Multi-Account Patterns](../2-multi_account/)** - Deploy across multiple AWS accounts
2. **[Advanced Architectures](../3-advanced_architectures/)** - Check advanced scenarios where VPC Lattice can help your service-to-service communication at scale
3. **[Auth policies](../4-auth_policies/)** - Implement granular control for service-to-service communication 
