<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# Conventions when editing or extending patterns

Read this **only** when modifying or adding patterns in the repository. [`CONVENTIONS.md`](../../../CONVENTIONS.md) is the authoritative contract — this file summarizes what an agent must respect; when in doubt, or for pinned tool and dependency versions, defer to it and to [`CONTRIBUTING.md`](../../../CONTRIBUTING.md).

- **IaC parity:** every published deployable pattern ships **both** CloudFormation and Terraform, except where `blueprint.yaml` declares otherwise (EKS is Terraform-only: Helm + Kubernetes Gateway API CRDs can't be represented cleanly in pure CloudFormation). The manifest is the source of truth; never claim an implementation that doesn't exist.
- **Naming:** `"<role>-<thing>-${var.identifier}"`, hyphens not underscores, identifier suffix last (security groups: `"<vpc>-<purpose>-security-group-${var.identifier}"`).
- **Version pins:** module and provider versions, the Lambda runtime, and the Terraform core floor are pinned uniformly across patterns — take current values from `CONVENTIONS.md`, do not hardcode them from memory.
- **Generated docs:** each Terraform pattern's `README.md` is **generated** by terraform-docs from `.header.md` — never hand-edit it; edit `.header.md` and regenerate.
- **License header:** MIT-0 header at the top of every source file.
- **Access logging on by default:** service network/service patterns create a CloudWatch Logs group `/aws/vpclattice/<identifier>`, destroyed on teardown.
- **Auth default:** every service-exposing pattern ships its service network and service with `AuthType = AWS_IAM` and a **completely open** (allow-all, including anonymous) auth policy — unchanged behavior out of the box, but "auth-ready". Resource-only patterns keep `NONE` (auth policies do not apply to VPC resources).
- **Secure defaults stay on:** IMDSv2 required, encrypted EBS root volumes, HTTPS listeners, RDS managed master password in Secrets Manager. Don't weaken these.
- **Security-scan suppressions** (Checkov) require a justification (`.checkov.yaml` `skip-check` with a comment, or inline `#checkov:skip=...:reason`). Suppress only deliberate demo simplifications or confirmed false positives.
- **Local checks:** run `pre-commit run --all-files` before opening a PR — it mirrors the CI workflow (terraform fmt/validate/tflint/terraform-docs drift, cfn-lint, checkov, lychee link check, hygiene hooks).
