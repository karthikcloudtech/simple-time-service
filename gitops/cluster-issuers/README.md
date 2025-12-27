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

## Update Email Address

Edit `clusterissuer.yaml` and replace `admin@example.com` with your email address:

```yaml
email: your-email@example.com
```

Then reapply:
```bash
kubectl apply -k gitops/cluster-issuers/
```

