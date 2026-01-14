# Scripts Documentation

## install-eks-addons.sh

Main installation script that bootstraps ArgoCD and updates all dynamic values.

**Usage:**
```bash
CLUSTER_NAME=simple-time-service-prod AWS_REGION=us-east-1 bash scripts/install-eks-addons.sh
```

**What it does:**
1. Installs AWS Load Balancer Controller directly via Helm (with VPC ID retrieved by VPC name)
2. Bootstraps ArgoCD
3. Updates ServiceAccount YAML files with IAM role ARNs from Terraform outputs
4. Applies ArgoCD Applications for all other addons

**Dynamic values handled:**
- VPC ID for AWS Load Balancer Controller: Retrieved by environment-specific VPC name (e.g., `simple-time-service-vpc-prod`) or falls back to EKS cluster
- ServiceAccount IAM role ARNs: Retrieved from Terraform outputs and updated in YAML files

**Note:** AWS Load Balancer Controller is installed directly via Helm (not via ArgoCD) because the Helm chart requires VPC ID, which cannot be set via VPC name.
