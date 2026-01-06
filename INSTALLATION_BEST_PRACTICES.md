# Installation Best Practices & Idempotency Guide

## Overview

This document outlines the recommended approach for managing infrastructure and Kubernetes resources, ensuring idempotency for daily destroy/recreate cycles.

## Resource Management Strategy

### ✅ Terraform Manages (AWS Infrastructure)

**Why Terraform:**
- AWS resources that exist outside Kubernetes
- IAM roles and policies (AWS-native)
- EKS addons that are AWS-managed
- Infrastructure lifecycle (create/destroy)

**Resources:**
1. **VPC & Networking**
   - VPC, Subnets, Route Tables
   - Internet Gateway, NAT Gateway
   - Security Groups

2. **EKS Cluster**
   - EKS Cluster
   - Node Groups
   - OIDC Provider

3. **IAM Roles & Policies**
   - Cluster role
   - Node role
   - ServiceAccount roles (for IRSA):
     - AWS Load Balancer Controller
     - Cluster Autoscaler
     - Cert-Manager
     - EBS CSI Driver
     - EFS CSI Driver (optional)
     - External DNS (optional)

4. **EKS Addons (AWS-Managed)**
   - EBS CSI Driver (via `aws_eks_addon`)

### ✅ Kubernetes Manifests/YAML Manages (Kubernetes Resources)

**Why YAML/ArgoCD:**
- Kubernetes-native resources
- Helm charts and applications
- GitOps workflow
- Easy to version and rollback

**Resources:**
1. **ServiceAccounts** (with IAM annotations)
   - Created via `gitops/serviceaccounts/`
   - Managed by ArgoCD Application

2. **Helm Charts** (via ArgoCD)
   - AWS Load Balancer Controller
   - Cert-Manager
   - Cluster Autoscaler
   - Metrics Server
   - Prometheus Stack
   - Elasticsearch, Kibana, Fluent-bit
   - OpenTelemetry Collector

3. **Application Deployments**
   - Your application manifests
   - Ingresses
   - Services

4. **ConfigMaps & Secrets**
   - Application configs
   - Certificates (via cert-manager)

## Installation Flow

### Phase 1: Infrastructure (Terraform)

```bash
cd infra/environments/prod
terraform init
terraform plan
terraform apply
```

**What happens:**
1. Creates VPC, subnets, networking
2. Creates EKS cluster and node groups
3. Creates IAM roles and policies
4. Creates OIDC provider
5. Installs EBS CSI Driver addon
6. Runs `install-eks-addons.sh` script (bootstraps ArgoCD)

**Outputs:**
- IAM role ARNs (for ServiceAccount annotations)
- Cluster endpoint
- VPC ID, Subnet IDs

### Phase 2: GitOps Bootstrap (Script)

The `install-eks-addons.sh` script (called by Terraform):

1. **Bootstraps ArgoCD**
   - Installs ArgoCD from official manifest
   - Waits for ArgoCD server to be ready
   - Applies ArgoCD ingress

2. **Creates ServiceAccounts with IAM Annotations**
   - Reads IAM role ARNs from Terraform outputs
   - Creates ServiceAccounts with proper annotations
   - Uses `kubectl apply` (idempotent)

3. **Applies ArgoCD Applications**
   - Applies all ArgoCD Application manifests
   - ArgoCD takes over management

### Phase 3: GitOps Sync (ArgoCD)

ArgoCD automatically:
1. Syncs ServiceAccounts (from `gitops/serviceaccounts/`)
2. Syncs Helm charts (from `gitops/argo-apps/*.yaml`)
3. Manages application deployments
4. Self-heals if resources are modified

## Idempotency Guarantees

### Terraform
- ✅ **Already idempotent** by design
- Uses `terraform apply` (safe to run multiple times)
- Handles resource existence gracefully

### Kubernetes Resources

**ServiceAccounts:**
```bash
# Script uses kubectl apply (idempotent)
kubectl create serviceaccount NAME --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate serviceaccount NAME --overwrite  # --overwrite prevents errors
```

**ArgoCD Applications:**
```bash
# kubectl apply is idempotent
kubectl apply -f gitops/argo-apps/*.yaml
```

**Helm Charts:**
- ArgoCD handles idempotency
- Uses `helm upgrade --install` internally
- Safe to sync multiple times

### Script Idempotency

The `install-eks-addons.sh` script:

1. **Checks before creating:**
   ```bash
   if kubectl get deployment argocd-server -n argocd &>/dev/null; then
       log "ArgoCD is already installed, skipping..."
       return 0
   fi
   ```

2. **Uses idempotent commands:**
   - `kubectl apply` (not `create`)
   - `--dry-run=client` to check existence
   - `--overwrite` for annotations

3. **Handles errors gracefully:**
   - Continues if resource exists
   - Logs warnings instead of failing

## Daily Destroy/Recreate Workflow

### Destroy Everything

```bash
# 1. Delete ArgoCD Applications (optional - Terraform destroy will handle)
kubectl delete application --all -n argocd

# 2. Destroy Terraform (this destroys everything)
cd infra/environments/prod
terraform destroy -auto-approve
```

**What gets destroyed:**
- ✅ EKS cluster and nodes
- ✅ VPC and networking
- ✅ IAM roles and policies
- ✅ EKS addons
- ✅ All Kubernetes resources (when cluster is destroyed)

### Recreate Everything

```bash
# 1. Apply Terraform (creates infrastructure + bootstraps ArgoCD)
cd infra/environments/prod
terraform apply -auto-approve

# 2. Wait for ArgoCD to sync (automatic)
kubectl get applications -n argocd -w

# 3. Verify everything is ready
kubectl get pods --all-namespaces
```

**What gets created:**
1. Terraform creates infrastructure
2. Script bootstraps ArgoCD
3. Script creates ServiceAccounts
4. Script applies ArgoCD Applications
5. ArgoCD syncs all Helm charts
6. Everything is ready!

## Key Design Decisions

### Why ServiceAccounts in YAML?

**Pros:**
- ✅ Version controlled in Git
- ✅ Managed by GitOps (ArgoCD)
- ✅ Easy to update IAM role ARNs
- ✅ Can be reviewed in PRs

**Cons:**
- Need to update role ARNs manually (or via script)

**Solution:** Script automatically updates ServiceAccounts with Terraform outputs

### Why IAM Roles in Terraform?

**Pros:**
- ✅ AWS resources belong in Terraform
- ✅ Lifecycle managed with infrastructure
- ✅ Easy to destroy/recreate
- ✅ Can reference other Terraform resources

**Cons:**
- None - this is the correct approach

### Why Helm Charts via ArgoCD?

**Pros:**
- ✅ GitOps workflow
- ✅ Automatic sync and self-healing
- ✅ Easy rollback
- ✅ Version control for chart versions
- ✅ No manual `helm install` commands

**Cons:**
- Requires ArgoCD to be running

**Solution:** Script bootstraps ArgoCD first

## Troubleshooting

### ServiceAccount Already Exists

**Error:** `serviceaccounts "aws-load-balancer-controller" already exists`

**Solution:** Script uses `kubectl apply` which handles this gracefully. If you see this, it means the script is working correctly.

### ArgoCD Application Sync Failed

**Check:**
```bash
kubectl get application APP_NAME -n argocd -o yaml
kubectl describe application APP_NAME -n argocd
```

**Common issues:**
1. ServiceAccount missing IAM annotation → Check `gitops/serviceaccounts/`
2. Helm chart version incompatible → Update `targetRevision` in ArgoCD app
3. StorageClass missing → Ensure `storage-class` app syncs first

### IAM Role Not Found

**Error:** Pods can't assume IAM role

**Check:**
```bash
# Verify role exists
aws iam get-role --role-name simple-time-service-aws-load-balancer-controller-role

# Verify ServiceAccount annotation
kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml
```

**Solution:** Ensure Terraform applied successfully and script ran

## Best Practices Summary

1. **Infrastructure → Terraform**
   - VPC, EKS, IAM roles, EKS addons

2. **Kubernetes Resources → YAML/ArgoCD**
   - ServiceAccounts, Helm charts, Applications

3. **Idempotency → Always use `apply`**
   - `terraform apply` (idempotent)
   - `kubectl apply` (idempotent)
   - Script checks before creating

4. **GitOps → ArgoCD**
   - All Kubernetes resources managed via Git
   - Automatic sync and self-healing

5. **Daily Workflow**
   - `terraform destroy` → `terraform apply`
   - Everything recreates automatically
   - No manual steps needed

## Quick Reference

### Create Everything
```bash
cd infra/environments/prod
terraform apply -auto-approve
# Script runs automatically, ArgoCD syncs everything
```

### Destroy Everything
```bash
cd infra/environments/prod
terraform destroy -auto-approve
# Everything is destroyed
```

### Check Status
```bash
# Infrastructure
terraform output

# Kubernetes
kubectl get nodes
kubectl get pods --all-namespaces

# ArgoCD
kubectl get applications -n argocd
argocd app list
```

### Update ServiceAccount IAM Roles
```bash
# Get role ARN from Terraform
terraform output -raw aws_load_balancer_controller_role_arn

# Update in Git (gitops/serviceaccounts/aws-load-balancer-controller-sa.yaml)
# ArgoCD will sync automatically
```

## Conclusion

This setup provides:
- ✅ **Idempotency:** Safe to run multiple times
- ✅ **Separation of Concerns:** Terraform for AWS, YAML for K8s
- ✅ **GitOps:** All Kubernetes resources in Git
- ✅ **Automation:** Script handles bootstrap, ArgoCD manages rest
- ✅ **Daily Practice:** Destroy and recreate without issues

