# Amazon VPC Lattice - ECS Fargate Targets

This pattern demonstrates publishing an HTTP/HTTPS service backed by **Amazon ECS Fargate** tasks through VPC Lattice, using the **IP** target type. Both the consumer and provider VPCs intentionally use the same address space (`10.0.0.0/16`) to make the overlapping-CIDR benefit explicit. It shows how a containerized application running on ECS Fargate is exposed as a VPC Lattice service, with the running tasks registered as IP targets and reached from a consumer in a separate VPC.

![ECS target](../../../images/pattern1_architecture4.png)

From the consumer EC2 instance, the service's DNS name resolves to a VPC Lattice **link-local** address (`169.254.171.x`); the request is then brokered by VPC Lattice to a healthy ECS task.

## What gets deployed

| Component | Details |
|-----------|---------|
| **Consumer VPC** (`10.0.0.0/16`) | EC2 instances (1 per AZ) with an EC2 Instance Connect endpoint for remote access; associated to the service network |
| **Provider VPC** (`10.0.0.0/16`) | ECS Fargate cluster with containerized application |
| **ECR Repository** | Amazon ECR repository for Docker images |
| **Target group** | 1 **IP** type target group |
| **VPC Lattice service** | 1 service with an HTTPS listener forwarding to ECS tasks |
| **VPC Endpoints** | ECR API, ECR DKR, S3 Gateway, and CloudWatch Logs endpoints |
| **Access logging** | A CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) and an access log subscription at the service-network scope |

## VPC Lattice service configuration

This pattern creates one VPC Lattice service demonstrating ECS Fargate integration:

| Aspect | Configuration |
|--------|---------------|
| **Custom Domain Name** | ❌ No (uses VPC Lattice-generated FQDN) |
| **Certificate** | ❌ VPC Lattice-managed |
| **Listener** | HTTPS on port 443 |
| **Target Group** | IP type |
| **Routing** | 100% traffic to ECS tasks |
| **Targets** | ECS Fargate tasks (automatically registered) |
| **Backend Protocol** | HTTP on port 80 |

## Implementation

This pattern is available for both IaC tools (CloudFormation + Terraform parity). Each implementation directory has its own README with deployment instructions:

| IaC Tool | Location |
|----------|----------|
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) |
| **Terraform** | [`./terraform/`](./terraform/) |

## Testing Connectivity

After deploying either implementation, you connect to a consumer EC2 instance, resolve the service's DNS name through VPC Lattice (it returns a link-local `169.254.171.x` address), and `curl` the service to confirm HTTP-over-Lattice connectivity to the ECS Fargate tasks — across two VPCs that both use `10.0.0.0/16`, with no VPC peering or transit gateway.

<details>
<summary>Click to expand testing steps</summary>

#### Step 1: Connect to Consumer Instance

Use EC2 Instance Connect endpoint to access a consumer instance:

> **Note**: Consumer EC2 instance IDs are provided as outputs when deploying the CloudFormation or Terraform code. Check the deployment outputs to get the instance IDs.

```bash
aws ec2-instance-connect ssh --instance-id <consumer-instance-id>
```

#### Step 2: Test DNS Resolution

Verify VPC Lattice DNS resolution:

> **Note**: The service domain name is provided as an output when deploying the CloudFormation or Terraform code. Check the deployment outputs to get the exact domain name.

```bash
dig <service-domain-name>
```

**Expected Result**: Link-local address (169.254.171.X) indicating VPC Lattice routing

#### Step 3: Test HTTPS Connectivity

Test connectivity to the ECS Fargate service through VPC Lattice:

```bash
curl https://<service-domain-name>
```

**Expected Response** (JSON format):
```json
{
  "message": "Hello from ECS Fargate!!",
  "request_ip": "169.254.171.X"
}
```

#### Step 4: Verify Target Health

Check that ECS tasks are healthy:

1. Navigate to **VPC → VPC Lattice → Target groups**
2. Select the ECS service's IP type target group
3. Verify ECS task IPs show **"Healthy"** status

</details>

## Cleanup

Tear down the resources when you are finished to stop incurring charges. While this pattern is deployed it runs consumer EC2 instances and ECS Fargate tasks, plus the provider VPC endpoints, and uses CloudWatch Logs vended-logs pricing for VPC Lattice access logging (ingestion + storage).

Use the teardown command for whichever implementation you deployed:

| IaC Tool | From | Command |
|----------|------|---------|
| **Terraform** | [`./terraform/`](./terraform/) | `terraform destroy` |
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) | `make undeploy` |

The ECR repository is configured to be removed with the pattern, and the access-logging CloudWatch Logs log group is created and destroyed together with the pattern, so the standard teardown removes them, no manual cleanup is required.

## Next Steps

After successfully deploying this pattern:

1. **Test connectivity**: Follow the testing guide above to verify the service works correctly.
2. **Explore other targets**: Try [EC2 Instance](../1-ec2_instance/), [Auto Scaling Group](../2-auto_scaling_group/), [Lambda](../3-lambda_function/), [EKS](../5-eks/), or [RDS / VPC Resources](../6-rds/) patterns.
3. **Add access control**: See the [Auth Policies & SigV4](../../4-auth_policies/) pattern to gate a service by IAM identity.
4. **Multi-Account**: Move to [Multi-Account patterns](../../2-multi_account/) for cross-account deployments.
5. **Advanced architectures**: Explore [Advanced patterns](../../3-advanced_architectures/) for more complex scenarios.
