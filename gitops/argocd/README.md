# ArgoCD Ingress Configuration

ArgoCD is configured to be accessible via `argocd.kart24.shop` with Let's Encrypt SSL certificate.

## Deployment

```bash
# Deploy ArgoCD ingress
kubectl apply -k gitops/argocd/
```

## DNS Configuration

After deployment, get the ALB address:

```bash
kubectl get ingress argocd-ingress -n argocd
```

Create a CNAME record:
- **Name:** `argocd` (or `argocd.kart24.shop` depending on your DNS provider)
- **Type:** CNAME
- **Value:** ALB hostname from ingress status

## Access

After DNS propagation (5-15 minutes):

- **URL:** https://argocd.kart24.shop
- **Username:** `admin`
- **Password:** 
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
  ```

## SSL Certificate

The ingress uses cert-manager with Let's Encrypt. Certificate is automatically created and renewed.

Check certificate status:
```bash
kubectl get certificate -n argocd
kubectl describe certificate argocd-trainerkarthik-shop-tls -n argocd
```

## Troubleshooting

### Certificate not issued
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager

# Check certificate request
kubectl describe certificaterequest -n argocd
```

### Ingress not creating ALB
```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check ingress events
kubectl describe ingress argocd-ingress -n argocd
```

### ArgoCD not accessible
- Verify ArgoCD pods are running: `kubectl get pods -n argocd`
- Check ArgoCD service: `kubectl get svc argocd-server -n argocd`
- Verify DNS resolution: `dig argocd.kart24.shop`

