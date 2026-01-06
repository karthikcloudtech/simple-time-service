# Quick Start Guide - Daily Practice Workflow

## Complete Setup (First Time or After Destroy)

```bash
# 1. Navigate to Terraform directory
cd infra/environments/prod

# 2. Initialize Terraform (if needed)
terraform init

# 3. Apply everything (creates infrastructure + bootstraps ArgoCD)
terraform apply -auto-approve

# 4. Wait for ArgoCD to sync (check status)
kubectl get applications -n argocd -w

# 5. Verify everything is ready
kubectl get pods --all-namespaces
```

**What happens automatically:**
1. ✅ Terraform creates VPC, EKS cluster, IAM roles
2. ✅ Terraform installs EBS CSI Driver addon
3. ✅ Script bootstraps ArgoCD
4. ✅ Script creates ServiceAccounts with IAM annotations
5. ✅ Script applies ArgoCD Applications
6. ✅ ArgoCD syncs all Helm charts
7. ✅ Everything is ready!

## Daily Destroy & Recreate

```bash
# Destroy everything
cd infra/environments/prod
terraform destroy -auto-approve

# Recreate everything (same as setup)
terraform apply -auto-approve
```

**That's it!** Everything recreates automatically. No manual steps needed.

## Check Status

```bash
# Infrastructure
terraform output

# Kubernetes cluster
kubectl get nodes
kubectl get pods --all-namespaces

# ArgoCD Applications
kubectl get applications -n argocd
argocd app list

# Specific application
kubectl get application aws-load-balancer-controller -n argocd
```

## Resource Management Summary

| Resource Type | Managed By | Location |
|--------------|------------|----------|
| VPC, Subnets | Terraform | `infra/terraform/modules/vpc/` |
| EKS Cluster | Terraform | `infra/terraform/modules/eks/` |
| IAM Roles | Terraform | `infra/terraform/modules/eks/iam_roles.tf` |
| EBS CSI Addon | Terraform | `infra/terraform/modules/eks/main.tf` |
| ServiceAccounts | ArgoCD/YAML | `gitops/serviceaccounts/` |
| Helm Charts | ArgoCD | `gitops/argo-apps/*.yaml` |
| Applications | ArgoCD | `gitops/apps/` |

## Troubleshooting

### ArgoCD Not Syncing

```bash
# Check ArgoCD server status
kubectl get pods -n argocd

# Check application status
kubectl get applications -n argocd
kubectl describe application APP_NAME -n argocd

# Force sync
argocd app sync APP_NAME
```

### ServiceAccount Missing IAM Annotation

```bash
# Check annotation
kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml

# Get role ARN from Terraform
terraform output -raw aws_load_balancer_controller_role_arn

# Update manually if needed
kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=<ROLE_ARN> --overwrite
```

### Pods Can't Start

```bash
# Check pod status
kubectl get pods -n NAMESPACE
kubectl describe pod POD_NAME -n NAMESPACE
kubectl logs POD_NAME -n NAMESPACE

# Common issues:
# - ServiceAccount missing IAM annotation
# - IAM role doesn't exist
# - Resource limits too low
```

## Key Files

- **Terraform Config:** `infra/environments/prod/`
- **Install Script:** `scripts/install-eks-addons.sh`
- **ArgoCD Apps:** `gitops/argo-apps/*.yaml`
- **ServiceAccounts:** `gitops/serviceaccounts/*.yaml`
- **Best Practices:** `INSTALLATION_BEST_PRACTICES.md`

## Next Steps

1. Read `INSTALLATION_BEST_PRACTICES.md` for detailed explanation
2. Customize Helm chart versions in `gitops/argo-apps/*.yaml`
3. Update application manifests in `gitops/apps/`
4. Practice destroy/recreate workflow daily

