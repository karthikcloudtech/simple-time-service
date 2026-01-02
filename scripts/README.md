# EKS Setup Scripts

## install-eks-addons.sh

**Primary Purpose**: Bootstrap ArgoCD for GitOps-based addon management

This script supports two modes:
- **GitOps Mode (Default)**: Only installs ArgoCD, which then manages all addons via GitOps
- **Manual Mode**: Installs all components directly (fallback/legacy mode)

### Recommended: GitOps Mode

After ArgoCD is installed, all addons are managed via:
- `gitops/argo-apps/*.yaml` - ArgoCD Application manifests
- `gitops/helm-charts/*/values.yaml` - Helm values files

See `gitops/argo-apps/README.md` for details on ArgoCD Applications.

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **kubectl** installed and configured for your EKS cluster
3. **helm** v3.x installed (only required for manual mode)
4. **jq** installed (only required for manual mode)
5. **EKS cluster** already created via Terraform

## Usage

### GitOps Mode (Recommended)

```bash
# Default: Bootstraps ArgoCD only
./scripts/install-eks-addons.sh

# Or explicitly set mode
INSTALL_MODE=gitops ./scripts/install-eks-addons.sh
```

After ArgoCD is installed:
1. Get ArgoCD admin password (shown in script output)
2. Apply ArgoCD Applications: `kubectl apply -f gitops/argo-apps/*.yaml`
3. ArgoCD will automatically sync and manage all addons

### Manual Mode (Fallback)

For emergency scenarios or legacy deployments:

```bash
INSTALL_MODE=manual ./scripts/install-eks-addons.sh
```

### Custom Configuration

```bash
export CLUSTER_NAME="simple-time-service-prod"
export AWS_REGION="us-east-1"
export PROJECT_NAME="simple-time-service"
export INSTALL_MODE="gitops"  # or "manual"

# For manual mode, control individual components:
export INSTALL_ALB_CONTROLLER="true"
export INSTALL_METRICS_SERVER="true"
export INSTALL_CERT_MANAGER="true"
export INSTALL_PROMETHEUS="true"
export INSTALL_EFK="true"
export INSTALL_OTEL_COLLECTOR="true"
export INSTALL_CLUSTER_AUTOSCALER="false"

./scripts/install-eks-addons.sh
```

### Verbose Output

```bash
VERBOSE=true ./scripts/install-eks-addons.sh
```

## What It Does

### GitOps Mode (Default)

1. **Prerequisites Check**
   - Verifies kubectl and aws are installed
   - Checks AWS authentication
   - Verifies kubectl connection to cluster

2. **ArgoCD Bootstrap**
   - Creates argocd namespace
   - Installs ArgoCD from official manifest
   - Waits for ArgoCD server to be ready
   - Shows next steps for applying ArgoCD Applications

3. **Next Steps**
   - Apply ArgoCD Applications from `gitops/argo-apps/`
   - ArgoCD manages all addons via GitOps

### Manual Mode

1. **Prerequisites Check**
   - Verifies kubectl, helm, aws, jq are installed
   - Checks AWS authentication
   - Verifies kubectl connection to cluster

2. **Core Components**
   - AWS Load Balancer Controller
   - Metrics Server
   - Cert-Manager

3. **Monitoring & Logging**
   - Prometheus Stack
   - EFK Stack (Elasticsearch, Fluent-bit, Kibana)
   - OpenTelemetry Collector

4. **Autoscaling**
   - Cluster Autoscaler (optional)

## GitOps Workflow

### Initial Setup

```bash
# 1. Bootstrap ArgoCD
./scripts/install-eks-addons.sh

# 2. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 3. Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 4. Apply ArgoCD Applications
kubectl apply -f gitops/argo-apps/*.yaml

# 5. ArgoCD will automatically sync all addons
```

### Ongoing Management

- Edit files in `gitops/argo-apps/` and `gitops/helm-charts/`
- Commit and push to Git
- ArgoCD automatically syncs changes (if auto-sync enabled)
- Or manually sync via UI or CLI: `argocd app sync <app-name>`

## Troubleshooting

### kubectl not connecting

```bash
# Update kubeconfig manually
aws eks update-kubeconfig --region us-east-1 --name simple-time-service-prod
```

### OIDC Provider Missing

The script will attempt to create the OIDC provider automatically. If it fails:

```bash
# Get OIDC issuer
oidc_issuer=$(aws eks describe-cluster --name $CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# Get thumbprint
thumbprint=$(openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com \
  -showcerts -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>/dev/null | \
  openssl x509 -fingerprint -noout -sha1 | cut -d'=' -f2 | tr -d ':')

# Create provider
aws iam create-open-id-connect-provider \
  --url "https://${oidc_issuer}" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$thumbprint"
```

### IAM Policy Already Exists

If you see errors about IAM resources already existing, that's okay - the script will reuse them.

### ArgoCD Password

To get ArgoCD password later:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### ArgoCD Not Syncing

```bash
# Check ArgoCD Applications status
kubectl get applications -n argocd

# Check specific application
argocd app get <app-name>

# Force sync
argocd app sync <app-name>

# Or via kubectl
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}'
```

## Verification

### GitOps Mode

```bash
# Check ArgoCD
kubectl get pods -n argocd
kubectl get applications -n argocd

# Check ArgoCD Applications status
kubectl get applications -n argocd -o wide

# Check all addons managed by ArgoCD
kubectl get pods --all-namespaces
```

### Manual Mode

```bash
# Check ALB Controller
kubectl get ingressclass
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check Metrics Server
kubectl top nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

# Check ArgoCD
kubectl get pods -n argocd
kubectl get svc -n argocd

# Check all components
kubectl get pods -A
```

## Cleanup

### GitOps Mode

```bash
# Remove ArgoCD Applications
kubectl delete -f gitops/argo-apps/*.yaml

# Remove ArgoCD
kubectl delete namespace argocd
```

### Manual Mode

```bash
# Remove ArgoCD
kubectl delete namespace argocd

# Remove ALB Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Remove Metrics Server
helm uninstall metrics-server -n kube-system

# Remove Cert-Manager
helm uninstall cert-manager -n cert-manager

# Remove Prometheus
helm uninstall prometheus -n monitoring

# Remove EFK Stack
helm uninstall elasticsearch -n logging
helm uninstall kibana -n logging
helm uninstall fluent-bit -n logging

# Remove OpenTelemetry Collector
helm uninstall otel-collector -n observability

# Remove Cluster Autoscaler (if installed)
helm uninstall cluster-autoscaler -n kube-system
```

## Related Scripts

- `install-eks-addons-bootstrap.sh` - Minimal bootstrap script (only ArgoCD)
- `check-helm-versions.sh` - Check latest Helm chart versions

## Notes

- **GitOps Mode is Recommended**: Provides better management, version control, and rollback capabilities
- **Script is Idempotent**: Safe to run multiple times
- **IAM Resources**: Not deleted by this script (use Terraform)
- **ArgoCD Password**: Should be changed after first login
- **GitOps Paths**: Script uses `gitops/` directory structure consistently

## Migration from Manual to GitOps

If you have manually installed addons and want to migrate to GitOps:

1. Bootstrap ArgoCD: `INSTALL_MODE=gitops ./scripts/install-eks-addons.sh`
2. Apply ArgoCD Applications: `kubectl apply -f gitops/argo-apps/*.yaml`
3. ArgoCD will detect existing resources and adopt them
4. Future changes should be made via GitOps (edit files in `gitops/`)

See `MIGRATION_TO_ARGOCD.md` for detailed migration guide.
