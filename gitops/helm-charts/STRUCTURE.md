# Helm Charts Folder Structure

## Purpose

The `gitops/helm-charts/` folder contains **Helm values files for infrastructure/addon components only**.

## What Goes Here

### ✅ Infrastructure/Addon Components

These are third-party Helm charts from public repositories:

- **Metrics Server** - Kubernetes metrics collection
- **AWS Load Balancer Controller** - ALB/NLB management
- **Cert-Manager** - SSL certificate management
- **Prometheus Stack** - Monitoring stack
- **Elasticsearch/Kibana** - Logging stack
- **Fluent-bit** - Log forwarding
- **OpenTelemetry Collector** - Observability
- **Cluster Autoscaler** - Node autoscaling
- **ArgoCD** - GitOps tool (self-management)

### ❌ What Does NOT Go Here

1. **Application Helm Charts**
   - Applications use raw Kubernetes manifests in `gitops/apps/`
   - Example: `simple-time-service` uses `deployment.yaml`, `service.yaml` (not Helm)

2. **Custom Helm Charts**
   - If you create custom Helm charts, put them in `charts/` directory
   - Not needed for this project

3. **ArgoCD Applications**
   - Application manifests go in `gitops/argo-apps/`
   - These reference Helm charts OR raw manifests

## Current Project Structure

```
gitops/
├── helm-charts/              # Infrastructure Helm values ONLY
│   ├── metrics-server/
│   │   └── values.yaml       # ✅ Infrastructure component
│   ├── cert-manager/
│   │   └── values.yaml       # ✅ Infrastructure component
│   └── prometheus-stack/
│       └── values.yaml       # ✅ Infrastructure component
│
├── apps/                     # Application manifests (NOT Helm)
│   └── simple-time-service/
│       ├── base/
│       │   ├── deployment.yaml    # ✅ Raw Kubernetes manifest
│       │   ├── service.yaml        # ✅ Raw Kubernetes manifest
│       │   └── ingress.yaml       # ✅ Raw Kubernetes manifest
│       └── overlays/
│           ├── prod/
│           └── staging/
│
└── argo-apps/                # ArgoCD Application manifests
    ├── metrics-server.yaml    # References Helm chart
    ├── prometheus-stack.yaml  # References Helm chart
    └── simple-time-service-prod.yaml  # References raw manifests (Kustomize)
```

## Why This Structure?

### Infrastructure Components → Helm Charts
- ✅ Third-party charts from public repositories
- ✅ Complex configurations benefit from Helm values
- ✅ Easy to update chart versions
- ✅ Standard practice for infrastructure

### Applications → Raw Manifests (Kustomize)
- ✅ Simple, straightforward deployments
- ✅ Full control over Kubernetes resources
- ✅ Easy to understand and modify
- ✅ No Helm chart dependency
- ✅ Kustomize for environment overlays

## When Would You Use Helm for Applications?

You might use Helm for applications if:

1. **Multiple Similar Services** - Template-based deployment
2. **Complex Configurations** - Many values to manage
3. **Chart Reusability** - Share charts across projects
4. **Team Preference** - Team prefers Helm over raw manifests

**For this project:** Raw manifests with Kustomize is simpler and sufficient.

## Summary

| Component Type | Location | Format |
|----------------|----------|--------|
| **Infrastructure/Addons** | `gitops/helm-charts/` | Helm values files |
| **Applications** | `gitops/apps/` | Raw Kubernetes manifests |
| **ArgoCD Apps** | `gitops/argo-apps/` | ArgoCD Application manifests |

**Answer:** No, `helm-charts/` is NOT used for applications. It's only for infrastructure/addon Helm charts.

