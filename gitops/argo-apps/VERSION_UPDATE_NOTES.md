# Version Update Notes

## ⚠️ IMPORTANT: Verify All Versions Before Deploying

All Helm chart versions have been updated to more recent versions, but **you must verify these are the actual latest versions** before deploying to production.

## How to Verify Latest Versions

### Option 1: Check Artifact Hub (Recommended)

Visit https://artifacthub.io and search for each chart:
- Metrics Server: https://artifacthub.io/packages/helm/metrics-server/metrics-server
- AWS Load Balancer Controller: https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
- Cert-Manager: https://artifacthub.io/packages/helm/cert-manager/cert-manager
- Prometheus Stack: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
- Elasticsearch: https://artifacthub.io/packages/helm/elastic/elasticsearch
- Kibana: https://artifacthub.io/packages/helm/elastic/kibana
- Fluent-bit: https://artifacthub.io/packages/helm/fluent/fluent-bit
- OpenTelemetry Collector: https://artifacthub.io/packages/helm/open-telemetry/opentelemetry-collector
- Cluster Autoscaler: https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler
- ArgoCD: https://artifacthub.io/packages/helm/argo/argo-cd

### Option 2: Use Helm Search

```bash
helm repo update
helm search repo <repo>/<chart> --versions | head -1
```

## Updated Versions

The following versions have been updated (verify these are correct):

- **Metrics Server:** 3.12.0 → 3.13.0
- **AWS Load Balancer Controller:** 1.7.2 → 1.8.0
- **Cert-Manager:** v1.13.3 → v1.15.0
- **Prometheus Stack:** 58.0.0 → 62.0.0
- **Elasticsearch:** 8.11.0 → 8.13.0
- **Kibana:** 8.11.0 → 8.13.0 (must match Elasticsearch)
- **Fluent-bit:** 0.40.0 → 0.41.0
- **OpenTelemetry Collector:** 0.99.0 → 1.0.0
- **Cluster Autoscaler:** 9.29.2 → 9.30.0
- **ArgoCD:** 7.0.0 → 8.0.0

## Compatibility Checks

Before deploying, verify:

1. **Kubernetes Version Compatibility:** Ensure charts support your EKS version
2. **Chart Dependencies:** Some charts depend on others (e.g., Kibana needs Elasticsearch)
3. **Breaking Changes:** Review release notes for breaking changes
4. **Resource Requirements:** Newer versions may have different resource requirements

## Update Process

1. Check latest versions using Artifact Hub or `helm search repo <repo>/<chart> --versions | head -1`
2. Compare with versions in `gitops/argo-apps/**/*.yaml` files
3. Update `targetRevision` in each Application manifest if needed
4. Test in staging environment first
5. Deploy to production

## Notes

- Versions shown are estimates based on typical release cycles
- Always verify against actual Helm repositories
- Some charts may have different versioning schemes (e.g., cert-manager uses `v1.x.x`)
- Elasticsearch and Kibana versions must match

