# ArgoCD Applications Configuration

This directory contains ArgoCD Application manifests that define what gets automatically deployed.

## Current ArgoCD Applications

### Folder Layout

```
gitops/argo-apps/
├── apps/
│   ├── simple-time-service-prod.yaml
│   └── simple-time-service-staging.yaml
├── observability/
│   ├── monitoring.yaml
│   ├── logging.yaml
│   ├── prometheus-stack.yaml
│   ├── elasticsearch.yaml
│   ├── kibana.yaml
│   ├── fluent-bit.yaml
│   ├── otel-collector-config.yaml
│   └── otel-collector.yaml
└── platform/
   ├── storage-class.yaml
   ├── metrics-server.yaml
   ├── cert-manager.yaml
   ├── cluster-issuers.yaml
   ├── serviceaccounts.yaml
   ├── cluster-autoscaler.yaml
   ├── argocd.yaml
   └── argocd-ingress.yaml
```

### Application Deployments

| Application | Path/Chart | Namespace | Auto-Sync | Status |
|-------------|------------|-----------|-----------|--------|
| **simple-time-service-prod** | `gitops/helm-charts/apps/simple-time-service` | `simple-time-service` | ✅ Yes | ✅ Configured |
| **simple-time-service-staging** | `gitops/helm-charts/apps/simple-time-service` | `simple-time-service-staging` | ✅ Yes | ✅ Configured |

### Infrastructure Ingresses

| Application | Path | Namespace | Auto-Sync | Status |
|-------------|------|-----------|-----------|--------|
| **monitoring-ingress** | `gitops/helm-charts/observability/monitoring-ingress` | `monitoring` | ✅ Yes | ✅ Configured |
| **logging-ingress** | `gitops/helm-charts/observability/logging-ingress` | `logging` | ✅ Yes | ✅ Configured |
| **argocd-ingress** | `gitops/helm-charts/platform/argocd-ingress` | `argocd` | ✅ Yes | ✅ Configured (applied by bootstrap script) |

### EKS Addons (Helm Charts via ArgoCD)

| Application | Helm Chart | Namespace | Auto-Sync | Prerequisites |
|-------------|------------|-----------|-----------|---------------|
| **storage-class** | `gitops/helm-charts/platform/storage-class` | `default` | ✅ Yes | None (cluster-scoped) |
| **metrics-server** | `metrics-server` (v3.12.0) | `kube-system` | ✅ Yes | None |
| **aws-load-balancer-controller** | `aws-load-balancer-controller` (v1.7.2) | `kube-system` | ✅ Yes | IAM role + ServiceAccount annotation |
| **cert-manager** | `cert-manager` (v1.13.3) | `cert-manager` | ✅ Yes | None |
| **cluster-issuers** | `gitops/helm-charts/platform/cluster-issuers` | `cert-manager` | ✅ Yes | cert-manager installed |
| **prometheus-stack** | `kube-prometheus-stack` (v58.0.0) | `monitoring` | ✅ Yes | StorageClass `gp3` |
| **elasticsearch** | `elasticsearch` (v8.11.0) | `logging` | ✅ Yes | StorageClass `gp3` |
| **kibana** | `kibana` (v8.11.0) | `logging` | ✅ Yes | Elasticsearch installed |
| **fluent-bit** | `fluent-bit` (v0.40.0) | `logging` | ✅ Yes | Elasticsearch installed |
| **otel-collector-config** | `gitops/helm-charts/observability/otel-collector-config` | `observability` | ✅ Yes | None |
| **otel-collector** | `opentelemetry-collector` (v0.99.0) | `observability` | ✅ Yes | ConfigMap `otel-collector-config` |
| **cluster-autoscaler** | `cluster-autoscaler` (v9.29.2) | `kube-system` | ✅ Yes | IAM role + ServiceAccount annotation |
| **argocd** | `argo-cd` (v7.0.0) | `argocd` | ✅ Yes | Initial bootstrap via script |

**NOTE:** All Helm chart versions should be verified for latest releases and compatibility:
- Check chart repositories for latest versions
- Verify Kubernetes version compatibility
- See individual application files for documentation links

## Auto-Deployment Status

### ✅ Will Auto-Deploy (via ArgoCD)

When you push changes to the `main` branch (or configured branch), ArgoCD will automatically:

1. **Application Deployments** ✅
   - `simple-time-service-prod` → Includes ingress patch
   - `simple-time-service-staging` → Includes ingress patch

2. **Infrastructure Ingresses** ✅
   - `monitoring-ingress` → Prometheus + Grafana ingresses
   - `logging-ingress` → Kibana + Elasticsearch ingresses
   - `argocd-ingress` → ArgoCD UI ingress

3. **EKS Addons** ✅ (Managed via ArgoCD GitOps)
   - Core: StorageClass, Metrics Server, Cert-Manager, ClusterIssuers
   - Networking: AWS Load Balancer Controller
   - Monitoring: Prometheus Stack
   - Logging: Elasticsearch, Kibana, Fluent-bit
   - Observability: OpenTelemetry Collector
   - Autoscaling: Cluster Autoscaler
   - GitOps: ArgoCD (self-managed)

### Setup Required

#### 1. Bootstrap ArgoCD (One-time)

First, install ArgoCD using the bootstrap script:

```bash
# Run bootstrap script (installs ArgoCD + applies ingress)
./scripts/install-eks-addons.sh
```

**What the script does:**
- Installs ArgoCD from official manifest
- Applies ArgoCD ingress (requires AWS Load Balancer Controller to be running)
- Shows ALB hostname for DNS configuration

**Alternative:** If ArgoCD is already installed, skip this step.

#### 2. Configure IAM Role Annotations (IMPORTANT: Do this BEFORE applying Applications)

**Critical:** Some ArgoCD Applications require IAM role annotations on ServiceAccounts. These must be configured BEFORE applying the Applications to prevent CrashLoopBackOff errors.

```bash
# AWS Load Balancer Controller (REQUIRED before applying aws-load-balancer-controller.yaml)
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn)
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite

# Cert-Manager (REQUIRED before applying cert-manager.yaml)
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw cert_manager_role_arn)
kubectl annotate serviceaccount cert-manager \
  -n cert-manager \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite

# Cluster Autoscaler (REQUIRED before applying cluster-autoscaler.yaml)
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw cluster_autoscaler_role_arn)
kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite
```

**Note:** If you already applied the Applications and pods are crashing, see `TROUBLESHOOTING_AWS_LB_CONTROLLER.md` for fix steps.

#### 3. Apply ArgoCD Applications

After IAM role annotations are configured, apply all ArgoCD Application manifests:

```bash
# Apply all ArgoCD applications
kubectl apply -f gitops/argo-apps/platform/storage-class.yaml
kubectl apply -f gitops/argo-apps/platform/metrics-server.yaml
kubectl apply -f gitops/argo-apps/platform/cert-manager.yaml
kubectl apply -f gitops/argo-apps/platform/cluster-issuers.yaml
kubectl apply -f gitops/argo-apps/observability/prometheus-stack.yaml
kubectl apply -f gitops/argo-apps/observability/elasticsearch.yaml
kubectl apply -f gitops/argo-apps/observability/kibana.yaml
kubectl apply -f gitops/argo-apps/observability/fluent-bit.yaml
kubectl apply -f gitops/argo-apps/observability/otel-collector-config.yaml
kubectl apply -f gitops/argo-apps/observability/otel-collector.yaml
kubectl apply -f gitops/argo-apps/platform/cluster-autoscaler.yaml
kubectl apply -f gitops/argo-apps/platform/argocd.yaml  # Self-management
kubectl apply -f gitops/argo-apps/platform/argocd-ingress.yaml  # ArgoCD ingress management

# Infrastructure ingresses (already configured)
kubectl apply -f gitops/argo-apps/observability/monitoring.yaml
kubectl apply -f gitops/argo-apps/observability/logging.yaml

# Application deployments
kubectl apply -f gitops/argo-apps/apps/simple-time-service-staging.yaml
kubectl apply -f gitops/argo-apps/apps/simple-time-service-prod.yaml
```

**Or apply all at once:**
```bash
kubectl apply -f gitops/argo-apps/apps \
   -f gitops/argo-apps/observability \
   -f gitops/argo-apps/platform
```

**Prerequisites:**
- Terraform must be applied (IAM roles created)
- ArgoCD must be installed (bootstrap)
- EKS cluster must be running
- IAM role annotations configured (Step 2 above)

After applying, ArgoCD will:
- Watch the Git repository and Helm chart repositories
- Auto-sync when changes are pushed to Git or chart versions are updated
- Deploy all Helm charts and Kubernetes resources automatically
- Create SSL certificates via cert-manager when ingresses are created
- Self-heal if resources are manually modified

## How It Works

1. **Bootstrap:** Run `install-eks-addons.sh` to install ArgoCD and apply ingress (one-time)
   - Installs ArgoCD from official manifest
   - Applies ArgoCD ingress (requires AWS Load Balancer Controller)
   - Shows ALB hostname for DNS configuration
2. **Apply Applications:** Apply ArgoCD Application manifests to register Helm charts
   - Includes `argocd-ingress.yaml` so ArgoCD can manage its own ingress via GitOps
3. **GitOps Sync:** ArgoCD monitors Git repository and Helm chart repositories
4. **Auto-Deploy:** ArgoCD automatically syncs when:
   - Changes are pushed to Git (polls every 3 minutes)
   - Helm chart versions are updated in Application manifests
   - Resources are manually modified (self-healing)
5. **Dependencies:** ArgoCD handles dependencies automatically (StorageClass before charts, Elasticsearch before Kibana, etc.)

## Manual Deployment (Alternative)

If you prefer manual deployment instead of ArgoCD, use Helm charts directly:

```bash
helm template monitoring-ingress gitops/helm-charts/observability/monitoring-ingress | kubectl apply -f -
helm template logging-ingress gitops/helm-charts/observability/logging-ingress | kubectl apply -f -
helm template simple-time-service gitops/helm-charts/apps/simple-time-service \
   -f gitops/helm-charts/apps/simple-time-service/values-prod.yaml | kubectl apply -f -
```

## Verify ArgoCD Applications

```bash
# List all ArgoCD applications
kubectl get application -n argocd

# Check specific application status
argocd app get metrics-server
argocd app get aws-load-balancer-controller
argocd app get cert-manager
argocd app get prometheus-stack
argocd app get elasticsearch
argocd app get cluster-autoscaler

# Check sync status of all apps
argocd app list

# Verify Helm releases
helm list --all-namespaces

# Verify resources
kubectl get pods --all-namespaces
kubectl get storageclass gp3
kubectl get clusterissuer

# View sync status in ArgoCD UI
# https://argocd.kart24.shop
```

## Sync Policy Details

All applications use:
- **Automated sync**: `syncPolicy.automated` enabled
- **Prune**: Automatically removes resources deleted from Git
- **Self-heal**: Automatically corrects manual changes
- **CreateNamespace**: Automatically creates namespaces if missing

## Git Repository Configuration

All applications watch:
- **Repository**: `https://gitlab.com/karthikbm2k25/simple-time-service.git`
- **Branch**: `main`
- **Path**: See table above

## Migration from Script to ArgoCD

If you previously used `scripts/install-eks-addons.sh` for direct installation, migrate to ArgoCD:

1. **Bootstrap ArgoCD:** Run `scripts/install-eks-addons.sh` (one-time, now only bootstraps ArgoCD)
2. **Apply Applications:** Apply all ArgoCD Application manifests
3. **Configure IAM:** Set ServiceAccount annotations for IAM roles
4. **Verify:** Check all applications are synced and healthy
5. **Note:** The script now only bootstraps ArgoCD; all addons are managed via GitOps

**Note:** ArgoCD will detect existing Helm releases and take over management. No need to uninstall first.

## Summary

✅ **Application deployments**: Auto-deployed via ArgoCD
✅ **Infrastructure ingresses**: Auto-deployed via ArgoCD
✅ **EKS addons**: All managed via ArgoCD GitOps (Helm charts)
✅ **All resources**: Automatically synced when you push to Git or update chart versions

**Benefits of ArgoCD Management:**
- ✅ Declarative configuration in Git
- ✅ Automatic sync and self-healing
- ✅ Easy rollback via Git history
- ✅ Version control for Helm chart versions
- ✅ No manual `helm install/upgrade` commands needed
- ✅ Consistent state across environments
- ✅ Dependency management handled automatically

**Next Steps:**
1. Run bootstrap script to install ArgoCD (if not already installed)
2. Apply all ArgoCD Application manifests
3. Configure IAM role annotations for ServiceAccounts
4. Verify all applications are synced and healthy in ArgoCD UI
5. Update Helm chart versions as needed (verify compatibility first)

## Version Verification

**IMPORTANT:** Before deploying, verify all Helm chart versions are current and compatible:

- **Metrics Server:** https://github.com/kubernetes-sigs/metrics-server/releases
- **AWS Load Balancer Controller:** https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
- **Cert-Manager:** https://github.com/cert-manager/cert-manager/releases (check Kubernetes compatibility)
- **Prometheus Stack:** https://github.com/prometheus-community/helm-charts/releases
- **Elasticsearch/Kibana:** https://github.com/elastic/helm-charts/releases
- **Fluent-bit:** https://github.com/fluent/helm-charts/releases
- **OpenTelemetry Collector:** https://github.com/open-telemetry/opentelemetry-helm-charts/releases
- **Cluster Autoscaler:** https://github.com/kubernetes/autoscaler/releases
- **ArgoCD:** https://github.com/argoproj/argo-helm/releases

Each application file contains a NOTE with the documentation link for version verification.

