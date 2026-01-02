# Troubleshooting AWS Load Balancer Controller CrashLoopBackOff

## Issue
AWS Load Balancer Controller pod is in `CrashLoopBackOff` state. This typically happens when:
1. ServiceAccount is missing IAM role annotation
2. IAM role doesn't exist or has wrong permissions
3. Cluster name mismatch
4. Multiple deployments conflicting
5. **VPC ID not specified** (when running on nodes with IMDSv2 or metadata unavailable)

## Quick Diagnosis

### 1. Check Pod Logs
```bash
# Get the crashing pod name
kubectl get pods -n kube-system | grep aws-load-balancer-controller

# Check logs (replace POD_NAME with actual pod name)
kubectl logs -n kube-system aws-load-balancer-controller-6488ff56b7-kw7vk --tail=50

# Common errors:
# - "failed to get AWS region" → Missing IAM role annotation
# - "failed to assume role" → Wrong IAM role ARN or permissions
# - "cluster not found" → Wrong cluster name
# - "failed to introspect vpcID from EC2Metadata" → VPC ID not specified (IMDSv2 issue)
```

### 2. Check ServiceAccount
```bash
# Check if ServiceAccount exists
kubectl get serviceaccount aws-load-balancer-controller -n kube-system

# Check IAM role annotation
kubectl get serviceaccount aws-load-balancer-controller -n kube-system \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# If empty, you need to annotate it
```

### 3. Check Deployment Status
```bash
# Check deployment
kubectl get deployment aws-load-balancer-controller -n kube-system

# Check if there are multiple deployments
kubectl get deployments -n kube-system | grep aws-load-balancer-controller

# Check replica sets
kubectl get replicaset -n kube-system | grep aws-load-balancer-controller
```

## Solution Steps

### Step 1: Get IAM Role ARN from Terraform
```bash
cd infra/environments/prod
terraform output aws_load_balancer_controller_role_arn
```

### Step 2: Annotate ServiceAccount
```bash
# Replace <ROLE_ARN> with the actual ARN from Step 1
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn)

kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn="$ROLE_ARN" \
  --overwrite
```

### Step 3: Delete the Crashing Pod
```bash
# Delete the crashing pod (it will be recreated automatically)
kubectl delete pod aws-load-balancer-controller-6488ff56b7-kw7vk -n kube-system

# Or delete all pods to restart with correct configuration
kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Step 4: Verify Pods are Running
```bash
# Wait a few seconds, then check
kubectl get pods -n kube-system | grep aws-load-balancer-controller

# All pods should be Running
```

### Step 5: Add VPC ID (If Running on IMDSv2 Nodes)

If you see the error `"failed to introspect vpcID from EC2Metadata"`, you need to specify the VPC ID explicitly:

```bash
# Get VPC ID from Terraform
VPC_ID=$(terraform -chdir=infra/environments/prod output -raw vpc_id)
echo "VPC ID: $VPC_ID"

# Update the ArgoCD Application to include VPC ID
# Edit gitops/argo-apps/aws-load-balancer-controller.yaml
# Replace <VPC_ID> in extraArgs with the actual VPC ID:
#   - name: extraArgs
#     value: "{--aws-vpc-id=vpc-xxxxxxxxx}"

# Or patch the Helm release directly (temporary fix):
helm upgrade aws-load-balancer-controller aws/aws-load-balancer-controller \
  -n kube-system \
  --reuse-values \
  --set extraArgs="{--aws-vpc-id=$VPC_ID}"

# Restart pods
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

**Permanent Fix:** Update `gitops/argo-apps/aws-load-balancer-controller.yaml`:
```yaml
- name: extraArgs
  value: "{--aws-vpc-id=vpc-xxxxxxxxx}"  # Replace with actual VPC ID
```

Then commit and push - ArgoCD will sync automatically.

### Step 6: Check Ingress Status
```bash
# Check if ingress is creating ALB
kubectl get ingress argocd-ingress -n argocd

# Check ingress events
kubectl describe ingress argocd-ingress -n argocd

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

## If Multiple Deployments Exist

If ArgoCD created a new deployment while the old one still exists:

### Option A: Let ArgoCD Manage (Recommended)
```bash
# Delete the old deployment manually
kubectl get deployment -n kube-system | grep aws-load-balancer-controller

# Identify the old one (usually has different name or older creation time)
# Delete the old deployment (NOT the one managed by ArgoCD)
kubectl delete deployment <OLD_DEPLOYMENT_NAME> -n kube-system

# ArgoCD will sync and create the correct one
```

### Option B: Scale Down Old Deployment
```bash
# Scale down the old deployment to 0
kubectl scale deployment <OLD_DEPLOYMENT_NAME> -n kube-system --replicas=0
```

## Verify IAM Role Permissions

If pods still crash after annotation, verify IAM role has correct permissions:

```bash
# Get the role ARN
ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn)

# Check role policies (requires AWS CLI)
aws iam list-attached-role-policies --role-name <ROLE_NAME>
aws iam list-role-policies --role-name <ROLE_NAME>
```

Required policies:
- `AWSLoadBalancerControllerIAMPolicy` (AWS managed policy)
- Or equivalent custom policy with ELB, EC2, and Route53 permissions

## Common Error Messages

### "failed to get AWS region"
- **Cause**: Missing IAM role annotation
- **Fix**: Annotate ServiceAccount (Step 2 above)

### "failed to assume role"
- **Cause**: Wrong IAM role ARN or trust policy issue
- **Fix**: 
  1. Verify role ARN is correct
  2. Check OIDC provider is configured
  3. Verify trust policy includes correct ServiceAccount

### "cluster not found"
- **Cause**: Wrong cluster name in Helm values
- **Fix**: Verify cluster name matches actual EKS cluster name
  ```bash
  kubectl get configmap aws-auth -n kube-system -o yaml | grep cluster-name
  # Or check Terraform output
  terraform -chdir=infra/environments/prod output cluster_name
  ```

### "UnauthorizedOperation"
- **Cause**: IAM role missing required permissions
- **Fix**: Attach `AWSLoadBalancerControllerIAMPolicy` to the IAM role

## Prevention

To prevent this issue in the future:

1. **Always annotate ServiceAccount before applying ArgoCD Application:**
   ```bash
   # Do this BEFORE applying argocd-ingress.yaml
   ROLE_ARN=$(terraform -chdir=infra/environments/prod output -raw aws_load_balancer_controller_role_arn)
   kubectl annotate serviceaccount aws-load-balancer-controller \
     -n kube-system \
     eks.amazonaws.com/role-arn="$ROLE_ARN" \
     --overwrite
   ```

2. **Check ArgoCD Application sync status:**
   ```bash
   kubectl get application aws-load-balancer-controller -n argocd
   argocd app get aws-load-balancer-controller
   ```

3. **Monitor pod status after ArgoCD sync:**
   ```bash
   watch kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

## Still Having Issues?

1. Check ArgoCD Application status:
   ```bash
   kubectl describe application aws-load-balancer-controller -n argocd
   ```

2. Check Helm release:
   ```bash
   helm list -n kube-system | grep aws-load-balancer-controller
   helm get values aws-load-balancer-controller -n kube-system
   ```

3. Review ArgoCD sync logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100 | grep aws-load-balancer-controller
   ```

