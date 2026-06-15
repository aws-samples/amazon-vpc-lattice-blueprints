# Signing requests (SigV4 / SigV4A)

**Signing** is how a caller proves its IAM identity to VPC Lattice. It's required only when a service or service network uses `auth_type = AWS_IAM` **and** its [auth policy](../policies/) authorizes by IAM identity (or otherwise denies anonymous); then the request must be signed so VPC Lattice can identify the principal and evaluate the policy against it. With the open baseline (or any policy that allows anonymous and filters only on request attributes), an unsigned request still works.

Signing uses [AWS Signature Version 4](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html) — either **SigV4** (single Region) or **SigV4A** (multi-Region).

## How it works

- **Signing name**: `vpc-lattice-svcs`. The signer uses your IAM credentials (environment, EC2 instance role via IMDS, ECS task role, Lambda execution role, etc.) to compute a signature that VPC Lattice validates and maps to a principal.
- **No payload signing**: VPC Lattice does not support signed payloads. Every signed request must include the header `x-amz-content-sha256: UNSIGNED-PAYLOAD`.
- **The signed identity is what the policy sees**: condition keys like `aws:PrincipalOrgID`, `aws:PrincipalAccount`, and `aws:PrincipalTag`, or a `Principal` ARN, are only populated for signed requests. An unsigned request is the **anonymous** principal and can satisfy only a policy that explicitly allows anonymous.

## SigV4 vs SigV4A

| | SigV4 | SigV4A |
|---|-------|--------|
| Scope | A single Region | A **Region set** (`*` = all Regions) |
| When to use | The common case: you call the service in one Region | The same signed request may be accepted in more than one Region (multi-Region / active-active designs) |
| Python signer | `crt.auth.CrtSigV4Auth(creds, "vpc-lattice-svcs", "<region>")` | `crt.auth.CrtSigV4AsymAuth(creds, "vpc-lattice-svcs", "*")` |

VPC Lattice accepts requests signed with either. Start with SigV4 unless you specifically need multi-Region signing.

## How to sign

### From the CLI / an EC2 instance — `awscurl`

[`awscurl`](https://github.com/okigan/awscurl) signs automatically from the ambient credentials, so it is the quickest way to test:

```bash
# Install on Amazon Linux 2023
sudo dnf install -y python3-pip && pip3 install awscurl

# SigV4-signed GET (picks up the instance role from IMDS)
awscurl --service vpc-lattice-svcs --region <region> https://<service-domain-name>
```

### From application code — Python

Runnable examples are included here; install the dependencies (`pip install botocore awscrt requests`) and set the endpoint/Region:

- [`sigv4_request.py`](./sigv4_request.py) — single-Region SigV4.
- [`sigv4a_request.py`](./sigv4a_request.py) — multi-Region SigV4A.

### Other languages

The AWS documentation has equivalent SigV4 and SigV4A examples for **Java**, **Node.js**, and **Go** (including gRPC): [SigV4 authenticated requests for Amazon VPC Lattice](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sigv4-authenticated-requests.html). In every SDK the recipe is the same: sign for the `vpc-lattice-svcs` signing name, disable payload signing, and send `x-amz-content-sha256: UNSIGNED-PAYLOAD`.

## Testing the allow/deny outcome

From a consumer with the open baseline swapped for a restrictive policy:

```bash
# Resolve the service through VPC Lattice (link-local 169.254.171.x)
dig +short <service-domain-name>

# Signed as an ALLOWED identity -> 200
awscurl --service vpc-lattice-svcs --region <region> https://<service-domain-name>

# Unsigned, or signed by a NON-allowed identity -> 403 AccessDeniedException
curl -i https://<service-domain-name>
```

Auth decisions (allow `200` / deny `403`) and the authenticated principal are recorded in the service's/network's [access logs](https://docs.aws.amazon.com/vpc-lattice/latest/ug/monitoring-access-logs.html).
