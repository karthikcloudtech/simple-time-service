# IAM Role Annotation Fix for EKS ServiceAccounts

## Problem

When Helm charts create ServiceAccounts, they don't automatically include the IAM role annotations needed for IRSA (IAM Roles for Service Accounts). This causes pods to fail with credential errors like:

```
NoCredentialProviders: no valid providers in chain
```

## Components Affected

1. **AWS Load Balancer Controller** - Fixed in `scripts/install-eks-addons.sh`
2. **Cluster Autoscaler** - Fixed in `gitops/argo-apps/cluster-autoscaler.yaml`
3. **Cert-Manager** - Fixed in `gitops/argo-apps/cert-manager.yaml`

## Solution

### Permanent Fix (GitOps)

The IAM role annotations are now included directly in the ArgoCD Application manifests as Helm parameters:

#### Cluster Autoscaler
```yaml
- name: serviceAccount.annotations.eks\.amazonaws\.com/role-arn
  value: "arn:aws:iam::017019814021:role/simple-time-service-cluster-autoscaler-role"
```

#### Cert-Manager
```yaml
- name: serviceAccount.annotations.eks\.amazonaws\.com/role-arn
  value: "arn:aws:iam::017019814021:role/simple-time-service-cert-manager-role"
```

#### AWS Load Balancer Controller
The installation script (`scripts/install-eks-addons.sh`) creates the ServiceAccount with the annotation before installing the Helm chart:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $alb_role_arn
EOF
```

### Manual Fix (If Already Deployed)

If components are already deployed without annotations, you can fix them manually:

```bash
# Get IAM role ARNs from Terraform
cd infra/environments/prod
ALB_ROLE=$(terraform output -raw aws_load_balancer_controller_role_arn)
AUTOSCALER_ROLE=$(terraform output -raw cluster_autoscaler_role_arn)
CERT_MANAGER_ROLE=$(terraform output -raw cert_manager_role_arn)

# Annotate ServiceAccounts
kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn="$ALB_ROLE" --overwrite

kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler -n kube-system \
  eks.amazonaws.com/role-arn="$AUTOSCALER_ROLE" --overwrite

kubectl annotate serviceaccount cert-manager -n cert-manager \
  eks.amazonaws.com/role-arn="$CERT_MANAGER_ROLE" --overwrite

# Restart pods to pick up the new credentials
kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
kubectl rollout restart deployment cert-manager -n cert-manager
```

## Verification

Check that pods are running without credential errors:

```bash
# Check Cluster Autoscaler
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=20

# Check AWS Load Balancer Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20

# Check Cert-Manager
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=20
```

You should see normal operational logs, not credential errors.

## How IRSA Works

1. **IAM Role**: Created by Terraform with trust policy for EKS OIDC provider
2. **ServiceAccount Annotation**: Links the Kubernetes ServiceAccount to the IAM role
3. **Pod Token**: EKS injects AWS credentials via a projected service account token
4. **AWS SDK**: Pods use these credentials to call AWS APIs

## Files Modified

- `gitops/argo-apps/cluster-autoscaler.yaml` - Added IAM role annotation parameter
- `gitops/argo-apps/cert-manager.yaml` - Added IAM role annotation parameter
- `scripts/install-eks-addons.sh` - Already had the fix for AWS Load Balancer Controller

## Next Steps

When deploying to a new environment:

1. Run Terraform to create IAM roles
2. Update the IAM role ARNs in the ArgoCD Application manifests
3. Run the installation script - it will handle everything automatically
4. ArgoCD will maintain the correct annotations via GitOps

## References

- [AWS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Cluster Autoscaler Helm Chart](https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler)
- [Cert-Manager Helm Chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
