#!/bin/bash
# Quick script to update VPC ID in AWS Load Balancer Controller ArgoCD application
# Gets VPC ID by VPC name (tag) or from EKS cluster via AWS API

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Updating VPC ID (by VPC name or EKS cluster)..."
echo "Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
echo ""

# Source the main script to get the update function
source "$SCRIPT_DIR/install-eks-addons.sh"

# Run the update function
TERRAFORM_DIR="${TERRAFORM_DIR:-infra/environments/prod}" update_serviceaccount_annotations

echo ""
echo "Done! VPC ID has been updated in gitops/argo-apps/aws-load-balancer-controller.yaml"
