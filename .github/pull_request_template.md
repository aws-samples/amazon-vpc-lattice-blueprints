## Description

<!-- What does this change do, and why? Link any related issue with "Closes #123". -->

## Where is the change?

<!-- Check every area this PR touches, then complete the matching section(s) below. -->

- [ ] `patterns/` — a **new** deployable pattern
- [ ] `patterns/` — an **update** to an existing pattern
- [ ] `patterns/4-auth_policies/` — the auth policies and signing reference toolkit
- [ ] `SKILLS.md` or `skills/` — agent knowledge
- [ ] Repository docs or CI only (`README.md`, `CONVENTIONS.md`, `CONTRIBUTING.md`, `AGENTS.md`, `llms.txt`, `.github/`)

## Checklist for every change

<!-- CI enforces most of this automatically. Running the checks locally first is faster than round-tripping through CI. -->

- [ ] I have read [CONVENTIONS.md](../CONVENTIONS.md) and this change conforms to it.
- [ ] `pre-commit run --all-files` passes locally (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] I reviewed advisory Checkov findings, fixed applicable issues, and included a justification for every new suppression (baseline comment or inline `:reason`).
- [ ] Any pattern or page added, removed, or renamed is reflected in [`llms.txt`](../llms.txt).
- [ ] No file or heading linked from outside this repository was renamed or moved (`llms.txt`, the `README.md` anchors `#why-vpc-lattice` and `#key-concepts`, category and pattern READMEs) — or, if one was, the pull request description calls it out.
- [ ] If a convention or a validation step changed, [`AGENTS.md`](../AGENTS.md) reflects it.

## If the change adds or updates a pattern

<!-- Formatting, generated READMEs, and lint are already enforced by the pre-commit suite above — no separate checkboxes needed. -->

- [ ] CloudFormation and Terraform implementations are in parity, or the exception is stated in the pattern README and the pattern table (as for EKS).
- [ ] The catalogs agree, per [Catalog and agent-index synchronization](../CONVENTIONS.md#9-catalog-and-agent-index-synchronization): the `README.md` pattern table, the category README, `llms.txt`, and the skill package's `references/pattern-selection.md`.
- [ ] Version pins follow [CONVENTIONS.md](../CONVENTIONS.md#3-version-pins); any pattern-specific floor is listed there.
- [ ] The versions the changed patterns use are the newest compatible, tested releases, or this pull request says which newer release was held back and why.
- [ ] Every new IaC source file carries the MIT-0 license header.
- [ ] Secure defaults are kept: IMDSv2, encrypted EBS root volumes, access logging on by default, and `AWS_IAM` with an open auth policy on service-exposing patterns.
- [ ] The pattern README's **Testing**, **Cost**, and **Cleanup** sections reflect any resource changes.

## If the change is in `patterns/4-auth_policies/`

- [ ] Each policy remains a complete, copy-paste document for one use case, listed in the `policies/README.md` table.
- [ ] Signing examples still run against the documented signing name (`vpc-lattice-svcs`).

## If the change is in `SKILLS.md` or `skills/`

- [ ] Shared facts match [CONVENTIONS.md](../CONVENTIONS.md): the DNS ranges and the EKS parity exception.
- [ ] `python3 skills/vpc-lattice-blueprints/scripts/validate-package.py` passes.
- [ ] I piloted the change with an agent — gave it the updated skill and a representative question — and its behaviour matched the intent. Describe the pilot under **Testing**.

## Testing

<!-- How was this verified? If a pattern was deployed, say in which Region and account setup, and what was checked (associations, DNS resolution, connectivity tests, teardown). If it was only statically validated, say so. If agent knowledge changed, describe the pilot: the prompt, the model/agent used, and what the response got right. -->
