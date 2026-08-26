<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
     SPDX-License-Identifier: MIT-0 -->

# VPC Lattice Blueprints — agent skill package

A portable [Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) that teaches an AI agent to reason about **Amazon VPC Lattice** and map user requests to the deployable patterns in this repository. The entry point is [`SKILL.md`](./SKILL.md); deeper guidance loads on demand from [`references/`](./references/).

## Install

The package is a plain directory: copy (or symlink) it into your agent runtime's skills location.

| Runtime | Location |
|---|---|
| Kiro CLI | `~/.kiro/skills/vpc-lattice-blueprints/` (global) or `.kiro/skills/` (workspace) |
| Claude Code | `~/.claude/skills/vpc-lattice-blueprints/` (user) or `.claude/skills/` (project) |
| Cursor | `.cursor/skills/vpc-lattice-blueprints/` |

Example (Kiro CLI, from a repository clone):

```bash
cp -r skills/vpc-lattice-blueprints ~/.kiro/skills/
```

No further configuration is needed: runtimes discover the skill from the `name` and `description` frontmatter in `SKILL.md`.

## How the skill finds repository content

The skill resolves the pattern catalog in this order (details in `SKILL.md` § Content resolution):

1. **Repository checkout available** — searches only the current working directory and its parents for a checkout containing both `blueprint.yaml` and `patterns/`, then uses that canonical content directly. It does not recursively search unrelated directories or choose another checkout elsewhere on disk.
2. **Standalone install** — if no checkout is available, uses the bundled snapshot [`assets/blueprint.yaml`](./assets/blueprint.yaml) for pattern selection; deploying a pattern still requires cloning this repository at the manifest source revision below.

The skill never derives a checkout path from its installed directory and never fetches content from the network on its own.

## Snapshot provenance

`assets/blueprint.yaml` is a **copy of the canonical `blueprint.yaml`** at the revision below. It is the manifest **source** revision — the skill package itself may have been added or updated after that release.

| Field | Value |
|---|---|
| Manifest source repository | https://github.com/aws-samples/amazon-vpc-lattice-blueprints |
| Manifest source revision | commit `5009984` (tag `v1.1.0`) |
| Manifest SHA-256 | `f00c0116b428bca887b4efa86ff81669a7a1ae0ef0eec8c00d2e4ec6b781cfe3` |
| Snapshot generated | 2026-08-26 |

Maintainers: when `blueprint.yaml` changes, regenerate the snapshot and update this table:

```bash
cp blueprint.yaml skills/vpc-lattice-blueprints/assets/blueprint.yaml
shasum -a 256 blueprint.yaml
```

CI verifies the snapshot matches the canonical manifest, so a stale snapshot fails the build rather than silently serving outdated patterns.

## Package layout

```
skills/vpc-lattice-blueprints/
├── SKILL.md                  # entry point: frontmatter + core playbook
├── README.md                 # this file
├── assets/
│   └── blueprint.yaml        # pinned catalog snapshot for standalone installs
├── evals/
│   └── evals.json            # evaluation corpus (trigger + task cases); structure-checked in CI, executed manually
├── scripts/
│   └── validate-package.py   # static package validation (run by pre-commit and CI)
└── references/               # loaded on demand by the agent
    ├── pattern-selection.md
    ├── architecting.md
    ├── deploy-and-test.md
    └── contributing-conventions.md
```
