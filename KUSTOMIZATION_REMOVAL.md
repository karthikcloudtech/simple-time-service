# Kustomization Removal - Complete Migration to Helm

**Date:** February 8, 2026  
**Status:** ✅ Complete

## Summary

All Kustomize-based configurations have been removed from the repository. The project now exclusively uses Helm charts for all deployments.

## What Was Removed

### Application Kustomizations
- `gitops/apps/simple-time-service/` (base and overlays for staging/prod)
  - Replaced by: `gitops/helm-charts/simple-time-service`

### Infrastructure Kustomizations
- `gitops/argocd/` → `gitops/helm-charts/argocd-ingress`
- `gitops/monitoring/` → `gitops/helm-charts/monitoring-ingress`
- `gitops/logging/` → `gitops/helm-charts/logging-ingress`
- `gitops/cluster-issuers/` → `gitops/helm-charts/cluster-issuers`
- `gitops/storage-class/` → `gitops/helm-charts/storage-class`
- `gitops/otel-collector/` → `gitops/helm-charts/otel-collector-config`
- `gitops/serviceaccounts/` → `gitops/helm-charts/serviceaccounts`

**Total:** 10 kustomization.yaml files removed

## Updated Documentation

All documentation has been updated to reference Helm charts instead of Kustomize:

1. **gitops/argo-apps/README.md** - Updated all path references to Helm charts
2. **gitops/INGRESS_SUMMARY.md** - Changed deployment commands to use `helm template`
3. **docs/infrastructure/CANARY_GUIDE.md** - Updated quick start and file structure
4. **docs/infrastructure/SETUP.md** - Changed from `kubectl apply -k` to `helm template`

## Deployment Commands

### Old (Kustomize)
```bash
kubectl apply -k gitops/apps/simple-time-service/overlays/prod
```

### New (Helm)
```bash
helm template simple-time-service gitops/helm-charts/simple-time-service \
  -f gitops/helm-charts/simple-time-service/values-prod.yaml | kubectl apply -f -
```

Or via ArgoCD (recommended):
```bash
kubectl apply -f gitops/argo-apps/simple-time-service-prod.yaml
```

## ArgoCD Applications

All ArgoCD Application manifests already reference Helm charts:
- ✅ simple-time-service-prod → `gitops/helm-charts/simple-time-service`
- ✅ simple-time-service-staging → `gitops/helm-charts/simple-time-service`
- ✅ monitoring-ingress → `gitops/helm-charts/monitoring-ingress`
- ✅ logging-ingress → `gitops/helm-charts/logging-ingress`
- ✅ argocd-ingress → `gitops/helm-charts/argocd-ingress`
- ✅ storage-class → `gitops/helm-charts/storage-class`
- ✅ cluster-issuers → `gitops/helm-charts/cluster-issuers`
- ✅ otel-collector-config → `gitops/helm-charts/otel-collector-config`
- ✅ serviceaccounts → `gitops/helm-charts/serviceaccounts`

## Benefits

1. **Consistency** - Single deployment method (Helm) across all resources
2. **Simplicity** - No more overlays/patches; just values files
3. **Industry Standard** - Helm is the de facto Kubernetes package manager
4. **Better Templating** - More powerful template functions and helpers
5. **Cleaner Repo** - Removed 40+ legacy files

## Verification

All Helm charts have been tested and render successfully:
```bash
# Application
helm template simple-time-service gitops/helm-charts/simple-time-service -f gitops/helm-charts/simple-time-service/values-prod.yaml

# Infrastructure
helm template monitoring-ingress gitops/helm-charts/monitoring-ingress
helm template logging-ingress gitops/helm-charts/logging-ingress
helm template storage-class gitops/helm-charts/storage-class
helm template cluster-issuers gitops/helm-charts/cluster-issuers
```

## Migration Context

This cleanup completes the Helm migration that was started earlier (see `gitops/HELM_MIGRATION.md`). The Helm charts were already in place and being used by ArgoCD, but the old Kustomize files were left in the repository. This change removes all legacy Kustomize configurations.

## No Action Required

Since ArgoCD applications were already pointing to Helm charts, no changes are needed for running deployments. This is purely a cleanup of unused files and documentation updates.
