# Script Cleanup Summary

## What Was Removed

Since all addons are now managed via ArgoCD GitOps (`gitops/argo-apps/*.yaml`), the following manual installation functions were removed from `install-eks-addons.sh`:

### Removed Functions (All Now Managed by ArgoCD)

1. **`install_alb_controller()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/aws-load-balancer-controller.yaml`
   - **IAM Role**: Created by Terraform (`infra/terraform/modules/eks/iam_roles.tf`)
   - **Helm Chart**: Deployed via ArgoCD Application

2. **`install_metrics_server()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/metrics-server.yaml`
   - **Helm Chart**: Deployed via ArgoCD Application

3. **`install_cert_manager()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/cert-manager.yaml`
   - **IAM Role**: Created by Terraform (`infra/terraform/modules/eks/iam_roles.tf`)
   - **Helm Chart**: Deployed via ArgoCD Application
   - **ClusterIssuers**: Managed by `gitops/argo-apps/cluster-issuers.yaml`

4. **`install_prometheus()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/prometheus-stack.yaml`
   - **Helm Chart**: Deployed via ArgoCD Application
   - **Values**: From `gitops/helm-charts/prometheus-stack/values.yaml`

5. **`install_storage_class()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/storage-class.yaml`
   - **Manifest**: Deployed via ArgoCD Application

6. **`install_efk()`** ❌ Removed (Elasticsearch, Fluent-bit, Kibana)
   - **Reason**: Managed by:
     - `gitops/argo-apps/elasticsearch.yaml`
     - `gitops/argo-apps/fluent-bit.yaml`
     - `gitops/argo-apps/kibana.yaml`
   - **Helm Charts**: Deployed via ArgoCD Applications
   - **Values**: From `gitops/helm-charts/{elasticsearch,fluent-bit,kibana}/values.yaml`

7. **`install_otel_collector()`** ❌ Removed
   - **Reason**: Managed by:
     - `gitops/argo-apps/otel-collector-config.yaml` (ConfigMap)
     - `gitops/argo-apps/otel-collector.yaml` (Helm chart)
   - **Helm Chart**: Deployed via ArgoCD Application
   - **Values**: From `gitops/helm-charts/otel-collector/values.yaml`

8. **`install_cluster_autoscaler()`** ❌ Removed
   - **Reason**: Managed by `gitops/argo-apps/cluster-autoscaler.yaml`
   - **IAM Role**: Created by Terraform (`infra/terraform/modules/eks/iam_roles.tf`)
   - **Helm Chart**: Deployed via ArgoCD Application

### Removed Helper Functions

- **`helm_repo()`** ❌ Removed (no longer needed - ArgoCD handles Helm repos)
- **`ns()`** ❌ Removed (ArgoCD creates namespaces automatically)
- **IAM role creation code** ❌ Removed (Terraform handles this)

### Removed Configuration Variables

- `INSTALL_MODE` (manual/gitops) - No longer needed, script is GitOps-only
- `INSTALL_ALB_CONTROLLER`
- `INSTALL_METRICS_SERVER`
- `INSTALL_CERT_MANAGER`
- `INSTALL_PROMETHEUS`
- `INSTALL_EFK`
- `INSTALL_OTEL_COLLECTOR`
- `INSTALL_CLUSTER_AUTOSCALER`
- `PROJECT_NAME` (only needed for IAM role names, which Terraform handles)

## What Remains

### Kept Functions

1. **`install_argocd_bootstrap()`** ✅ Kept
   - **Reason**: Needed to bootstrap ArgoCD itself (chicken-and-egg problem)
   - **Purpose**: One-time installation of ArgoCD, which then manages itself and all other addons

### Kept Utilities

- `check_prerequisites()` - Still needed
- `verify_setup()` - Still needed
- `wait_for_nodes()` - Still needed
- Logging functions (`log`, `success`, `warn`, `error`)

## Impact

### Before
- **Lines**: ~635 lines
- **Functions**: 9 installation functions + helpers
- **Modes**: GitOps mode + Manual mode
- **Responsibilities**: IAM creation, Helm installation, manual deployment

### After
- **Lines**: ~175 lines (72% reduction!)
- **Functions**: 1 installation function (ArgoCD bootstrap)
- **Modes**: GitOps-only
- **Responsibilities**: ArgoCD bootstrap only

## Migration Path

### Old Usage (Manual Mode)
```bash
INSTALL_MODE=manual ./scripts/install-eks-addons.sh
```

### New Usage (GitOps Mode - Only)
```bash
# 1. Bootstrap ArgoCD
./scripts/install-eks-addons.sh

# 2. Ensure IAM roles exist (via Terraform)
cd infra/environments/prod && terraform apply

# 3. Annotate ServiceAccounts with IAM role ARNs
# (Get ARNs from Terraform outputs)
terraform output aws_load_balancer_controller_role_arn
terraform output cluster_autoscaler_role_arn
terraform output cert_manager_role_arn

# Annotate ServiceAccounts
kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=<ROLE_ARN>

# 4. Apply ArgoCD Applications
kubectl apply -f gitops/argo-apps/*.yaml
```

## Benefits

1. **Single Source of Truth**: All addons managed via GitOps
2. **Simpler Script**: 72% reduction in code
3. **Better Maintainability**: No duplicate installation logic
4. **Consistent Management**: All addons follow same GitOps pattern
5. **Version Control**: All configurations in Git
6. **Rollback Capability**: Git history provides rollback
7. **No IAM Duplication**: Terraform handles IAM, script doesn't duplicate

## ArgoCD Applications Reference

All addons are now managed via these ArgoCD Applications:

| Component | ArgoCD Application | Helm Chart/Path |
|-----------|-------------------|-----------------|
| StorageClass | `storage-class.yaml` | `gitops/storage-class/` |
| Metrics Server | `metrics-server.yaml` | `metrics-server` |
| ALB Controller | `aws-load-balancer-controller.yaml` | `aws-load-balancer-controller` |
| Cert-Manager | `cert-manager.yaml` | `cert-manager` |
| ClusterIssuers | `cluster-issuers.yaml` | `gitops/cluster-issuers/` |
| Prometheus Stack | `prometheus-stack.yaml` | `kube-prometheus-stack` |
| Elasticsearch | `elasticsearch.yaml` | `elasticsearch` |
| Kibana | `kibana.yaml` | `kibana` |
| Fluent-bit | `fluent-bit.yaml` | `fluent-bit` |
| OTEL Collector Config | `otel-collector-config.yaml` | `gitops/otel-collector/` |
| OTEL Collector | `otel-collector.yaml` | `opentelemetry-collector` |
| Cluster Autoscaler | `cluster-autoscaler.yaml` | `cluster-autoscaler` |
| ArgoCD (self) | `argocd.yaml` | `argo-cd` |

See `gitops/argo-apps/README.md` for details.

