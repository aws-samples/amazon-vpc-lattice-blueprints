# Amazon VPC Lattice - EC2 Instance Targets

This pattern demonstrates publishing HTTP/HTTPS services backed by **EC2 instances** through VPC Lattice, using both the **INSTANCE** and **IP** target types. Both the consumer and provider VPCs intentionally use the same address space (`10.0.0.0/16`) to make the overlapping-CIDR benefit explicit.

It is the entry-point pattern for understanding the core VPC Lattice building blocks (service network, service, listener, and target group) with EC2 instances as the backend.

![EC2 Instance & IP target](../../../images/pattern1_architecture1.png)

From the consumer EC2 instance, each service's DNS name resolves to a VPC Lattice **link-local** address (`169.254.171.x/24`, IPv6 `fd00:ec2:80::/64`); the request is then brokered by VPC Lattice to a healthy EC2 target.

## What gets deployed

| Component | Details |
|-----------|---------|
| **Consumer VPC** (`10.0.0.0/16`) | EC2 instances (1 per AZ) with an EC2 Instance Connect endpoint for remote access; associated to the service network |
| **Provider VPC** (`10.0.0.0/16`) | EC2 instances (1 per AZ) configured as web servers (httpd), with an IPv6 egress-only internet gateway for package installs (no NAT cost) |
| **Target groups** | 3 target groups: one **INSTANCE** type, one **IPv4 IP** type, one **IPv6 IP** type |
| **VPC Lattice services** | 2 services with HTTPS listeners demonstrating different target types and routing |
| **Access logging** | A CloudWatch Logs log group (`/aws/vpclattice/<identifier>`) and an access log subscription at the service-network scope |

## VPC Lattice services configuration

This pattern creates two VPC Lattice services to contrast target types and routing configurations:

| Aspect | Service 1 | Service 2 |
|--------|-----------|-----------|
| **Custom domain name** | ❌ No (uses VPC Lattice-generated FQDN) | ✅ Yes (configurable via variables) |
| **Certificate** | ❌ VPC Lattice-managed | ✅ ACM certificate (configurable via variables) |
| **Private hosted zone** | ❌ Not required | ✅ Route 53 private hosted zone for DNS resolution |
| **Listener** | HTTPS on port 443 | HTTPS on port 443 |
| **Target groups** | 1 INSTANCE type | 1 IPv4 IP type + 1 IPv6 IP type |
| **Routing** | 100% traffic to INSTANCE target group | 50% traffic to IPv4 targets, 50% to IPv6 targets |
| **Targets** | 2 EC2 instances (by instance ID) on port 80 | Same 2 EC2 instances (by IP address) on port 80 |
| **Backend protocol** | HTTP | HTTP |

**Key differences:**
- **Service 1** uses instance IDs (INSTANCE target type) and the VPC Lattice-generated domain.
- **Service 2** uses IP addresses (IP target type) with both IPv4 and IPv6, plus a custom domain name.
- Both services target the same EC2 instances but demonstrate different targeting methods.

> **Note**: An egress-only internet gateway is created in the provider VPC to allow EC2 instances to install packages. IPv6 is used to avoid NAT gateway costs while providing egress access.

## Implementation

This pattern is available for both IaC tools (CloudFormation + Terraform parity). Each implementation directory has its own README with deployment instructions:

| IaC Tool | Location |
|----------|----------|
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) |
| **Terraform** | [`./terraform/`](./terraform/) |

## Testing Connectivity

After deploying either implementation, you connect to a consumer EC2 instance, resolve each service's DNS name through VPC Lattice (it returns a link-local `169.254.171.x` address), and `curl` the services to confirm HTTP-over-Lattice connectivity to the EC2 targets — across two VPCs that both use `10.0.0.0/16`, with no VPC peering or transit gateway.

<details>
<summary>Click to expand testing steps</summary>

#### Step 1: Connect to a consumer instance

Use the EC2 Instance Connect endpoint to access a consumer instance:

> **Note**: Consumer EC2 instance IDs are provided as outputs when deploying the CloudFormation or Terraform code. Check the deployment outputs to get the instance IDs.

```bash
aws ec2-instance-connect ssh --instance-id <consumer-instance-id>
```

#### Step 2: Test DNS resolution

Verify VPC Lattice DNS resolution for both services:

> **Note**: Both service domain names are provided as outputs when deploying the CloudFormation or Terraform code. Check the deployment outputs to get the exact domain names.

| Service | Command | Expected Result |
|---------|---------|-----------------|
| **Service 1** | `dig <service1-domain-name>` | Link-local address (`169.254.171.x`) indicating VPC Lattice routing |
| **Service 2** | `dig <custom-domain-name>` | Link-local address (`169.254.171.x`) — ALIAS record configured |

#### Step 3: Test HTTPS connectivity

Test connectivity to both services using the same curl command with their respective domain names:

```bash
# Service 1 (VPC Lattice-generated domain)
curl https://<service1-domain-name>

# Service 2 (Custom domain name)
curl https://<custom-domain-name>
```

**Expected response:**
- "Hello from EC2 instance"
- Request IP address (VPC Lattice IP — IPv4 or IPv6 depending on which target group was used)

#### Step 4: Test load distribution

Verify traffic distribution patterns for each service:

| Service | Command | Expected Distribution |
|---------|---------|----------------------|
| **Service 1** | `for i in {1..10}; do curl https://<service1-domain-name>; echo ""; done` | 100% to INSTANCE target group (distributed across 2 EC2 instances) |
| **Service 2** | `for i in {1..20}; do curl https://<custom-domain-name>; echo ""; done` | 50% to IPv4 targets, 50% to IPv6 targets (same 2 EC2 instances) |

#### Step 5: Verify target health

Check that all targets are healthy in the AWS Console:

1. Navigate to **VPC → VPC Lattice → Target groups**
2. Select each of the three target groups (one INSTANCE type, one IPv4 IP type, one IPv6 IP type)
3. Verify all targets show **"Healthy"** status

</details>

## Cleanup

Tear down the resources when you are finished to stop incurring charges. While this pattern is deployed it runs consumer and provider EC2 instances (instance hours) and uses CloudWatch Logs vended-logs pricing for VPC Lattice access logging (ingestion + storage).

Use the teardown command for whichever implementation you deployed:

| IaC Tool | From | Command |
|----------|------|---------|
| **Terraform** | [`./terraform/`](./terraform/) | `terraform destroy` |
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) | `make undeploy` |

The access-logging CloudWatch Logs log group is created and destroyed together with the pattern, so the standard teardown removes it, no manual cleanup is required.

## Next Steps

After successfully deploying this pattern:

1. **Test connectivity**: Follow the testing guide above to verify both services work correctly.
2. **Explore other targets**: Try [Auto Scaling Group](../2-auto_scaling_group/), [Lambda](../3-lambda_function/), [ECS](../4-ecs/), [EKS](../5-eks/), or [RDS / VPC Resources](../6-rds/) patterns.
3. **Restrict access**: This pattern already enables `AWS_IAM` auth with an open policy. See the [Auth Policies & SigV4 toolkit](../../4-auth_policies/) to swap in a restrictive policy and sign requests with SigV4.
4. **Multi-Account**: Move to [Multi-Account patterns](../../2-multi_account/) for cross-account deployments.
5. **Advanced architectures**: Explore [Advanced patterns](../../3-advanced_architectures/) for more complex scenarios.
