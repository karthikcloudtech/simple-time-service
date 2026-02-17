# Kustomize to Helm Migration Guide

## Overview

This document describes the migration from Kustomize-based ArgoCD applications to Helm-based applications completed on 2026-02-08.

## What Was Migrated

All Kustomize-based ArgoCD applications have been migrated to use Helm charts. This includes:

### 1. Application Services
- **simple-time-service** (prod and staging)
  - Migrated from: `gitops/apps/simple-time-service/overlays/{env}`
  - Migrated to: `gitops/helm-charts/apps/simple-time-service`
  - Values files: `values.yaml`, `values-prod.yaml`, `values-staging.yaml`

### 2. Infrastructure Components
- **monitoring-ingress** (Prometheus and Grafana ingresses)
  - Migrated from: `gitops/monitoring`
  - Migrated to: `gitops/helm-charts/observability/monitoring-ingress`

- **logging-ingress** (Elasticsearch and Kibana ingresses)
  - Migrated from: `gitops/logging`
  - Migrated to: `gitops/helm-charts/observability/logging-ingress`

- **otel-collector-config** (OpenTelemetry ConfigMap)
  - Migrated from: `gitops/otel-collector`
  - Migrated to: `gitops/helm-charts/observability/otel-collector-config`

- **serviceaccounts** (AWS IRSA service accounts)
  - Migrated from: `gitops/serviceaccounts`
  - Migrated to: `gitops/helm-charts/platform/serviceaccounts`

- **storage-class** (EBS GP3 StorageClass)
  - Migrated from: `gitops/storage-class`
  - Migrated to: `gitops/helm-charts/platform/storage-class`

- **cluster-issuers** (Cert-Manager ClusterIssuers)
  - Migrated from: `gitops/cluster-issuers`
  - Migrated to: `gitops/helm-charts/platform/cluster-issuers`

- **argocd-ingress** (ArgoCD ingress)
  - Migrated from: `gitops/argocd`
  - Migrated to: `gitops/helm-charts/platform/argocd-ingress`

## Benefits of Helm Migration

1. **Better Templating**: Helm provides more powerful templating with built-in functions
2. **Easier Environment Management**: Environment-specific values files are clearer than Kustomize patches
3. **Industry Standard**: Helm is the de facto standard for Kubernetes package management
4. **Consistency**: All infrastructure and application components now use the same deployment method
5. **Simplified Values**: Environment differences are expressed as simple value overrides
6. **Better Documentation**: Helm charts include structured metadata via Chart.yaml

## File Structure

### Helm Chart Structure
Each migrated component follows this structure:
```
gitops/helm-charts/{category}/{component}/
├── Chart.yaml                 # Chart metadata
├── values.yaml                # Default values
├── values-{env}.yaml          # Environment-specific overrides (if applicable)
└── templates/                 # Kubernetes manifest templates
    ├── namespace.yaml
    ├── {resource}.yaml
    └── ...
```

### ArgoCD Application Updates
All ArgoCD Application manifests in `gitops/argo-apps/` have been updated to use the new Helm source:

**Before (Kustomize):**
```yaml
spec:
  source:
    repoURL: https://github.com/karthikcloudtech/simple-time-service.git
    targetRevision: fastapi
    path: gitops/apps/simple-time-service/overlays/prod
```

**After (Helm):**
```yaml
spec:
  source:
    repoURL: https://github.com/karthikcloudtech/simple-time-service.git
    targetRevision: fastapi
    path: gitops/helm-charts/apps/simple-time-service
    helm:
      valueFiles:
        - values.yaml
        - values-prod.yaml
```

## Helm Charts Created

| Chart Name | Description | Templates |
|------------|-------------|-----------|
| apps/simple-time-service | Main application with Argo Rollouts | Namespace, Rollout, Service, Ingress, ServiceMonitor, AnalysisTemplates |
| observability/monitoring-ingress | Prometheus and Grafana ingresses | Namespace, Prometheus Ingress, Grafana Ingress |
| observability/logging-ingress | Elasticsearch and Kibana ingresses | Namespace, Elasticsearch Ingress, Kibana Ingress |
| observability/otel-collector-config | OpenTelemetry Collector ConfigMap | ConfigMap |
| platform/serviceaccounts | AWS IRSA service accounts | ServiceAccounts, Namespace |
| platform/storage-class | EBS GP3 StorageClass | StorageClass |
| platform/cluster-issuers | Cert-Manager ClusterIssuers | ClusterIssuers |
| platform/argocd-ingress | ArgoCD ingress | Namespace, Ingress |

## Validation

All Helm charts have been validated using `helm template` to ensure they render correctly:

```bash
# Example validation commands
cd gitops/helm-charts/apps/simple-time-service
helm template test . -f values.yaml -f values-prod.yaml

cd ../../observability/monitoring-ingress
helm template test . -f values.yaml

# ... etc for all charts
```

All charts successfully render the expected Kubernetes manifests.

## Deployment

When ArgoCD syncs these applications, it will:
1. Render the Helm templates using the specified values files
2. Apply the generated Kubernetes manifests to the cluster
3. Continue to monitor and sync changes automatically

## Old Kustomize Directories

The following directories still exist but are no longer referenced by ArgoCD applications:
- `gitops/apps/simple-time-service/` (base and overlays)
- `gitops/monitoring/`
- `gitops/logging/`
- `gitops/otel-collector/`
- `gitops/serviceaccounts/`
- `gitops/storage-class/`
- `gitops/cluster-issuers/`
- `gitops/argocd/` (except for documentation)

These can be removed in a future cleanup if desired, but they are kept for reference and backward compatibility.

## Rolling Back (If Needed)

If you need to roll back to Kustomize-based deployments:

1. Revert the ArgoCD Application manifests in `gitops/argo-apps/`
2. Change the `source.path` back to the original Kustomize paths
3. Remove the `source.helm` section
4. Let ArgoCD re-sync the applications

Example rollback for simple-time-service-prod:
```yaml
spec:
  source:
    path: gitops/apps/simple-time-service/overlays/prod
    # Remove helm section
```

## Future Considerations

1. **Cleanup**: Consider removing old Kustomize directories after confirming Helm migration is stable
2. **Documentation**: Update other documentation files to reflect Helm-based structure
3. **CI/CD**: Update any CI/CD pipelines that reference Kustomize paths
4. **New Applications**: All new applications should use Helm charts following the established pattern

## Testing Recommendations

Before deploying to production:
1. Test in a development/staging environment first
2. Verify all resources are created correctly
3. Check that environment-specific values are applied correctly
4. Ensure ArgoCD sync works as expected
5. Validate application functionality after deployment

## Support

For questions or issues with the migration:
- Review the individual Helm chart values files for configuration options
- Check ArgoCD sync status for any deployment issues
- Refer to the existing Helm chart documentation in `gitops/helm-charts/`
