# Version Verification Guide

Before deploying ArgoCD applications, verify all Helm chart versions are current and compatible with your Kubernetes cluster version.

## Quick Verification Checklist

- [ ] Kubernetes cluster version: `kubectl version --short`
- [ ] EKS cluster version: Check AWS Console or `aws eks describe-cluster --name <cluster-name>`
- [ ] All Helm chart versions verified against latest releases
- [ ] Chart versions compatible with Kubernetes version

## Chart Version Documentation Links

### Core Addons

**Metrics Server**
- Chart Repository: https://kubernetes-sigs.github.io/metrics-server
- Latest Releases: https://github.com/kubernetes-sigs/metrics-server/releases
- Current Version in Config: `3.12.0`
- File: `gitops/argo-apps/metrics-server.yaml`

**AWS Load Balancer Controller**
- Chart Repository: https://aws.github.io/eks-charts
- Latest Releases: https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
- EKS Compatibility: https://github.com/aws/eks-charts#compatibility
- Current Version in Config: `1.7.2`
- File: `gitops/argo-apps/aws-load-balancer-controller.yaml`

**Cert-Manager**
- Chart Repository: https://charts.jetstack.io
- Latest Releases: https://github.com/cert-manager/cert-manager/releases
- Kubernetes Compatibility: https://cert-manager.io/docs/installation/supported-releases/
- Current Version in Config: `v1.13.3`
- File: `gitops/argo-apps/cert-manager.yaml`

### Monitoring & Observability

**Prometheus Stack**
- Chart Repository: https://prometheus-community.github.io/helm-charts
- Latest Releases: https://github.com/prometheus-community/helm-charts/releases
- Chart Hub: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
- Current Version in Config: `58.0.0`
- File: `gitops/argo-apps/prometheus-stack.yaml`

**OpenTelemetry Collector**
- Chart Repository: https://open-telemetry.github.io/opentelemetry-helm-charts
- Latest Releases: https://github.com/open-telemetry/opentelemetry-helm-charts/releases
- Chart Hub: https://artifacthub.io/packages/helm/open-telemetry/opentelemetry-collector
- Current Version in Config: `0.99.0`
- File: `gitops/argo-apps/otel-collector.yaml`

### Logging

**Elasticsearch**
- Chart Repository: https://helm.elastic.co
- Latest Releases: https://github.com/elastic/helm-charts/releases
- Version Compatibility: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-supported-versions.html
- Current Version in Config: `8.11.0`
- File: `gitops/argo-apps/elasticsearch.yaml`

**Kibana**
- Chart Repository: https://helm.elastic.co
- Latest Releases: https://github.com/elastic/helm-charts/releases
- **IMPORTANT:** Kibana version must match Elasticsearch version
- Current Version in Config: `8.11.0`
- File: `gitops/argo-apps/kibana.yaml`

**Fluent-bit**
- Chart Repository: https://fluent.github.io/helm-charts
- Latest Releases: https://github.com/fluent/helm-charts/releases
- Chart Hub: https://artifacthub.io/packages/helm/fluent/fluent-bit
- Current Version in Config: `0.40.0`
- File: `gitops/argo-apps/fluent-bit.yaml`

### Autoscaling

**Cluster Autoscaler**
- Chart Repository: https://kubernetes.github.io/autoscaler
- Latest Releases: https://github.com/kubernetes/autoscaler/releases
- Chart Hub: https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler
- EKS Compatibility: Check AWS documentation for recommended version
- Current Version in Config: `9.29.2`
- File: `gitops/argo-apps/cluster-autoscaler.yaml`

### GitOps

**ArgoCD**
- Chart Repository: https://argoproj.github.io/argo-helm
- Latest Releases: https://github.com/argoproj/argo-helm/releases
- Official Docs: https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/
- Current Version in Config: `7.0.0`
- File: `gitops/argo-apps/argocd.yaml`

## How to Update Versions

1. **Check Latest Version:**
   - Visit the chart repository or GitHub releases page
   - Check compatibility with your Kubernetes version
   - Review changelog for breaking changes

2. **Update Application Manifest:**
   ```yaml
   # gitops/argo-apps/<app-name>.yaml
   spec:
     source:
       targetRevision: <new-version>  # Update this
   ```

3. **Commit and Push:**
   ```bash
   git add gitops/argo-apps/<app-name>.yaml
   git commit -m "Update <app-name> to version <new-version>"
   git push
   ```

4. **ArgoCD Auto-Sync:**
   - ArgoCD detects the change automatically
   - Syncs the new version within 3 minutes (default poll interval)
   - Or sync manually: `argocd app sync <app-name>`

## Compatibility Matrix

| Component | Kubernetes 1.28+ | Kubernetes 1.29+ | Kubernetes 1.30+ | Notes |
|-----------|------------------|------------------|------------------|-------|
| Metrics Server | ✅ | ✅ | ✅ | Check chart version |
| ALB Controller | ✅ | ✅ | ✅ | EKS-specific |
| Cert-Manager | ✅ | ✅ | ✅ | Check cert-manager.io docs |
| Prometheus Stack | ✅ | ✅ | ✅ | Check chart compatibility |
| Elasticsearch | ✅ | ✅ | ✅ | Check ECK compatibility |
| Cluster Autoscaler | ✅ | ✅ | ✅ | Check AWS EKS docs |

**Note:** Always verify compatibility for your specific Kubernetes/EKS version.

## Deprecated Features to Watch

- **Helm Chart API Versions:** Some charts may use deprecated APIs
- **Kubernetes APIs:** Check for deprecated API versions in chart values
- **ArgoCD API:** Ensure Application manifests use `argoproj.io/v1alpha1`

## Testing Updates

Before updating production:

1. Test in staging environment first
2. Review Helm chart release notes
3. Check for breaking changes
4. Verify backup/rollback procedure
5. Update one chart at a time

## Getting Help

- Chart Issues: Check chart repository GitHub issues
- ArgoCD Issues: https://github.com/argoproj/argo-cd/issues
- EKS Compatibility: AWS EKS documentation
- Kubernetes Compatibility: Kubernetes release notes

