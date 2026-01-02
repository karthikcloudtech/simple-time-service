# Migration Guide: Script to ArgoCD GitOps

This guide explains how to migrate from the bash script (`scripts/install-eks-addons.sh`) to ArgoCD GitOps management.

## Overview

**Before:** All EKS addons installed via bash script with Helm commands
**After:** All EKS addons managed via ArgoCD GitOps with declarative Application manifests

## Benefits

1. **Version Control:** All configurations tracked in Git
2. **Easy Rollbacks:** Revert via Git history
3. **Self-Healing:** ArgoCD automatically corrects manual changes
4. **Dependency Management:** ArgoCD handles installation order
5. **Consistency:** Same state across all environments
6. **Audit Trail:** All changes visible in Git commits

## Migration Steps

### Step 1: Verify Prerequisites

```bash
# Ensure Terraform is applied (IAM roles exist)
terraform -chdir=infra/environments/prod output

# Verify EKS cluster is running
kubectl cluster-info

# Check current installations (if any)
helm list --all-namespaces
kubectl get pods --all-namespaces
```

### Step 2: Bootstrap ArgoCD

```bash
# Run bootstrap script (installs ArgoCD only)
./scripts/install-eks-addons.sh

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access UI (optional)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Step 3: Apply ArgoCD Applications

```bash
# Apply all ArgoCD Application manifests
kubectl apply -f gitops/argo-apps/*.yaml

# Verify applications are created
kubectl get application -n argocd
```

### Step 4: Configure IAM Role Annotations

```bash
# AWS Load Balancer Controller
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn)
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite

# Cert-Manager
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw cert_manager_role_arn)
kubectl annotate serviceaccount cert-manager \
  -n cert-manager \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite
kubectl rollout restart deployment cert-manager -n cert-manager
kubectl rollout restart deployment cert-manager-webhook -n cert-manager
kubectl rollout restart deployment cert-manager-cainjector -n cert-manager

# Cluster Autoscaler
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw cluster_autoscaler_role_arn)
kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite
```

### Step 5: Verify Installation

```bash
# Check ArgoCD application status
argocd app list

# Check specific application
argocd app get metrics-server
argocd app get prometheus-stack

# Verify Helm releases
helm list --all-namespaces

# Check pods
kubectl get pods --all-namespaces
```

## What Changed

### Old Script (`install-eks-addons.sh`)
- Installed all addons via Helm commands
- Managed IAM role creation (now in Terraform)
- Handled installation order manually
- Required manual updates for chart versions

### New Approach
- **Bootstrap Script:** Only installs ArgoCD (`install-eks-addons.sh`)
- **ArgoCD Applications:** Declarative manifests in `gitops/argo-apps/`
- **Terraform:** Manages IAM roles (already done)
- **GitOps:** ArgoCD manages all Helm charts

## File Structure

```
gitops/
├── argo-apps/              # ArgoCD Application manifests
│   ├── metrics-server.yaml
│   ├── aws-load-balancer-controller.yaml
│   ├── cert-manager.yaml
│   ├── prometheus-stack.yaml
│   ├── elasticsearch.yaml
│   ├── kibana.yaml
│   ├── fluent-bit.yaml
│   ├── otel-collector.yaml
│   ├── cluster-autoscaler.yaml
│   ├── storage-class.yaml
│   └── argocd.yaml         # Self-management
├── storage-class/          # StorageClass manifest
│   ├── storageclass.yaml
│   └── kustomization.yaml
└── otel-collector/         # OpenTelemetry ConfigMap
    ├── configmap.yaml
    └── kustomization.yaml

scripts/
└── install-eks-addons.sh  # Bootstrap script (ArgoCD only, all addons managed via GitOps)
```

## Updating Chart Versions

To update a Helm chart version:

1. Check latest version from chart repository
2. Update `targetRevision` in the Application manifest
3. Commit and push to Git
4. ArgoCD automatically syncs the new version

Example:
```yaml
# gitops/argo-apps/metrics-server.yaml
spec:
  source:
    targetRevision: 3.12.0  # Update this version
```

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
argocd app get <app-name>

# Check sync logs
argocd app logs <app-name>

# Force sync
argocd app sync <app-name>
```

### Helm Chart Version Issues

- Verify chart version exists in repository
- Check Kubernetes version compatibility
- Review application sync status in ArgoCD UI

### IAM Role Issues

- Verify Terraform outputs are correct
- Check ServiceAccount annotations
- Ensure IAM roles exist in AWS

### Dependencies Not Met

- StorageClass must exist before charts that use it
- Elasticsearch must be ready before Kibana
- Cert-manager must be ready before ClusterIssuers

ArgoCD handles dependencies automatically, but you can check sync order in the UI.

## Rollback

To rollback a change:

1. **Git Rollback:**
   ```bash
   git revert <commit-hash>
   git push
   # ArgoCD automatically syncs the reverted state
   ```

2. **Manual Rollback:**
   ```bash
   # Sync to previous Git revision
   argocd app sync <app-name> --revision <previous-commit>
   ```

## Next Steps

1. Verify all applications are synced and healthy
2. Update Helm chart versions as needed (check compatibility)
3. Monitor ArgoCD UI for sync status
4. Remove old script if no longer needed (keep for reference)

## Documentation Links

- **ArgoCD:** https://argo-cd.readthedocs.io/
- **Helm Charts:** Check individual chart repositories for latest versions
- **Terraform:** IAM roles are managed in `infra/terraform/modules/eks/iam_roles.tf`

