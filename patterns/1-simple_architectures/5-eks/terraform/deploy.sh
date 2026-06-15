#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Amazon EKS (VPC Lattice) Deployment Script"
echo "=========================================="
echo ""

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}"

# Step 1: Create the ECR repository first (the sample app image must exist before
# the workload is applied). The EKS resources are raw aws_eks_* (no community
# module), so a targeted apply is safe here.
echo "Step 1: Creating the ECR repository..."
terraform init
terraform apply -target=aws_ecr_repository.eks_app -auto-approve

# Step 2: Resolve the ECR repository URL + region/account.
REPOSITORY_URL=$(terraform output -raw repository_url)
REGION=$(echo "${REPOSITORY_URL}" | cut -d'.' -f4)
AWS_ACCOUNT_ID=$(echo "${REPOSITORY_URL}" | cut -d'.' -f1)
echo "ECR repository: ${REPOSITORY_URL}"

# Step 3: Build and push the sample app image. EKS Auto Mode runs Graviton
# (arm64) nodes, so always build for linux/arm64.
echo ""
echo "Step 3: Building and pushing the image (linux/arm64)..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build --platform linux/arm64 -t "${REPOSITORY_URL}:latest" "${SCRIPT_DIR}/../application"
docker push "${REPOSITORY_URL}:latest"

# Step 4: Deploy the rest of the pattern (cluster, controller, Gateway API
# manifest, consumer VPC). The manifest apply/teardown stays Terraform-managed.
echo ""
echo "Step 4: Deploying the remaining infrastructure..."
terraform apply -auto-approve

echo ""
echo "=========================================="
echo "Deployment completed successfully!"
echo "=========================================="
