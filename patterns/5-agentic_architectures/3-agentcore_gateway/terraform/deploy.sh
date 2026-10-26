#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Deploy the pattern in three steps:
# 1. Create the Amazon ECR repositories.
# 2. Build and push the agent, triage and tickets images (ARM64: AgentCore Runtime runs ARM64 containers only).
# 3. Deploy the rest of the pattern, then submit the AWS Agent Registry records so they become discoverable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="${SCRIPT_DIR}/../../applications"
cd "${SCRIPT_DIR}"

echo "Step 1: Amazon ECR repositories"
terraform init
terraform apply -target=aws_ecr_repository.agent -target=aws_ecr_repository.triage -target=aws_ecr_repository.tickets -auto-approve

echo "Step 2: Build and push the images (linux/arm64)"
AGENT_REPOSITORY=$(terraform output -json repository_urls | python3 -c "import json,sys;print(json.load(sys.stdin)['agent'])")
TRIAGE_REPOSITORY=$(terraform output -json repository_urls | python3 -c "import json,sys;print(json.load(sys.stdin)['triage'])")
TICKETS_REPOSITORY=$(terraform output -json repository_urls | python3 -c "import json,sys;print(json.load(sys.stdin)['tickets'])")
REGISTRY_HOST="${AGENT_REPOSITORY%%/*}"
REGION=$(echo "${REGISTRY_HOST}" | cut -d'.' -f4)

aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY_HOST}"
docker buildx build --platform linux/arm64 --provenance=false -t "${AGENT_REPOSITORY}:latest" --push "${APPLICATIONS_DIR}/agent"
docker buildx build --platform linux/arm64 --provenance=false -t "${TRIAGE_REPOSITORY}:latest" --push "${APPLICATIONS_DIR}/triage"
docker buildx build --platform linux/arm64 --provenance=false -t "${TICKETS_REPOSITORY}:latest" --push "${APPLICATIONS_DIR}/mcp_tickets"

echo "Step 3: Deploy the pattern"
terraform apply -auto-approve

echo "Submitting the AWS Agent Registry records for approval (auto-approved by the registry)"
REGISTRY_ID=$(terraform output -json registry | python3 -c "import json,sys;print(json.load(sys.stdin)['registry_id'])")
for RECORD_ID in $(terraform output -json registry | python3 -c "import json,sys;print(' '.join(json.load(sys.stdin)['record_ids']))"); do
  aws agent-registry-control submit-registry-record-for-approval --registry-id "${REGISTRY_ID}" --record-id "${RECORD_ID}" --region "${REGION}" || true
done

echo "Deployment completed."
