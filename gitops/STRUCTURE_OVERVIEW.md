# GitOps Structure Overview

## Quick Reference

```
gitops/
│
├── 📦 argo-apps/              # ArgoCD Application Manifests (WHAT to deploy)
│   ├── simple-time-service-prod.yaml    → References apps/
│   ├── metrics-server.yaml              → References Helm chart
│   ├── prometheus-stack.yaml            → References Helm chart
│   └── ...
│
├── 🚀 apps/                  # Application Manifests (Raw Kubernetes)
│   └── simple-time-service/
│       ├── base/             # Base manifests
│       └── overlays/         # Environment overlays
│
├── 📊 helm-charts/           # Helm Values Files (Infrastructure ONLY)
│   ├── metrics-server/values.yaml
│   ├── prometheus-stack/values.yaml
│   └── ...
│
├── 🔧 Infrastructure Components (Raw Manifests)
│   ├── argocd/               # ArgoCD ingress
│   ├── monitoring/           # Monitoring ingresses
│   ├── logging/              # Logging ingresses
│   ├── cluster-issuers/      # Cert-Manager ClusterIssuers
│   ├── storage-class/        # StorageClass
│   └── otel-collector/       # OpenTelemetry ConfigMap
│
└── 📄 Documentation
    ├── INGRESS_SUMMARY.md
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

### 2. Application Manifests (`apps/`)

**Purpose:** Raw Kubernetes manifests for applications

**Structure:**
- Base manifests (deployment, service, ingress)
- Environment overlays (prod, staging)
- Uses Kustomize for patching

**Current:** 1 application (`simple-time-service`)

### 3. Helm Charts (`helm-charts/`)

**Purpose:** Helm values files for infrastructure/addon charts

**Contents:**
- 9 Helm chart value files
- Documentation (README, best practices, migration guides)

**Note:** Currently created but not actively used (Applications use inline parameters)

### 4. Infrastructure Components

**Purpose:** Raw Kubernetes manifests for infrastructure

**Components:**
- `argocd/` - ArgoCD ingress configuration
- `monitoring/` - Prometheus/Grafana ingresses
- `logging/` - Kibana/Elasticsearch ingresses
- `cluster-issuers/` - Cert-Manager ClusterIssuers
- `storage-class/` - EBS GP3 StorageClass
- `otel-collector/` - OpenTelemetry ConfigMap

## File Count Summary

| Directory | Files | Purpose |
|-----------|-------|---------|
| `argo-apps/` | 19 YAML files | ArgoCD Applications |
| `apps/` | 12 YAML files | Application manifests |
| `helm-charts/` | 9 values.yaml + docs | Helm values |
| Infrastructure | ~15 YAML files | Raw manifests |
| **Total** | **~55 files** | GitOps configs |

## ArgoCD Application Types

### Type 1: Application Deployments
- Reference: `gitops/apps/simple-time-service/overlays/{env}`
- Format: Raw Kubernetes manifests (Kustomize)
- Examples: `simple-time-service-prod.yaml`, `simple-time-service-staging.yaml`

### Type 2: Helm Chart Applications
- Reference: Helm chart repositories
- Format: Helm charts with inline parameters OR values files
- Examples: `metrics-server.yaml`, `prometheus-stack.yaml`, `cert-manager.yaml`

### Type 3: Raw Manifest Applications
- Reference: `gitops/{component}/`
- Format: Raw Kubernetes manifests (Kustomize)
- Examples: `storage-class.yaml`, `cluster-issuers.yaml`, `monitoring.yaml`

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

- ✅ Applications use raw manifests (not Helm)
- ✅ Infrastructure uses Helm charts
- ✅ Helm-charts folder only contains infrastructure values
- ✅ ArgoCD Applications properly reference sources
- ✅ Environment separation via Kustomize overlays
- ✅ Documentation in place

## Notes

- **Helm Charts Folder:** Contains values files but Applications currently use inline parameters
- **Migration:** Can migrate to values files later if needed
- **Structure:** Follows GitOps best practices
- **Organization:** Clear separation between apps and infrastructure

