#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Chat with a consumer agent: ./chat.sh ecs (agent-ecs, through ECS Exec) or ./chat.sh runtime (agent-runtime)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

AGENT="${1:-ecs}"
AGENT_RUNTIME_ARN=$(terraform output -raw agent_runtime_arn)

# The AWS CLI credentials must be for the account the pattern is deployed in
DEPLOYED_ACCOUNT=$(echo "${AGENT_RUNTIME_ARN}" | cut -d':' -f5)
CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ "${CALLER_ACCOUNT}" != "${DEPLOYED_ACCOUNT}" ]; then
  echo "Your AWS CLI credentials are for account ${CALLER_ACCOUNT}, but the pattern is deployed in ${DEPLOYED_ACCOUNT}." >&2
  echo "Use credentials for ${DEPLOYED_ACCOUNT} (for example, export AWS_PROFILE=<profile>) and run this again." >&2
  exit 1
fi

case "${AGENT}" in
  ecs)
    python3 ../../applications/chat.py ecs --cluster "$(terraform output -raw ecs_cluster)" \
      --service "$(terraform output -raw agent_ecs_service)" --region "$(echo "${AGENT_RUNTIME_ARN}" | cut -d':' -f4)"
    ;;
  runtime)
    python3 ../../applications/chat.py runtime --arn "${AGENT_RUNTIME_ARN}"
    ;;
  *)
    echo "Usage: ./chat.sh ecs|runtime" >&2
    exit 1
    ;;
esac
