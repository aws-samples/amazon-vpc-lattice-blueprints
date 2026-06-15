# Amazon VPC Lattice - Multi-Account: Distributed Service Networks

This pattern demonstrates the **distributed** multi-account model and shows **two** VPC Lattice primitives that can be shared: a **service** and a **resource configuration**. A **provider account** creates a Lambda-backed **service** *and* an Aurora **resource configuration**, sharing both (via AWS RAM) across the Organization; each **consumer account** owns its **own service network**, associates the shared service and resource configuration to it, and associates its VPCs. Ownership is decentralized (each consumer decides which shared services and resources to consume and governs its own network) maximizing autonomy for application teams. The consumer also reads Aurora's RDS-managed credentials **cross-account** from AWS Secrets Manager, so it can fully authenticate to the database.

![Distributed Service Network](../../../images/distributed.png)

<!-- TODO: update distributed.png to include the Aurora resource configuration (resource gateway + Aurora in the provider account). -->

From a consumer EC2 instance, the **service** DNS name resolves to a VPC Lattice **link-local** address (`169.254.171.x/24`) and the **Aurora** endpoint resolves to the VPC Lattice **VPC-resource** range (`129.224.0.x/17`) — IPv6 `fd00:ec2:80::/64` for both.

## Account structure

| Account | Responsibilities | Key resources |
|---------|------------------|---------------|
| **Provider account** | Creates and shares the VPC Lattice service *and* the Aurora resource configuration; shares the DB credentials | Provider VPC, VPC Lattice service + HTTPS listener, Lambda + target group, Aurora cluster, resource gateway, resource configuration, RAM share, RDS-managed secret + customer-managed KMS key (shared org-wide), access logging (service scope) |
| **Consumer account** | Owns its service network, associates the shared service and resource configuration, and reads the shared DB credentials | Service network (`AWS_IAM`), service + resource-config associations, consumer VPC (+ egress-only IGW), VPC association (private DNS), EC2 instances + EC2 Instance Connect endpoint, Secrets Manager interface endpoint, EC2 IAM role (read the shared secret), access logging (service-network scope) |

## RAM sharing flow

| Shared resource | Direction | Purpose |
|-----------------|-----------|---------|
| **VPC Lattice service + resource configuration** | Provider account → Consumer accounts | One RAM share (`provider-resource-share`) carries both; each consumer associates them to its own service network |

> **Credentials are not shared via RAM.** Secrets Manager secrets aren't RAM-shareable — the consumer reads Aurora's RDS-managed secret cross-account via the secret's **resource policy** + the **customer-managed KMS key** policy (both scoped to the Organization). A customer-managed key is required because the default `aws/secretsmanager` key can't be shared.

## VPC Lattice configuration

| Aspect | Configuration |
|--------|---------------|
| **Service network** | `AWS_IAM` auth with a permissive (allow-all) auth policy; owned by each consumer account |
| **Service** | HTTPS listener on port 443, `AWS_IAM` auth with an open (allow-all) policy, 100% forward to the Lambda target group; owned by the provider account |
| **Service target** | AWS Lambda function (returns a JSON greeting) |
| **Resource configuration** | `ARN` type → Aurora cluster, fronted by a dual-stack resource gateway in the provider VPC |
| **Custom domain name** | ❌ No (service uses the VPC Lattice-generated FQDN; Aurora uses its RDS endpoint) |
| **Access logging** | Two scopes: service scope (provider account) and service-network scope (consumer account), each to `/aws/vpclattice/<identifier>` |

## Implementation

This pattern is available for both IaC tools (CloudFormation + Terraform parity). Each implementation directory has its own README with the cross-account deployment order:

| IaC Tool | Location |
|----------|----------|
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) |
| **Terraform** | [`./terraform/`](./terraform/) (one module per account) |

## Testing Connectivity

After deploying both accounts, connect to a consumer EC2 instance and exercise the full cross-account flow: `curl` the Lambda **service**, read Aurora's credentials from Secrets Manager **cross-account**, and connect to Aurora through the **resource configuration** with those credentials.

<details>
<summary>Click to expand testing steps</summary>

> **Note**: Steps 1-4 run in the **Consumer account** and Step 5 in the **Provider account**. The service domain name, Aurora endpoint, and Aurora secret ARN are all **provider-account** deployment outputs.

#### Step 1: Connect to a consumer instance (Consumer account)

```bash
aws ec2-instance-connect ssh --instance-id <consumer-instance-id>
```

#### Step 2: Test the service over HTTPS (Consumer account)

```bash
curl https://<service-domain-name>
```

**Expected Response** (JSON):
```json
{
  "message": "Hello from Lambda Function!!"
}
```

#### Step 3: Read the Aurora credentials cross-account (Consumer account)

The Aurora master secret lives in the **provider account**; the consumer reads it through its Secrets Manager interface endpoint, authorized by the cross-account secret + KMS policies:

```bash
aws secretsmanager get-secret-value \
  --secret-id '<aurora-secret-arn>' \
  --query SecretString --output text --region <your-region>
```

**Expected Result**: a JSON document containing the `username` and `password`. This is proof that the cross-account secret (and its customer-managed KMS key) are readable from the consumer account.

#### Step 4: Connect to Aurora through the resource configuration (Consumer account)

Install the DNS + MySQL client tools (the consumer reaches the internet over IPv6 via the egress-only IGW), confirm the Aurora endpoint resolves through VPC Lattice, then connect with the credentials from Step 3:

```bash
sudo dnf install -y bind-utils mariadb105

# Resolves to the VPC Lattice VPC-resource range (129.224.0.x/17), not Aurora's real IP
dig +short <aurora-endpoint>

# Connect using the username/password retrieved in Step 3
mysql -h <aurora-endpoint> -u admin -p
```

**Expected Result**: `dig` returns an address in `129.224.0.x/17` (IPv6 `fd00:ec2:80::/64`), and `mysql` opens a session — the consumer reaches Aurora cross-account through the resource configuration and authenticates with the shared credentials.

</details>

## Cleanup

Tear down when finished to stop charges (consumer EC2 instances and CloudWatch access-log ingestion). Resources must be destroyed in **reverse account order** (consumer → provider); the exact per-account commands are in each implementation's README:

| IaC Tool | From | Teardown |
|----------|------|----------|
| **Terraform** | [`./terraform/`](./terraform/) | `terraform destroy` per account, in reverse order |
| **CloudFormation** | [`./cloudformation/`](./cloudformation/) | `delete-stack` per account, in reverse order |

Each account creates its own access-logging log group, removed with that account's teardown — no manual cleanup required.

## Next Steps

After successfully deploying this pattern:

1. **Test connectivity**: Follow the testing guide above to verify cross-account connectivity.
2. **Try the other model**: Compare with [Centralized Service Network](../1-centralized_service_network/), where a central team owns the network.
3. **Restrict access**: The shared service already uses `AWS_IAM` auth with an open policy. See the [Auth Policies & SigV4 toolkit](../../4-auth_policies/) to swap in a restrictive policy and sign requests with SigV4.
4. **Custom domains**: Add Route 53 private hosted zones + ACM certificates using the [VPC Lattice DNS Guidance](https://aws.amazon.com/solutions/guidance/amazon-vpc-lattice-automated-dns-configuration-on-aws/).
