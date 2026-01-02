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

#### `gitops/monitoring/` - Monitoring Ingresses

```
monitoring/
├── README.md
├── namespace.yaml
├── prometheus-ingress.yaml       # Prometheus ingress
├── grafana-ingress.yaml          # Grafana ingress
└── kustomization.yaml
```

**Purpose:** Ingress configurations for monitoring stack

#### `gitops/logging/` - Logging Ingresses

```
logging/
├── namespace.yaml
├── elasticsearch-ingress.yaml    # Elasticsearch ingress
├── kibana-ingress.yaml           # Kibana ingress
└── kustomization.yaml
```

**Purpose:** Ingress configurations for logging stack

#### `gitops/storage-class/` - StorageClass Manifest

```
storage-class/
├── storageclass.yaml             # GP3 StorageClass
└── kustomization.yaml
```

**Purpose:** EBS GP3 StorageClass for persistent volumes

#### `gitops/otel-collector/` - OpenTelemetry ConfigMap

```
otel-collector/
├── configmap.yaml                # OTel Collector configuration
└── kustomization.yaml
```

**Purpose:** OpenTelemetry Collector configuration

---

### 📁 `infra/` - Infrastructure as Code (Terraform)

```
infra/
├── environments/
│   └── prod/                     # Production environment
│       ├── main.tf               # Main Terraform config
│       ├── variables.tf          # Variable definitions
│       ├── outputs.tf           # Output values
│       ├── terraform.tfvars      # Variable values
│       └── terraform.tfstate*   # State files (gitignored)
│
└── terraform/
    └── modules/
        ├── eks/                  # EKS cluster module
        │   ├── main.tf          # EKS cluster, node groups
        │   ├── iam_roles.tf    # IAM roles for service accounts
        │   ├── addons.tf        # EKS addons (EBS CSI)
        │   ├── variables.tf     # Module variables
        │   └── outputs.tf      # Module outputs
        └── vpc/                  # VPC module
            ├── main.tf          # VPC, subnets, NAT gateway
            ├── variables.tf      # Module variables
            └── outputs.tf       # Module outputs
```

**Purpose:** Infrastructure provisioning via Terraform
- EKS cluster, VPC, networking
- IAM roles for service accounts
- EKS managed addons

---

### 📁 `scripts/` - Automation Scripts

```
scripts/
├── README.md
├── check-helm-versions.sh        # Check latest Helm chart versions
├── install-eks-addons-bootstrap.sh  # Bootstrap ArgoCD (minimal)
├── install-eks-addons.sh         # Legacy: Full addon installation
├── setup-gitlab-runner-ec2.sh   # GitLab Runner setup
└── GITLAB_RUNNER_EC2_SETUP.md   # GitLab Runner documentation
```

**Purpose:** Automation and setup scripts
- Bootstrap scripts for initial setup
- Version checking utilities
- CI/CD setup scripts

---

### 📁 `k8s/` - Legacy Kubernetes Manifests

```
k8s/
├── deployment.yaml               # Legacy app deployment
├── storage-class-gp3.yaml       # Legacy StorageClass
├── kibana-values.yml            # Legacy Kibana values
└── debug-connectivity-es.yml    # Debugging manifests
```

**Purpose:** Legacy Kubernetes manifests (pre-GitOps)
- May be used for manual deployments
- Some files referenced by scripts

---

## File Type Summary

### ArgoCD Applications (`gitops/argo-apps/*.yaml`)
- Define what gets deployed
- Reference Helm charts OR raw manifests
- Managed by ArgoCD

### Helm Values (`gitops/helm-charts/*/values.yaml`)
- Configuration for Helm charts
- Currently created but not actively used
- Can be referenced by ArgoCD Applications

### Raw Kubernetes Manifests (`gitops/apps/`, `gitops/*/`)
- Application deployments
- Infrastructure components (ingresses, StorageClass, etc.)
- Managed via Kustomize

### Terraform (`infra/`)
- Infrastructure provisioning
- IAM roles and policies
- EKS cluster and networking

### Scripts (`scripts/`)
- Bootstrap and setup automation
- Utility scripts

## Key Distinctions

### Applications vs Infrastructure

| Type | Location | Format | Managed By |
|------|----------|--------|------------|
| **Applications** | `gitops/apps/` | Raw Kubernetes manifests | ArgoCD |
| **Infrastructure** | `gitops/helm-charts/` | Helm values files | ArgoCD |
| **ArgoCD Apps** | `gitops/argo-apps/` | ArgoCD Application manifests | ArgoCD |

### Helm Charts vs Raw Manifests

| Component | Uses Helm? | Location |
|-----------|------------|----------|
| **Applications** | ❌ No | `gitops/apps/` |
| **Infrastructure Addons** | ✅ Yes | `gitops/helm-charts/` |
| **Ingresses** | ❌ No | `gitops/monitoring/`, `gitops/logging/` |
| **StorageClass** | ❌ No | `gitops/storage-class/` |
| **ClusterIssuers** | ❌ No | `gitops/cluster-issuers/` |

## ArgoCD Application Mapping

| ArgoCD Application | References | Type |
|-------------------|------------|------|
| `simple-time-service-prod` | `gitops/apps/simple-time-service/overlays/prod` | Raw manifests |
| `metrics-server` | Helm chart: `metrics-server` | Helm chart |
| `prometheus-stack` | Helm chart: `kube-prometheus-stack` | Helm chart |
| `monitoring` | `gitops/monitoring` | Raw manifests (ingresses) |
| `cluster-issuers` | `gitops/cluster-issuers` | Raw manifests |

## Best Practices Followed

✅ **Separation of Concerns**
- Applications separate from infrastructure
- Helm charts separate from raw manifests
- Terraform separate from Kubernetes configs

✅ **GitOps Structure**
- All Kubernetes configs in `gitops/`
- ArgoCD Applications define deployments
- Version controlled in Git

✅ **Environment Management**
- Kustomize overlays for environments
- Separate prod/staging configs

✅ **Documentation**
- README files in key directories
- Migration guides and best practices
- Version verification guides

## Summary

- **Applications:** Raw Kubernetes manifests in `gitops/apps/`
- **Infrastructure:** Helm charts with values in `gitops/helm-charts/`
- **ArgoCD:** Application manifests in `gitops/argo-apps/`
- **Infrastructure:** Terraform in `infra/`
- **Scripts:** Automation in `scripts/`

All managed declaratively via GitOps! 🎉

