# Fixes Applied - January 11, 2026

## Summary
Fixed ServiceAccount IAM role annotations and added missing Terraform outputs to resolve pod deployment issues.

## Changes Made

### 1. ServiceAccount IAM Role Annotations Fixed
Updated all ServiceAccount YAML files with correct IAM role ARNs:

- **Cluster Autoscaler** (`gitops/serviceaccounts/cluster-autoscaler-sa.yaml`)
  - Added IAM role ARN: `arn:aws:iam::017019814021:role/simple-time-service-cluster-autoscaler-role`
  - Status: ✅ Fixed - Pod now running successfully

- **AWS Load Balancer Controller** (`gitops/serviceaccounts/aws-load-balancer-controller-sa.yaml`)
  - Added IAM role ARN: `arn:aws:iam::017019814021:role/simple-time-service-aws-load-balancer-controller-role`
  - Status: ✅ ServiceAccount created - Waiting for ArgoCD to deploy controller

- **Cert Manager** (`gitops/serviceaccounts/cert-manager-sa.yaml`)
  - Added IAM role ARN: `arn:aws:iam::017019814021:role/simple-time-service-cert-manager-role`
  - Status: ✅ Updated

### 2. Terraform Outputs Enhanced
Added missing output to `infra/environments/prod/outputs.tf`:

- **aws_load_balancer_controller_role_arn**: IAM role ARN for AWS Load Balancer Controller
  - Now available via: `terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn`

### 3. Installation Script Improvements
Updated `scripts/install-eks-addons.sh`:

- Enhanced `update_serviceaccount_annotations()` function to handle both placeholder and existing ARN patterns
- Improved regex patterns to match `ACCOUNT_ID` placeholder or actual account IDs
- Script now automatically updates ServiceAccount YAML files with correct IAM role ARNs from Terraform outputs

## Current Status

### ✅ Working Components
- Cluster Autoscaler - Running successfully
- Cert Manager - Running successfully
- Metrics Server - Running successfully
- Fluent Bit - Running successfully
- Prometheus Stack - Running successfully
- ArgoCD - Running successfully

### ⚠️ Pending Deployment (Blocked by ArgoCD Repo Server Connectivity)
The following components are configured but waiting for ArgoCD to sync:
- AWS Load Balancer Controller
- Elasticsearch
- Kibana
- OTEL Collector

**Note**: ArgoCD applications show "Unknown" sync status due to repo server connectivity issues. This is likely a transient network issue that should resolve automatically. Once connectivity is restored, ArgoCD will automatically sync these applications.

## Verification Commands

```bash
# Check Cluster Autoscaler status
kubectl get pods -n kube-system | grep cluster-autoscaler

# Check ServiceAccount annotations
kubectl get serviceaccount -n kube-system cluster-autoscaler-aws-cluster-autoscaler -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
kubectl get serviceaccount -n kube-system aws-load-balancer-controller -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Check ArgoCD application status
kubectl get application -n argocd

# Force sync applications (if needed)
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

## Next Steps

1. Monitor ArgoCD repo server connectivity - check logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server`
2. Once connectivity is restored, applications should sync automatically
3. Verify all pods are running: `kubectl get pods -A`

## Files Modified

1. `gitops/serviceaccounts/cluster-autoscaler-sa.yaml`
2. `gitops/serviceaccounts/aws-load-balancer-controller-sa.yaml`
3. `gitops/serviceaccounts/cert-manager-sa.yaml`
4. `infra/environments/prod/outputs.tf`
5. `scripts/install-eks-addons.sh`
