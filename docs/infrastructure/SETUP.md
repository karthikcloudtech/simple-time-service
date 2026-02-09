# EKS Cluster Setup Guide

## Quick Start

### 1. Prerequisites

Install required tools:

```bash
# macOS
brew install kubectl helm awscli jq

# Linux (Ubuntu/Debian)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

sudo apt-get update && sudo apt-get install -y awscli jq
```

### 2. Configure AWS

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., us-east-1)
# Enter default output format (json)
```

Or set environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. Deploy Infrastructure (Terraform)

```bash
cd infra/environments/prod
terraform init
terraform plan
terraform apply
```

### 4. Install EKS Addons

```bash
# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "simple-time-service-prod")
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Run installation script
./scripts/install-eks-addons.sh
```

### 5. Verify Installation

```bash
# Check all pods are running
kubectl get pods -A

# Check ALB Controller
kubectl get ingressclass

# Check ArgoCD
kubectl get pods -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
# Username: admin
# Password: (check script output or run below command)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## What Gets Installed

### AWS Load Balancer Controller
- Required for ALB Ingress (used in your ingress.yaml)
- Creates Application Load Balancers for Kubernetes Ingress resources
- Handles SSL/TLS termination
- Supports path-based routing

### Metrics Server
- Provides resource metrics to Kubernetes
- Required for `kubectl top` commands
- Required for Horizontal Pod Autoscaling (HPA)
- Required for Vertical Pod Autoscaling (VPA)

### ArgoCD
- GitOps continuous delivery tool
- Syncs Kubernetes resources from Git repositories
- Provides UI for monitoring deployments

### Cert-Manager
- Automatically manages TLS certificates
- Integrates with Let's Encrypt for free SSL certificates
- Automatically renews certificates before expiration

### Cluster Autoscaler (Optional)
- Automatically adjusts node group size
- Scales up when pods can't be scheduled
- Scales down when nodes are underutilized
- Requires IAM role configured in Terraform

## Accessing ArgoCD

After installation, access ArgoCD UI:

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# In another terminal, login
argocd login localhost:8080
# Username: admin
# Password: (from installation output)

# Or get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## Deploying Your Application

### Option 1: Direct Helm Template

```bash
# Staging
helm template simple-time-service gitops/helm-charts/apps/simple-time-service -f gitops/helm-charts/apps/simple-time-service/values-staging.yaml | kubectl apply -f -

# Production
helm template simple-time-service gitops/helm-charts/apps/simple-time-service -f gitops/helm-charts/apps/simple-time-service/values-prod.yaml | kubectl apply -f -
```

### Option 2: ArgoCD (Recommended)

1. Apply ArgoCD Application manifests:
   ```bash
   kubectl apply -f gitops/argo-apps/apps/simple-time-service-staging.yaml
   kubectl apply -f gitops/argo-apps/apps/simple-time-service-prod.yaml
   ```

2. Check status:
   ```bash
   kubectl get application -n argocd
   argocd app get simple-time-service-staging
   argocd app get simple-time-service-prod
   ```

3. Access via UI:
   - Open ArgoCD UI
   - Find your application
   - Monitor sync status

## Troubleshooting

### kubectl can't connect

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name simple-time-service-prod

# Test connection
kubectl cluster-info
```

### ALB Controller not working

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check service account
kubectl describe sa aws-load-balancer-controller -n kube-system

# Check IAM role
kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

### ArgoCD not syncing

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check application status
argocd app get simple-time-service-staging
argocd app get simple-time-service-prod

# Force sync
argocd app sync simple-time-service-staging
argocd app sync simple-time-service-prod
```

### Ingress not creating ALB

```bash
# Check ingress
kubectl describe ingress -n simple-time-service-staging
kubectl describe ingress -n simple-time-service

# Check ingress controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Verify ingress class
kubectl get ingressclass
```

## Next Steps

1. **Configure ArgoCD Applications**
   - Apply ArgoCD application manifests
   - Configure Git repository access
   - Set up sync policies

2. **Set up Secrets**
   - Create secrets for Docker Hub credentials
   - Configure database credentials
   - Set up TLS certificates

3. **Configure DNS**
   - Point your domain to ALB
   - Set up Route53 or external DNS
   - Configure SSL certificates

4. **Monitor and Log**
   - Set up CloudWatch Logs
   - Configure Prometheus/Grafana
   - Set up alerts

## Additional Resources

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

