# ArgoCD Applications Configuration

This directory contains ArgoCD Application manifests that define what gets automatically deployed.

## Current ArgoCD Applications

| Application | Path | Namespace | Auto-Sync | Status |
|-------------|------|-----------|-----------|--------|
| **simple-time-service-prod** | `gitops/apps/simple-time-service/overlays/prod` | `simple-time-service` | ✅ Yes | ✅ Configured |
| **simple-time-service-staging** | `gitops/apps/simple-time-service/overlays/staging` | `simple-time-service-staging` | ✅ Yes | ✅ Configured |
| **monitoring-ingress** | `gitops/monitoring` | `monitoring` | ✅ Yes | ✅ **NEW** |
| **logging-ingress** | `gitops/logging` | `logging` | ✅ Yes | ✅ **NEW** |
| **argocd-ingress** | `gitops/argocd` | `argocd` | ✅ Yes | ✅ **NEW** |

## Auto-Deployment Status

### ✅ Will Auto-Deploy (via ArgoCD)

When you push changes to the `develop` branch, ArgoCD will automatically:

1. **Application Ingresses** ✅
   - `simple-time-service-prod` → Includes ingress patch
   - `simple-time-service-staging` → Includes ingress patch

2. **Infrastructure Ingresses** ✅ (After applying ArgoCD apps)
   - `monitoring-ingress` → Prometheus + Grafana ingresses
   - `logging-ingress` → Kibana + Elasticsearch ingresses
   - `argocd-ingress` → ArgoCD UI ingress

### Setup Required

To enable auto-deployment for infrastructure ingresses, apply the ArgoCD Application manifests:

```bash
# Apply all ArgoCD applications
kubectl apply -f gitops/argo-apps/monitoring.yaml
kubectl apply -f gitops/argo-apps/logging.yaml
kubectl apply -f gitops/argo-apps/argocd.yaml
```

After applying, ArgoCD will:
- Watch the Git repository
- Auto-sync when changes are pushed to `develop` branch
- Deploy ingresses automatically
- Create SSL certificates via cert-manager

## How It Works

1. **You push changes** to GitLab (develop branch)
2. **ArgoCD detects changes** (polls every 3 minutes by default)
3. **ArgoCD syncs automatically** (because `syncPolicy.automated` is enabled)
4. **Ingresses are deployed** to Kubernetes
5. **Cert-manager creates SSL certificates** automatically

## Manual Deployment (Alternative)

If you prefer manual deployment instead of ArgoCD:

```bash
# Deploy manually
kubectl apply -k gitops/argocd/
kubectl apply -k gitops/monitoring/
kubectl apply -k gitops/logging/
```

## Verify ArgoCD Applications

```bash
# List all ArgoCD applications
kubectl get application -n argocd

# Check application status
argocd app get monitoring-ingress
argocd app get logging-ingress
argocd app get argocd-ingress
argocd app get simple-time-service-prod
argocd app get simple-time-service-staging

# View sync status in ArgoCD UI
# https://argocd.trainerkarthik.shop
```

## Sync Policy Details

All applications use:
- **Automated sync**: `syncPolicy.automated` enabled
- **Prune**: Automatically removes resources deleted from Git
- **Self-heal**: Automatically corrects manual changes
- **CreateNamespace**: Automatically creates namespaces if missing

## Git Repository Configuration

All applications watch:
- **Repository**: `https://gitlab.com/karthikbm2k25/simple-time-service.git`
- **Branch**: `develop`
- **Path**: See table above

## Summary

✅ **Application ingresses**: Already auto-deployed via existing ArgoCD apps
✅ **Infrastructure ingresses**: Will auto-deploy after applying new ArgoCD apps
✅ **All ingresses**: Will be automatically synced when you push to Git

**Next Step**: Apply the ArgoCD Application manifests to enable auto-deployment for infrastructure ingresses.

