# EKS Setup Scripts

## install-eks-addons.sh

Installs all required components for the EKS cluster:

- **AWS Load Balancer Controller** - Required for ALB Ingress
- **Metrics Server** - Required for HPA and resource metrics
- **ArgoCD** - GitOps deployment tool
- **Cluster Autoscaler** - Optional, for auto-scaling nodes

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **kubectl** installed and configured for your EKS cluster
3. **helm** v3.x installed
4. **jq** installed (for JSON parsing)
5. **EKS cluster** already created via Terraform

## Usage

### Basic Usage (Default Settings)

```bash
./scripts/install-eks-addons.sh
```

### Custom Configuration

Set environment variables to customize:

```bash
export CLUSTER_NAME="simple-time-service-prod"
export AWS_REGION="us-east-1"
export PROJECT_NAME="simple-time-service"

# Options (true/false)
export INSTALL_ALB_CONTROLLER="true"
export INSTALL_ARGOCD="true"
export INSTALL_METRICS_SERVER="true"
export INSTALL_CLUSTER_AUTOSCALER="false"

./scripts/install-eks-addons.sh
```

### One-liner with Custom Cluster

```bash
CLUSTER_NAME="my-cluster" AWS_REGION="us-west-2" ./scripts/install-eks-addons.sh
```

## What It Does

### 1. Prerequisites Check
- Verifies kubectl, helm, aws, jq are installed
- Checks AWS authentication
- Verifies kubectl connection to cluster

### 2. AWS Load Balancer Controller
- Creates IAM policy for ALB controller
- Creates IAM role with OIDC trust relationship
- Creates Kubernetes service account
- Installs controller via Helm
- Configures for your cluster

### 3. Metrics Server
- Installs via Helm
- Required for Horizontal Pod Autoscaling
- Required for resource metrics (kubectl top)

### 4. ArgoCD
- Creates argocd namespace
- Installs ArgoCD via official manifests
- Waits for deployment to be ready
- Shows initial admin password

### 5. Cluster Autoscaler (Optional)
- Creates service account with IAM role
- Installs via Helm
- Configures for your cluster

## Output

The script provides:
- Color-coded status messages
- Installation progress
- Verification of each component
- Next steps and instructions

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
oidc_issuer=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# Get thumbprint
thumbprint=$(openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com -showcerts -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d'=' -f2 | tr -d ':')

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
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Verification

After installation, verify everything is working:

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

To remove installed components:

```bash
# Remove ArgoCD
kubectl delete namespace argocd

# Remove ALB Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Remove Metrics Server
helm uninstall metrics-server -n kube-system

# Remove Cluster Autoscaler (if installed)
helm uninstall cluster-autoscaler -n kube-system
```

## Notes

- The script is idempotent - safe to run multiple times
- IAM resources are not deleted by this script (use Terraform)
- The script requires appropriate AWS permissions
- ArgoCD initial password should be changed after first login

