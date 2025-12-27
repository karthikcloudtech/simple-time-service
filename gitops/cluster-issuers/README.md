# ClusterIssuer Configuration

This directory contains ClusterIssuer resources for Let's Encrypt SSL certificates.

## ClusterIssuers

- **letsencrypt-prod**: Production Let's Encrypt issuer
- **letsencrypt-staging**: Staging Let's Encrypt issuer (for testing)

## Apply ClusterIssuers

```bash
# Apply ClusterIssuers
kubectl apply -k gitops/cluster-issuers/
```

## Verify

```bash
# Check ClusterIssuers
kubectl get clusterissuer

# Check status
kubectl describe clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-staging
```

## Important Notes

1. **Cluster-scoped**: ClusterIssuers are cluster-scoped resources (not namespace-scoped)
2. **One-time setup**: Only needs to be applied once per cluster
3. **Email**: Update the email address in `clusterissuer.yaml` with your actual email
4. **Required**: Cert-manager must be installed before applying ClusterIssuers
5. **DNS-01 Challenge**: These ClusterIssuers use DNS-01 challenge with Route53 (required for ALB)
6. **IAM Role**: Cert-manager service account needs IAM role annotation for Route53 access

## DNS-01 Challenge Setup

These ClusterIssuers are configured to use DNS-01 challenge with Route53, which is required for AWS ALB Ingress Controller.

### Prerequisites

1. **Terraform Applied**: The cert-manager IAM role must be created via Terraform:
   ```bash
   cd infra/environments/prod
   terraform apply
   ```

2. **Cert-Manager Service Account**: Annotate the cert-manager service account with the IAM role ARN:
   ```bash
   # Get the cert-manager role ARN from Terraform outputs
   terraform output cert_manager_role_arn
   
   # Annotate the cert-manager service account
   kubectl annotate serviceaccount cert-manager \
     -n cert-manager \
     eks.amazonaws.com/role-arn=<CERT_MANAGER_ROLE_ARN> \
     --overwrite
   ```

3. **Restart cert-manager pods** to pick up the new IAM role:
   ```bash
   kubectl rollout restart deployment cert-manager -n cert-manager
   kubectl rollout restart deployment cert-manager-webhook -n cert-manager
   kubectl rollout restart deployment cert-manager-cainjector -n cert-manager
   ```

### Route53 Hosted Zone

Ensure you have a Route53 hosted zone for `trainerkarthik.shop`. The cert-manager IAM role has permissions to manage DNS records in all hosted zones.

## Update Email Address

Edit `clusterissuer.yaml` and replace `admin@example.com` with your email address:

```yaml
email: your-email@example.com
```

Then reapply:
```bash
kubectl apply -k gitops/cluster-issuers/
```

