# Helm Charts Folder Structure

## Purpose

The `gitops/helm-charts/` folder contains **Helm charts for both applications and infrastructure/addon components**.

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

### ✅ Application Components

- **simple-time-service** - Main application chart (Rollouts, ingress, services)

### ❌ What Does NOT Go Here

1. **Custom Helm Charts**
   - If you create custom Helm charts, put them in `charts/` directory
   - Not needed for this project

2. **ArgoCD Applications**
   - Application manifests go in `gitops/argo-apps/`
   - These reference Helm charts

## Current Project Structure

```
gitops/
├── helm-charts/              # Helm charts (apps + infrastructure)
│   ├── apps/
│   │   └── simple-time-service/
│   ├── observability/
│   │   ├── monitoring-ingress/
│   │   ├── logging-ingress/
│   │   └── ...
│   └── platform/
│       ├── cert-manager/
│       ├── metrics-server/
│       └── ...
│
└── argo-apps/                # ArgoCD Application manifests
   ├── apps/
   ├── observability/
   └── platform/
```

## Why This Structure?

### Infrastructure Components → Helm Charts
- ✅ Third-party charts from public repositories
- ✅ Complex configurations benefit from Helm values
- ✅ Easy to update chart versions
- ✅ Standard practice for infrastructure

### Applications → Helm Charts
- ✅ Shared conventions across environments
- ✅ Clear overrides via values files
- ✅ Easier reuse and consistency

## Summary

| Component Type | Location | Format |
|----------------|----------|--------|
| **Helm Charts** | `gitops/helm-charts/` | Helm charts (apps + infrastructure) |
| **ArgoCD Apps** | `gitops/argo-apps/` | ArgoCD Application manifests grouped by category |

**Answer:** `helm-charts/` is used for both applications and infrastructure, while ArgoCD manifests are grouped into `apps`, `observability`, and `platform`.

