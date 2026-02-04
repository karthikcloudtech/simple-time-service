# Complete Project Structure

## Overview

This document provides a complete overview of the project folder structure and what each directory contains.

## Root Directory Structure

```
simple-time-service/
├── app/                          # Application source code
├── gitops/                       # GitOps configurations (ArgoCD)
├── infra/                        # Infrastructure as Code (Terraform)
├── k8s/                          # Legacy Kubernetes manifests
├── scripts/                      # Automation scripts
└── [Documentation files]         # Various .md files
```

## Detailed Structure

### 📁 `app/` - Application Source Code

```
app/
└── app.py                        # Python Flask application
```

**Purpose:** Application source code (Python Flask service)

---

### 📁 `gitops/` - GitOps Configurations

This is the main GitOps directory managed by ArgoCD.

#### `gitops/apps/` - Application Manifests

```
apps/
└── simple-time-service/
    ├── base/                     # Base Kubernetes manifests
    │   ├── deployment.yaml       # Application deployment
    │   ├── service.yaml          # Kubernetes service
    │   ├── ingress.yaml          # Ingress configuration
    │   ├── namespace.yaml        # Namespace definition
    │   ├── servicemonitor.yaml   # Prometheus ServiceMonitor
    │   └── kustomization.yaml    # Kustomize base config
    └── overlays/                 # Environment-specific overlays
        ├── prod/                 # Production environment
        │   ├── kustomization.yaml
        │   ├── patch-prod.yaml
        │   └── patch-ingress-prod.yaml
        └── staging/              # Staging environment
            ├── kustomization.yaml
            ├── namespace.yaml
            ├── patch-staging.yaml
            └── patch-ingress-staging.yaml
```

**Purpose:** Raw Kubernetes manifests for applications (NOT Helm)
- Uses Kustomize for environment overlays
- Managed by ArgoCD Applications

#### `gitops/argo-apps/` - ArgoCD Application Manifests

```
argo-apps/
├── README.md                     # Documentation
├── VERSION_UPDATE_NOTES.md       # Version verification guide
│
├── Application Deployments:
│   ├── simple-time-service-prod.yaml      # App deployment (prod)
│   └── simple-time-service-staging.yaml  # App deployment (staging)
│
├── Infrastructure Ingresses:
│   ├── monitoring.yaml           # Prometheus + Grafana ingresses
│   ├── logging.yaml               # Kibana + Elasticsearch ingresses
│   └── argocd.yaml                # ArgoCD UI ingress
│
└── EKS Addons (Helm Charts):
    ├── storage-class.yaml        # StorageClass (raw manifest)
    ├── metrics-server.yaml       # Metrics Server Helm chart
    ├── aws-load-balancer-controller.yaml  # ALB Controller Helm chart
    ├── cert-manager.yaml         # Cert-Manager Helm chart
    ├── cluster-issuers.yaml       # ClusterIssuers (raw manifest)
    ├── prometheus-stack.yaml     # Prometheus Stack Helm chart
    ├── elasticsearch.yaml        # Elasticsearch Helm chart
    ├── kibana.yaml               # Kibana Helm chart
    ├── fluent-bit.yaml           # Fluent-bit Helm chart
    ├── otel-collector-config.yaml # OpenTelemetry ConfigMap
    ├── otel-collector.yaml       # OpenTelemetry Collector Helm chart
    ├── cluster-autoscaler.yaml  # Cluster Autoscaler Helm chart
    └── argocd.yaml               # ArgoCD self-management Helm chart
```

**Purpose:** ArgoCD Application manifests that define what gets deployed
- References Helm charts OR raw Kubernetes manifests
- Managed declaratively via GitOps

#### `gitops/helm-charts/` - Helm Values Files

```
helm-charts/
├── README.md                     # Overview
├── BEST_PRACTICES.md             # Best practices guide
├── MIGRATION_GUIDE.md            # Migration from inline params
├── STRUCTURE.md                  # Structure explanation
│
└── [Chart Name]/                 # One folder per Helm chart
    └── values.yaml               # Helm values file
    │
    ├── metrics-server/
    ├── aws-load-balancer-controller/
    ├── cert-manager/
    ├── prometheus-stack/
    ├── elasticsearch/
    ├── kibana/
    ├── fluent-bit/
    ├── otel-collector/
    └── cluster-autoscaler/
```

**Purpose:** Helm values files for infrastructure/addon charts
- **NOT used for applications** (applications use raw manifests)
- Currently created but not actively used (Applications use inline parameters)
- Available for migration if needed

#### `gitops/argocd/` - ArgoCD Ingress Configuration

```
argocd/
├── README.md
├── namespace.yaml                # ArgoCD namespace
├── argocd-ingress.yaml           # ArgoCD UI ingress
└── kustomization.yaml            # Kustomize config
```

**Purpose:** ArgoCD infrastructure configuration (ingress)

#### `gitops/cluster-issuers/` - Cert-Manager ClusterIssuers

```
cluster-issuers/
├── README.md
├── clusterissuer.yaml            # Let's Encrypt ClusterIssuers
└── kustomization.yaml            # Kustomize config
```

**Purpose:** Cert-Manager ClusterIssuers for SSL certificates

