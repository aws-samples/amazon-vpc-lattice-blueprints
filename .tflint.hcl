# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Repository TFLint configuration for Amazon VPC Lattice Blueprints.
#
# Used by the static-only CI (.github/workflows/ci.yml) and by local pre-commit.
# The AWS ruleset is enabled so `tflint` checks for invalid AWS resource
# arguments, deprecated syntax, and naming issues across every pattern's
# Terraform. `tflint --init` installs the plugin declared below; the CI passes
# this file via `--config` so every pattern dir is linted with the same ruleset.

config {
  # Lint only the module in the working directory; child modules pulled into
  # .terraform/ are validated transitively by their own pattern roots.
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# ---------------------------------------------------------------------------
# Justified rule suppression.
#
# aws_lambda_function_invalid_runtime: the AWS ruleset pinned above (v0.31.0)
# predates the GA "python3.14" managed Lambda runtime and therefore reports it
# as invalid. python3.14 is a deliberate, documented repo-wide pin and is a
# real, generally available AWS Lambda runtime. The finding is a stale-ruleset
# false positive, not a code defect, so the rule is disabled until the ruleset
# pin is raised to a version that recognizes python3.14.
# ---------------------------------------------------------------------------
rule "aws_lambda_function_invalid_runtime" {
  enabled = false
}
