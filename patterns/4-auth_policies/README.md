# Amazon VPC Lattice - Auth Policies & SigV4 signing

This section is a **reference toolkit**, not a standalone deployable pattern. It gathers the assets you need to add **identity-based access control** to *any* of the blueprints in this repository:

- **[`policies/`](./policies/)**: copy-paste-ready auth policy documents, one per use case (allow an Org, OUs, an account, a specific IAM role, by tag, or filter by HTTP method/path/source VPC).
- **[`signing/`](./signing/)**: how request signing works and how to sign with **SigV4** and **SigV4A** (CLI + code examples).

In this repository, every pattern that exposes a **VPC Lattice service** ships its service networks and services with `auth_type = AWS_IAM` and the **completely open** policy in [`policies/open-allow-all.json`](./policies/open-allow-all.json) (allow all principals, including unsigned/anonymous callers). They behave exactly like an open service out of the box; to enforce access control you only swap the open policy for one of the restrictive policies here. No structural change to the pattern is required.

Access control is one of the main reasons to choose VPC Lattice over a traditional load balancer: a load balancer gates callers by **network reachability** (security groups, routes), while VPC Lattice adds an identity-based gate where an **auth policy** decides whether the *signed identity* may invoke the service. Because that capability is cross-cutting, it lives here once instead of as another end-to-end deployment: deploy any pattern in [section 1](../1-simple_architectures/), [section 2](../2-multi_account/), or [section 3](../3-advanced_architectures/), then apply this guidance to lock it down.

## How VPC Lattice authentication works

| Auth type | Behaviour |
|-----------|-----------|
| `NONE` | No authentication. Any caller that can reach the service on the network is allowed. |
| `AWS_IAM` | The service/network is guarded by an **auth policy** (an IAM resource-based policy). If no policy is attached, **all traffic is denied**. SigV4/SigV4A-signed requests are authorized against the policy; unsigned requests are treated as the **anonymous** principal and are allowed only if the policy explicitly permits anonymous access. |

Two scopes can carry a policy, and **both must allow** a request for it to succeed (deny-by-default at each layer):

- **Service network scope**: coarse-grained, applies to every service associated to the network. Best owned by a central/networking team.
- **Service scope**: fine-grained, applies to one service. Best owned by the application team.

## Applying an auth policy

The ready-to-use policy documents live in **[`policies/`](./policies/)** (see that folder's README for the full index and guidance on combining/layering them). Pick one, then attach it to a service network or service that uses `auth_type = AWS_IAM` — you are only swapping the policy document, not changing the pattern's structure.

> **Signing is required for identity-based policies.** Conditions that authorize by **IAM identity** — `aws:PrincipalOrgID`, `aws:PrincipalAccount`, `aws:PrincipalOrgPaths`, `aws:PrincipalTag`, or a `Principal` ARN — only work if the caller **SigV4- or SigV4A-signs** the request: an unsigned request carries no principal (it is anonymous), so those conditions can never match and the request is denied. **Request-attribute** conditions (`vpc-lattice-svcs:RequestMethod`, `RequestPath`, `SourceVpc`, `RequestHeader/*`, `RequestQueryString/*`) work for anonymous callers too, so you can filter on HTTP information without requiring authentication. See **[`signing/`](./signing/)** for how to sign.

### Terraform

Patterns that use the `aws-ia/amazon-vpc-lattice-module` set the policy inline via `auth_policy` on the `service_network` or `services` object. Load a snippet with `file()` (or inline it with `jsonencode`):

```hcl
service_network = {
  name        = "service-network-${var.identifier}"
  auth_type   = "AWS_IAM"
  auth_policy = file("${path.module}/../../4-auth_policies/policies/allow-organization.json")
}
```

Patterns that create the resources directly attach a separate `aws_vpclattice_auth_policy`:

```hcl
resource "aws_vpclattice_auth_policy" "service" {
  resource_identifier = aws_vpclattice_service.service.id
  policy              = file("${path.module}/policy.json")
}
```

### CloudFormation

Set `AuthType: AWS_IAM` and attach an `AWS::VpcLattice::AuthPolicy` (inline the JSON under `Policy`):

```yaml
ServiceAuthPolicy:
  Type: AWS::VpcLattice::AuthPolicy
  Properties:
    ResourceIdentifier: !Ref VpcLatticeService
    Policy:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal: "*"
          Action: vpc-lattice-svcs:Invoke
          Resource: "*"
          Condition:
            StringEquals:
              aws:PrincipalOrgID: o-xxxxxxxxxx
```

### AWS CLI

```bash
# Minify first - put-auth-policy rejects newlines/blank lines
jq -c . policies/allow-organization.json > policy.min.json
aws vpc-lattice put-auth-policy \
  --resource-identifier <sn-... or svc-...> \
  --policy file://policy.min.json
```

## Signing requests

Any policy that authorizes by **IAM identity** (Org, OUs, account, role, principal tag) requires the caller to **SigV4- or SigV4A-sign** the request for the `vpc-lattice-svcs` signing name — unsigned requests are anonymous and will be denied by those policies. See **[`signing/`](./signing/)** for how it works, the SigV4 vs SigV4A trade-off, an `awscurl` recipe, and runnable Python examples.

## Observing auth decisions

Every pattern enables VPC Lattice **access logging** by default, and because services use `AWS_IAM` auth, each log entry records the authenticated principal and the auth decision:

```bash
aws logs tail /aws/vpclattice/<identifier-or-stack-name> --follow --region <region>
```

Each request appears as its own entry (`Allowed` with a `200`, or `Denied` with a `403`) so you can confirm exactly which identity was allowed or denied and why.
