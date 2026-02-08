# GitOps Structure Overview

## Quick Reference

```
gitops/
│
├── 📦 argo-apps/              # ArgoCD Application Manifests (WHAT to deploy)
│   ├── simple-time-service-prod.yaml    → References helm-charts/
│   ├── metrics-server.yaml              → References external Helm chart
│   ├── prometheus-stack.yaml            → References external Helm chart
│   └── ...
│
├── 🚀 apps/                  # [DEPRECATED] Application Manifests (Migrated to Helm)
│   └── simple-time-service/  # Now using helm-charts/simple-time-service
│       ├── base/             # Base manifests (kept for reference)
│       └── overlays/         # Environment overlays (kept for reference)
│
├── 📊 helm-charts/           # Helm Charts (Applications + Infrastructure)
│   ├── simple-time-service/  # Application Helm chart
│   ├── monitoring-ingress/   # Monitoring ingresses
│   ├── logging-ingress/      # Logging ingresses
│   ├── otel-collector-config/# OpenTelemetry ConfigMap
│   ├── serviceaccounts/      # AWS IRSA service accounts
│   ├── storage-class/        # StorageClass
│   ├── cluster-issuers/      # Cert-Manager ClusterIssuers
│   ├── argocd-ingress/       # ArgoCD ingress
│   ├── metrics-server/values.yaml       # External chart values
│   ├── prometheus-stack/values.yaml     # External chart values
│   └── ...
│
├── 🔧 [DEPRECATED] Infrastructure Components (Migrated to Helm)
│   ├── argocd/               # ArgoCD ingress (now helm-charts/argocd-ingress)
│   ├── monitoring/           # Monitoring ingresses (now helm-charts/monitoring-ingress)
│   ├── logging/              # Logging ingresses (now helm-charts/logging-ingress)
│   ├── cluster-issuers/      # ClusterIssuers (now helm-charts/cluster-issuers)
│   ├── storage-class/        # StorageClass (now helm-charts/storage-class)
│   └── otel-collector/       # ConfigMap (now helm-charts/otel-collector-config)
│
└── 📄 Documentation
    ├── INGRESS_SUMMARY.md
    ├── HELM_MIGRATION.md
    └── [Various README files]
```

## Component Breakdown

### 1. ArgoCD Applications (`argo-apps/`)

**Purpose:** Define what ArgoCD should deploy

**Types:**
- **Application Deployments:** `simple-time-service-prod.yaml`, `simple-time-service-staging.yaml`
- **Infrastructure Ingresses:** `monitoring.yaml`, `logging.yaml`, `argocd.yaml`
- **EKS Addons (Helm):** `metrics-server.yaml`, `prometheus-stack.yaml`, etc.
- **Raw Manifests:** `storage-class.yaml`, `cluster-issuers.yaml`

**Total:** 19 ArgoCD Application manifests

### 2. Application Manifests (`apps/`) - [DEPRECATED]

**Purpose:** Raw Kubernetes manifests for applications (MIGRATED TO HELM)

**Status:** DEPRECATED - All applications have been migrated to Helm charts in `helm-charts/` directory

**Previous Structure:**
- Base manifests (deployment, service, ingress)
- Environment overlays (prod, staging)
- Uses Kustomize for patching

**Migration:** See `HELM_MIGRATION.md` for details

### 3. Helm Charts (`helm-charts/`)

**Purpose:** Helm charts for applications AND infrastructure components

**Contents:**
- **Application Helm Charts:**
  - `simple-time-service/` - Main application with environment-specific values
- **Infrastructure Helm Charts:**
  - `monitoring-ingress/` - Prometheus and Grafana ingresses
  - `logging-ingress/` - Elasticsearch and Kibana ingresses
  - `otel-collector-config/` - OpenTelemetry ConfigMap
  - `serviceaccounts/` - AWS IRSA service accounts
  - `storage-class/` - EBS GP3 StorageClass
  - `cluster-issuers/` - Cert-Manager ClusterIssuers
  - `argocd-ingress/` - ArgoCD ingress
- **External Chart Values:**
  - `metrics-server/values.yaml`
  - `prometheus-stack/values.yaml`
  - `cert-manager/values.yaml`
  - And more...
- **Documentation:**
  - README, best practices, migration guides

**Migration:** All Kustomize-based apps migrated to Helm (see `HELM_MIGRATION.md`)

### 4. Infrastructure Components - [DEPRECATED]

**Purpose:** Raw Kubernetes manifests for infrastructure (MIGRATED TO HELM)

**Status:** DEPRECATED - All components have been migrated to Helm charts in `helm-charts/` directory

**Previous Components:**
- `argocd/` - ArgoCD ingress (now `helm-charts/argocd-ingress/`)
- `monitoring/` - Prometheus/Grafana ingresses (now `helm-charts/monitoring-ingress/`)
- `logging/` - Kibana/Elasticsearch ingresses (now `helm-charts/logging-ingress/`)
- `cluster-issuers/` - ClusterIssuers (now `helm-charts/cluster-issuers/`)
- `storage-class/` - StorageClass (now `helm-charts/storage-class/`)
- `otel-collector/` - ConfigMap (now `helm-charts/otel-collector-config/`)

**Migration:** See `HELM_MIGRATION.md` for details

## File Count Summary

| Directory | Files | Purpose |
|-----------|-------|---------|
| `argo-apps/` | 19 YAML files | ArgoCD Applications |
| `apps/` | 12 YAML files | Application manifests |
| `helm-charts/` | 9 values.yaml + docs | Helm values |
| Infrastructure | ~15 YAML files | Raw manifests |
| **Total** | **~55 files** | GitOps configs |

## ArgoCD Application Types

### Type 1: Local Helm Chart Applications
- Reference: `gitops/helm-charts/{component}/`
- Format: Helm charts with environment-specific values files
- Examples: `simple-time-service-prod.yaml`, `simple-time-service-staging.yaml`, `monitoring.yaml`, `logging.yaml`, `storage-class.yaml`, `cluster-issuers.yaml`

### Type 2: External Helm Chart Applications
- Reference: External Helm chart repositories (e.g., `https://argoproj.github.io/argo-helm`)
- Format: Helm charts with inline parameters OR values files
- Examples: `metrics-server.yaml`, `prometheus-stack.yaml`, `cert-manager.yaml`, `argocd.yaml`

### Type 3: [DEPRECATED] Raw Manifest Applications
- **Status:** DEPRECATED - All have been migrated to Type 1 (Local Helm Charts)
- Previous Reference: `gitops/{component}/` or `gitops/apps/{app}/overlays/{env}`
- Previous Format: Raw Kubernetes manifests (Kustomize)

## Dependencies

### Installation Order

1. **Bootstrap:** ArgoCD (via script)
2. **Core Infrastructure:**
   - StorageClass (required by Prometheus, Elasticsearch)
   - Metrics Server
   - Cert-Manager
   - ClusterIssuers (requires Cert-Manager)
3. **Networking:**
   - AWS Load Balancer Controller
4. **Monitoring:**
   - Prometheus Stack
   - Monitoring Ingresses
5. **Logging:**
   - Elasticsearch (requires StorageClass)
   - Kibana (requires Elasticsearch)
   - Fluent-bit (requires Elasticsearch)
   - Logging Ingresses
6. **Observability:**
   - OpenTelemetry ConfigMap
   - OpenTelemetry Collector
7. **Autoscaling:**
   - Cluster Autoscaler
8. **Self-Management:**
   - ArgoCD (self-management)

## Verification Checklist

- ✅ All applications migrated to Helm charts
- ✅ All infrastructure components migrated to Helm charts
- ✅ Helm-charts folder contains both application and infrastructure charts
- ✅ ArgoCD Applications properly reference Helm chart sources
- ✅ Environment separation via Helm values files (values-prod.yaml, values-staging.yaml)
- ✅ Documentation updated to reflect migration
- ✅ All Helm charts validated with `helm template`

## Migration Notes (2026-02-08)

- **Migration Completed:** All Kustomize-based applications and infrastructure migrated to Helm
- **Old Directories:** Kept for reference but no longer used by ArgoCD
- **Benefits:** Better templating, easier environment management, industry standard approach
- **Documentation:** See `HELM_MIGRATION.md` for complete migration details
- **Structure:** Follows GitOps and Helm best practices
- **Organization:** Unified approach for both apps and infrastructure

