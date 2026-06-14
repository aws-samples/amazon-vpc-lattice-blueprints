# Amazon VPC Lattice - Auto Scaling Group Targets

This pattern demonstrates publishing an HTTP/HTTPS service backed by an **Amazon EC2 Auto Scaling group** through VPC Lattice, using the **INSTANCE** target type. Both the consumer and provider VPCs intentionally use the same address space (`10.0.0.0/16`) to make the overlapping-CIDR benefit explicit.

![Auto Scaling Group target](../../../images/pattern1_architecture2.png)

From the consumer EC2 instance, the service's DNS name resolves to a VPC Lattice **link-local** address (`169.254.171.x`); the request is then brokered by VPC Lattice to a healthy instance in the Auto Scaling group.

## What gets deployed

| Component | Details |
|-----------|---------|
| **Consumer VPC** (`10.0.0.0/16`) | EC2 instances (1 per AZ) with an EC2 Instance Connect endpoint for remote access; associated to the service network |
| **Provider VPC** (`10.0.0.0/16`) | Auto Scaling group with 2 EC2 instances (1 per AZ) configured as web servers |
| **Target group** | 1 **INSTANCE** type target group |
| **VPC Lattice service** | 1 service with an HTTPS listener forwarding to the Auto Scaling group |
| **Access logging** | A CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) and an access log subscription at the service-network scope |

## VPC Lattice service configuration

This pattern creates one VPC Lattice service demonstrating Auto Scaling group integration:

| Aspect | Configuration |
|--------|---------------|
| **Custom Domain Name** | ❌ No (uses VPC Lattice-generated FQDN) |
| **Certificate** | ❌ VPC Lattice-managed |
| **Listener** | HTTPS on port 443 |
| **Target Group** | INSTANCE type (Auto Scaling group) |
| **Routing** | 100% traffic to Auto Scaling group instances |
| **Targets** | Auto Scaling group (automatic instance registration/deregistration) |
| **Backend Protocol** | HTTP |

**Key Feature**: The Auto Scaling group is associated with the VPC Lattice target group using the `attach-traffic-sources` action, enabling automatic instance registration and deregistration as the group scales.

> **Note**: An egress-only Internet gateway is created in the provider VPC to allow EC2 instances to install packages. IPv6 is used to avoid NAT gateway costs while providing egress access.

## Implementation

This pattern is available for both IaC tools (CloudFormation + Terraform parity). Each implementation directory has its own README with deployment instructions:

| IaC Tool | Location |
|----------|----------|
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) |
| **Terraform** | [`./terraform/`](./terraform/) |

## Testing Connectivity

After deploying either implementation, you connect to a consumer EC2 instance, resolve the service's DNS name through VPC Lattice (it returns a link-local `169.254.171.x` address), and `curl` the service to confirm HTTP-over-Lattice connectivity to the Auto Scaling group — across two VPCs that both use `10.0.0.0/16`, with no VPC peering or transit gateway.

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

Test connectivity to the service:

```bash
curl https://<service-domain-name>
```

**Expected Response**:
- "Hello from the AutoScaling Group!!"
- Request IP address (VPC Lattice IP showing which instance handled the request)

#### Step 4: Verify Target Health

Check that all Auto Scaling group instances are healthy:

1. Navigate to **VPC → VPC Lattice → Target groups**
2. Select the Auto Scaling group's INSTANCE type target group
3. Verify all instances show **"Healthy"** status

</details>

## Cleanup

Tear down the resources when you are finished to stop incurring charges. While this pattern is deployed it runs consumer EC2 instances and the provider Auto Scaling group (instance hours) and uses CloudWatch Logs vended-logs pricing for VPC Lattice access logging (ingestion + storage).

Use the teardown command for whichever implementation you deployed:

| IaC Tool | From | Command |
|----------|------|---------|
| **Terraform** | [`./terraform/`](./terraform/) | `terraform destroy` |
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) | `make undeploy` |

The access-logging CloudWatch Logs log group is created and destroyed together with the pattern, so the standard teardown removes it, no manual cleanup is required.

## Next Steps

After successfully deploying this pattern:

1. **Test connectivity**: Follow the testing guide above to verify the service works correctly.
2. **Explore other targets**: Try [EC2 Instance](../1-ec2_instance/), [Lambda](../3-lambda_function/), [ECS](../4-ecs/), [EKS](../5-eks/), or [RDS / VPC Resources](../6-rds/) patterns.
3. **Add access control**: See the [Auth Policies & SigV4](../../4-auth_policies/) pattern to gate a service by IAM identity.
4. **Multi-Account**: Move to [Multi-Account patterns](../../2-multi_account/) for cross-account deployments.
5. **Advanced architectures**: Explore [Advanced patterns](../../3-advanced_architectures/) for more complex scenarios.
