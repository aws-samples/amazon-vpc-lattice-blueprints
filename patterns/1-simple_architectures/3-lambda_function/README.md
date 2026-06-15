# Amazon VPC Lattice - Lambda Function Targets

This pattern demonstrates publishing an HTTP/HTTPS service backed by an **AWS Lambda function** through VPC Lattice, using the **LAMBDA** target type. The consumer VPC uses the `10.0.0.0/16` address space; because the target is a serverless function rather than an in-VPC instance, VPC Lattice brokers the request without any peering or transit gateway, making the overlapping-CIDR benefit explicit for serverless backends too.

It shows how a serverless function can be exposed as a VPC Lattice service and consumed exactly like any instance- or IP-based target, with no networking changes on the consumer side.

![Lambda Function target](../../../images/pattern1_architecture3.png)

From the consumer EC2 instance, the service's DNS name resolves to a VPC Lattice **link-local** address (`169.254.171.x`); the request is then brokered by VPC Lattice and invokes the Lambda function.

## What gets deployed

| Component | Details |
|-----------|---------|
| **Consumer VPC** (`10.0.0.0/16`) | EC2 instances (1 per AZ) with an EC2 Instance Connect endpoint for remote access; associated to the service network |
| **Lambda Function** | Serverless function responding to HTTP requests |
| **Target group** | 1 **LAMBDA** type target group |
| **VPC Lattice service** | 1 service with an HTTPS listener forwarding to Lambda |
| **Access logging** | A CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) and an access log subscription at the service-network scope |

## VPC Lattice service configuration

This pattern creates one VPC Lattice service demonstrating Lambda function integration:

| Aspect | Configuration |
|--------|---------------|
| **Custom Domain Name** | ❌ No (uses VPC Lattice-generated FQDN) |
| **Certificate** | ❌ VPC Lattice-managed |
| **Listener** | HTTPS on port 443 |
| **Target Group** | LAMBDA type |
| **Routing** | 100% traffic to Lambda function |
| **Target** | AWS Lambda function |
| **Backend Protocol** | N/A (Lambda invocation) |

## Implementation

This pattern is available for both IaC tools (CloudFormation + Terraform parity). Each implementation directory has its own README with deployment instructions:

| IaC Tool | Location |
|----------|----------|
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) |
| **Terraform** | [`./terraform/`](./terraform/) |

## Testing Connectivity

After deploying either implementation, you connect to a consumer EC2 instance, resolve the service's DNS name through VPC Lattice (it returns a link-local `169.254.171.x` address), and `curl` the service to confirm the request is brokered to the Lambda function — with no VPC peering or transit gateway.

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

Test connectivity to the Lambda function through VPC Lattice:

```bash
curl https://<service-domain-name>
```

**Expected Response** (JSON format):
```json
{
  "message": "Hello from Lambda Function!!",
  "request_ip": "169.254.171.X"
}
```

</details>

## Cleanup

Tear down the resources when you are finished to stop incurring charges. While this pattern is deployed it runs consumer EC2 instances (instance hours) and uses CloudWatch Logs vended-logs pricing for VPC Lattice access logging (ingestion + storage). The Lambda function itself only incurs cost per invocation.

Use the teardown command for whichever implementation you deployed:

| IaC Tool | From | Command |
|----------|------|---------|
| **Terraform** | [`./terraform/`](./terraform/) | `terraform destroy` |
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) | `make undeploy` |

The access-logging CloudWatch Logs log group is created and destroyed together with the pattern, so the standard teardown removes it, no manual cleanup is required.

## Next Steps

After successfully deploying this pattern:

1. **Test connectivity**: Follow the testing guide above to verify the service works correctly.
2. **Explore other targets**: Try [EC2 Instance](../1-ec2_instance/), [Auto Scaling Group](../2-auto_scaling_group/), [ECS](../4-ecs/), [EKS](../5-eks/), or [RDS / VPC Resources](../6-rds/) patterns.
3. **Restrict access**: This pattern already enables `AWS_IAM` auth with an open policy. See the [Auth Policies & SigV4 toolkit](../../4-auth_policies/) to swap in a restrictive policy and sign requests with SigV4.
4. **Multi-Account**: Move to [Multi-Account patterns](../../2-multi_account/) for cross-account deployments.
5. **Advanced architectures**: Explore [Advanced patterns](../../3-advanced_architectures/) for more complex scenarios.
