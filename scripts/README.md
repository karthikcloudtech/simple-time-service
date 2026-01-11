# Scripts Documentation

## update-vpc-id.sh

Quick script to update VPC ID dynamically in AWS Load Balancer Controller ArgoCD application.

**Usage:**
```bash
CLUSTER_NAME=simple-time-service-prod AWS_REGION=us-east-1 ./scripts/update-vpc-id.sh
```

**What it does:**
1. Retrieves VPC ID dynamically by VPC name tag (e.g., `simple-time-service-vpc`)
2. Falls back to EKS cluster describe if VPC name lookup fails
3. Updates `gitops/argo-apps/aws-load-balancer-controller.yaml` automatically
4. No hardcoding - always gets current VPC ID from AWS

**Why dynamic?**
- VPC ID may change if infrastructure is recreated
- Avoids hardcoding values in Git
- Ensures accuracy by querying AWS directly

## install-eks-addons.sh

Main installation script that bootstraps ArgoCD and updates all dynamic values.

**Usage:**
```bash
CLUSTER_NAME=simple-time-service-prod AWS_REGION=us-east-1 bash scripts/install-eks-addons.sh
```

**Dynamic values updated:**
- ServiceAccount IAM role ARNs (from Terraform outputs)
- VPC ID for AWS Load Balancer Controller (by VPC name or EKS cluster)

**Note:** Always run this script before deploying ArgoCD applications to ensure all dynamic values are current.
