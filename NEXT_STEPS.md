# Next Steps After Merge Request - Step by Step Guide

## Current Status

✅ **Merge Request Created** - Pipeline triggered with 5 stages:
1. ✅ scan_code - **Completed automatically**
2. ✅ build - **Completed automatically**
3. ✅ docker - **Completed automatically** (Docker image built with commit SHA)
4. ✅ scan_image - **Completed automatically**
5. ⏸️ terraform - **Needs manual action**

---

## Step-by-Step Actions

### Step 1: Review Terraform Plan (Already Done?)

1. Go to GitLab: **CI/CD → Pipelines**
2. Open your merge request's pipeline
3. Find the **`terraform_plan`** job (should be completed)
4. Review the plan output to see what infrastructure will be created:
   - VPC and subnets
   - EKS cluster
   - IAM roles
   - Security groups
   - Networking components

**✅ Action Required:** Verify the plan looks correct

---

### Step 2: Approve and Apply Terraform (MANUAL STEP)

1. In the same pipeline, find the **`terraform_apply`** job
2. It should show a **▶️ Play button** (this means it's waiting for manual approval)
3. Click the **▶️ Play button** to approve and run `terraform apply`
4. Wait for it to complete (can take 10-20 minutes to create EKS cluster)

**⏱️ Estimated Time:** 15-20 minutes

**📋 What happens:**
- Creates VPC with public/private subnets
- Creates EKS cluster with node groups
- Sets up IAM roles and policies
- Configures networking and security groups

**✅ Action Required:** Click play button on `terraform_apply` job

---

### Step 3: Install EKS Addons (After Terraform Completes)

After infrastructure is created, you need to install:
- AWS Load Balancer Controller (for ALB ingress)
- Metrics Server (for resource metrics)
- ArgoCD (for GitOps deployments)
- Cert-Manager (for TLS certificates)

#### Option A: Via GitLab CI (Recommended)

**Current Status:** The `.gitlab-ci-addons.yml` file exists but needs to be included in your main CI.

**Quick Fix - Add to `.gitlab-ci.yml`:**
```yaml
# Add this to your .gitlab-ci.yml include section (around line 183)
include:
  - local: 'infra/.gitlab-ci.yml'
  - local: '.gitlab-ci-addons.yml'  # Add this line
```

**Then run it:**
1. Go to GitLab: **CI/CD → Pipelines → Run Pipeline**
2. Select `main` branch (or your target branch)
3. Add variable: `INSTALL_ADDONS=true`
4. Click "Run pipeline"
5. Find the `install_eks_addons` job and click ▶️ Play button

#### Option B: Manual Installation (Alternative)

If you prefer to install manually:

```bash
# Set variables
export CLUSTER_NAME="simple-time-service-prod"
export AWS_REGION="us-east-1"

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Run installation script
cd /path/to/simple-time-service
./scripts/install-eks-addons.sh
```

**⏱️ Estimated Time:** 5-10 minutes

**✅ Action Required:** Install EKS addons (choose Option A or B)

---

### Step 4: Configure ArgoCD Access (After Addons Installed)

After ArgoCD is installed, get the admin password:

```bash
# Update kubeconfig if not already done
aws eks update-kubeconfig --region us-east-1 --name simple-time-service-prod

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
# Username: admin
# Password: (from command above)
```

**✅ Action Required:** Get ArgoCD credentials and access UI

---

### Step 5: Deploy Application to Kubernetes

After ArgoCD is set up, deploy your application using one of these methods:

#### Option A: Via ArgoCD (Recommended - GitOps)

```bash
# Apply ArgoCD Application manifest
kubectl apply -f gitops/argo-apps/simple-time-service-prod.yaml

# Check status
kubectl get application -n argocd
argocd app get simple-time-service-prod
```

The ArgoCD application will:
- Watch your Git repository
- Sync Kubernetes manifests from `gitops/apps/simple-time-service/overlays/prod`
- Automatically deploy when changes are merged to the `develop` branch

#### Option B: Direct kubectl (For Testing)

```bash
# Deploy directly
kubectl apply -k gitops/apps/simple-time-service/overlays/prod

# Check status
kubectl get pods -n simple-time-service
kubectl get svc -n simple-time-service
kubectl get ingress -n simple-time-service
```

**✅ Action Required:** Deploy application (choose Option A or B)

---

### Step 6: Verify Deployment

After deployment, verify everything is working:

```bash
# Check pods are running
kubectl get pods -n simple-time-service

# Check service
kubectl get svc -n simple-time-service

# Get ingress URL (ALB address)
kubectl get ingress -n simple-time-service

# Test the endpoint
# Replace <ALB-ADDRESS> with the address from ingress
curl https://<ALB-ADDRESS>/
curl https://<ALB-ADDRESS>/healthz
```

**✅ Action Required:** Verify application is running and accessible

---

## Automation Status Summary

| Stage | Status | Action Required |
|-------|--------|-----------------|
| Code Scanning | ✅ Automated | None |
| Build | ✅ Automated | None |
| Docker Build | ✅ Automated | None |
| Image Scanning | ✅ Automated | None |
| Terraform Plan | ✅ Automated | Review output |
| **Terraform Apply** | ⏸️ **Manual** | **Click play button** |
| EKS Addons | ⏸️ **Manual** | Run CI job or script |
| ArgoCD Setup | ⏸️ **Manual** | Get password, configure access |
| App Deployment | ✅ Automated (via ArgoCD) | Apply ArgoCD app manifest |

---

## Quick Checklist

- [ ] Review `terraform_plan` output
- [ ] Click ▶️ Play on `terraform_apply` job
- [ ] Wait for Terraform to complete (~15-20 min)
- [ ] Install EKS addons (Option A or B)
- [ ] Get ArgoCD admin password
- [ ] Deploy application via ArgoCD or kubectl
- [ ] Verify application is running
- [ ] Test endpoint

---

## Troubleshooting

### Terraform Apply Fails

Check:
- AWS credentials are set in GitLab CI/CD variables
- S3 bucket for Terraform state exists
- DynamoDB table for state locking exists
- AWS service quotas are sufficient

### EKS Addons Installation Fails

Check:
- Cluster is fully created and accessible
- kubectl can connect to cluster
- AWS credentials have necessary permissions
- Script has execute permissions

### Application Not Deploying

Check:
- Docker image tag matches commit SHA
- ArgoCD can access Git repository
- Kubernetes manifests are correct
- Namespace exists or CreateNamespace is enabled

---

## Next Steps After First Deployment

1. **Configure DNS** - Point your domain to the ALB address
2. **Set up Monitoring** - Configure Prometheus/Grafana dashboards
3. **Set up Logging** - Configure log aggregation
4. **Configure Secrets** - Set up proper secret management
5. **Enable Auto-scaling** - Configure HPA/VPA if needed

For more details, see:
- `SETUP.md` - Detailed setup guide
- `README.md` - Full documentation
- `RECOMMENDATION.md` - Architecture recommendations

