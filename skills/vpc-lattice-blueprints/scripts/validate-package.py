#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Static validation for the vpc-lattice-blueprints agent skill package.

Checks (all static, no network, no AWS credentials, stdlib only):
  1. SKILL.md exists and starts with YAML frontmatter containing `name` and
     `description`; `name` matches ^[a-z0-9-]+$, is <= 64 chars, and equals
     the package directory name; `description` is non-empty and <= 1024 chars.
  2. Every relative markdown link and every `references/...` path mentioned
     in SKILL.md, README.md, and every references/*.md file resolves to an
     existing file.
  3. assets/blueprint.yaml is byte-identical (SHA-256) to the canonical
     repository blueprint.yaml, and the package README publishes that hash.
  4. evals/evals.json parses; case IDs are unique, trigger cases carry an
     allowed `expect` value and non-empty prompts, and task cases carry
     non-empty assertion lists.

Exit code 0 on success, 1 with per-check error messages on failure.
Run from anywhere: paths are resolved relative to this script's location.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent.parent          # skills/vpc-lattice-blueprints
REPO_ROOT = PKG_DIR.parent.parent                         # repository root
ALLOWED_EXPECT = {"activate", "no_activation", "activate_and_clarify"}

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def parse_frontmatter(text: str) -> dict:
    """Minimal frontmatter parser for simple `key: value` pairs (no PyYAML dep).

    Understands single-line values, folded/literal block scalars
    (`key: >` / `key: |`, optionally with a chomping indicator), and
    space/tab-indented continuation lines. Any other YAML construct
    (lists, nested maps, comments) is skipped rather than rejected:
    this validator checks only the fields it models (`name`,
    `description`) and must not fail legitimate frontmatter it does
    not understand.
    """
    if not text.startswith("---\n"):
        err("SKILL.md: file must begin with YAML frontmatter ('---' on line 1)")
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        err("SKILL.md: frontmatter is not closed with '---' on its own line")
        return {}
    fields: dict[str, str] = {}
    key = None
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            key = m.group(1)
            if key in fields:
                err(f"SKILL.md frontmatter: duplicate field '{key}'")
            value = m.group(2).strip()
            if re.fullmatch(r"[>|][+-]?", value):
                value = ""  # block scalar: the body arrives as indented lines below
            fields[key] = value
        elif key and line.startswith((" ", "\t")):
            fields[key] = (fields[key] + " " + line.strip()).strip()
        # Anything else is a YAML construct this parser does not model:
        # tolerate it silently instead of erroring.
    return fields


def check_frontmatter() -> None:
    skill_md = PKG_DIR / "SKILL.md"
    if not skill_md.is_file():
        err("SKILL.md is missing")
        return
    fields = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
    name = fields.get("name", "")
    desc = fields.get("description", "")
    if not name:
        err("SKILL.md frontmatter: 'name' is missing or empty")
    else:
        if not re.fullmatch(r"[a-z0-9-]+", name):
            err(f"SKILL.md frontmatter: name '{name}' must match ^[a-z0-9-]+$")
        if len(name) > 64:
            err(f"SKILL.md frontmatter: name is {len(name)} chars (max 64)")
        if name != PKG_DIR.name:
            err(f"SKILL.md frontmatter: name '{name}' must equal the package directory name '{PKG_DIR.name}'")
    if not desc:
        err("SKILL.md frontmatter: 'description' is missing or empty")
    elif len(desc) > 1024:
        err(f"SKILL.md frontmatter: description is {len(desc)} chars (max 1024)")


def check_relative_paths() -> None:
    link_re = re.compile(r"\]\(([^)]+)\)")
    ref_re = re.compile(r"`(references/[A-Za-z0-9._/-]+)`")
    docs: list[tuple[str, Path]] = [(name, PKG_DIR / name) for name in ("SKILL.md", "README.md")]
    docs += [
        (str(p.relative_to(PKG_DIR)), p)
        for p in sorted((PKG_DIR / "references").glob("*.md"))
    ]
    for doc, path in docs:
        if not path.is_file():
            err(f"{doc} is missing")
            continue
        text = path.read_text(encoding="utf-8")
        targets: set[Path] = set()
        for raw in link_re.findall(text):
            target = raw.split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:", "/")):
                continue
            targets.add((path.parent / target).resolve())
        for rel in ref_re.findall(text):
            targets.add((PKG_DIR / rel).resolve())
        for target in sorted(targets):
            if not target.exists():
                err(f"{doc}: referenced path '{target}' does not exist")


def check_snapshot_sync() -> None:
    canonical = REPO_ROOT / "blueprint.yaml"
    snapshot = PKG_DIR / "assets" / "blueprint.yaml"
    readme = PKG_DIR / "README.md"
    if not canonical.is_file():
        err("canonical blueprint.yaml not found at the repository root")
        return
    if not snapshot.is_file():
        err("assets/blueprint.yaml snapshot is missing")
        return
    h_canonical = hashlib.sha256(canonical.read_bytes()).hexdigest()
    h_snapshot = hashlib.sha256(snapshot.read_bytes()).hexdigest()
    if h_canonical != h_snapshot:
        err(
            "assets/blueprint.yaml has drifted from the canonical blueprint.yaml "
            f"(canonical {h_canonical[:12]}..., snapshot {h_snapshot[:12]}...). "
            "Regenerate it: cp blueprint.yaml skills/vpc-lattice-blueprints/assets/blueprint.yaml "
            "and update the provenance table in the package README."
        )
    if not readme.is_file():
        err("README.md is missing; cannot validate snapshot provenance")
        return
    match = re.search(
        r"\|\s*Manifest SHA-256\s*\|\s*`([0-9a-f]{64})`\s*\|",
        readme.read_text(encoding="utf-8"),
    )
    if not match:
        err("README.md: Manifest SHA-256 provenance value is missing or malformed")
    elif match.group(1) != h_snapshot:
        err(
            "README.md: Manifest SHA-256 does not match assets/blueprint.yaml "
            f"(README {match.group(1)[:12]}..., snapshot {h_snapshot[:12]}...)"
        )


def check_evals() -> None:
    evals_path = PKG_DIR / "evals" / "evals.json"
    if not evals_path.is_file():
        err("evals/evals.json is missing")
        return
    try:
        data = json.loads(evals_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        err(f"evals/evals.json: invalid JSON ({exc})")
        return
    trigger_cases = data.get("trigger_cases", [])
    task_cases = data.get("task_cases", [])
    if not trigger_cases:
        err("evals/evals.json: no trigger_cases defined")
    if not task_cases:
        err("evals/evals.json: no task_cases defined")
    seen_ids: set[str] = set()
    for kind, cases in (("trigger", trigger_cases), ("task", task_cases)):
        for case in cases:
            cid = case.get("id", "")
            if not cid:
                err(f"evals {kind} case: missing id")
            elif cid in seen_ids:
                err(f"evals case {cid}: duplicate id")
            else:
                seen_ids.add(cid)
            if not case.get("prompt", "").strip():
                err(f"evals {kind} case {cid or '<no id>'}: empty prompt")
            if kind == "trigger" and case.get("expect") not in ALLOWED_EXPECT:
                err(f"evals trigger case {cid or '<no id>'}: 'expect' must be one of {sorted(ALLOWED_EXPECT)}")
            if kind == "task" and not case.get("assertions"):
                err(f"evals task case {cid or '<no id>'}: assertions list is empty")


def main() -> int:
    check_frontmatter()
    check_relative_paths()
    check_snapshot_sync()
    check_evals()
    if errors:
        print(f"validate-package: {len(errors)} error(s):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("validate-package: all checks passed "
          "(frontmatter, referenced paths, snapshot provenance, evals structure).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
