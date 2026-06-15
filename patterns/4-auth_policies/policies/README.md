# Auth policy snippets

Copy-paste-ready VPC Lattice auth policy documents, one per use case. Each file is a complete policy (a `Version` + `Statement` document) that you attach to a **service network** or a **service** that uses `auth_type = AWS_IAM`. Replace the placeholder values (`111122223333`, `o-xxxxxxxxxx`, `vpc-...`, role ARNs, tag keys) with your own.

All snippets use the action `vpc-lattice-svcs:Invoke`. Authorization is **deny-by-default**: anything a statement doesn't explicitly allow is denied. See the [section README](../README.md) for how to attach a policy (Terraform / CloudFormation / CLI) and how to sign requests.

| File | Use case | Gate | Signed request required? |
|------|----------|------|--------------------------|
| [`open-allow-all.json`](./open-allow-all.json) | The repo baseline: allow everything, including unsigned/anonymous callers | none (open) | No |
| [`require-authentication.json`](./require-authentication.json) | Allow any caller, but reject unsigned/anonymous requests | authentication | Yes |
| [`allow-iam-role.json`](./allow-iam-role.json) | Allow a single IAM role (principal ARN) | IAM identity | Yes |
| [`allow-account.json`](./allow-account.json) | Allow every principal in one AWS account | IAM identity (`aws:PrincipalAccount`) | Yes |
| [`allow-organization.json`](./allow-organization.json) | Allow every principal in an AWS Organization | IAM identity (`aws:PrincipalOrgID`) | Yes |
| [`allow-organizational-units.json`](./allow-organizational-units.json) | Allow principals under specific OUs | IAM identity (`aws:PrincipalOrgPaths`) | Yes |
| [`allow-by-principal-tag.json`](./allow-by-principal-tag.json) | Allow callers carrying a specific principal tag | IAM identity (`aws:PrincipalTag`) | Yes |
| [`filter-by-http-method-path.json`](./filter-by-http-method-path.json) | Allow only certain HTTP methods/paths (e.g. read-only `GET /public/*`) | request attributes | No |
| [`filter-by-source-vpc.json`](./filter-by-source-vpc.json) | Allow only requests originating from a specific VPC | request origin (`vpc-lattice-svcs:SourceVpc`) | No |

## Combining statements

Real policies usually combine these. For example, "anyone in the Organization, authenticated, but only `GET`s" is the `allow-organization.json` statement plus the `RequestMethod` condition from `filter-by-http-method-path.json`. You can also layer scopes: a broad policy at the **service-network** scope (owned by a networking team) and a narrow one at the **service** scope (owned by the app team); because both layers must allow, the effective permission is the intersection.

## A note on identity vs request attributes

- **IAM-identity** conditions (`aws:PrincipalOrgID`, `aws:PrincipalAccount`, `aws:PrincipalOrgPaths`, `aws:PrincipalTag`, or a `Principal` ARN) require the request to be **SigV4-signed**; an unsigned request has no principal and is denied.
- **Request-attribute** conditions (`vpc-lattice-svcs:RequestMethod`, `RequestPath`, `SourceVpc`, `RequestHeader/*`, `RequestQueryString/*`) are available even for anonymous callers, so you can filter on HTTP information without requiring authentication.

> **CLI note**: `aws vpc-lattice put-auth-policy` requires the policy as a single line without blank lines. These files are pretty-printed for readability; minify them (e.g. `jq -c . file.json`) before passing to the CLI. Terraform (`jsonencode`/`file()`) and CloudFormation (inline `Policy`) accept them as-is.
