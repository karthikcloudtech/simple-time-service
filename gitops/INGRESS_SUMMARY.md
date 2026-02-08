# Ingress Configuration Summary

All services are configured to use your domain `kart24.shop` with Let's Encrypt SSL certificates.

## Services and Domains

| Service | Domain | Namespace | Port | Status |
|---------|--------|-----------|------|--------|
| **ArgoCD** | `argocd.kart24.shop` | `argocd` | 80 | ✅ Configured |
| **Prometheus** | `prometheus.kart24.shop` | `monitoring` | 9090 | ✅ Configured |
| **Grafana** | `grafana.kart24.shop` | `monitoring` | 80 | ✅ Configured |
| **Kibana** | `kibana.kart24.shop` | `logging` | 5601 | ✅ Configured |
| **Elasticsearch** | `elasticsearch.kart24.shop` | `logging` | 9200 | ✅ Configured |
| **Simple Time Service** | `time.kart24.shop` | `simple-time-service` | 80 | ✅ Configured |

## Deployment Instructions

All ingresses are managed by Helm charts and deployed via ArgoCD. To manually deploy:

### 1. Deploy ArgoCD Ingress
```bash
helm template argocd-ingress gitops/helm-charts/argocd-ingress | kubectl apply -f -
```

### 2. Deploy Monitoring Ingresses (Prometheus + Grafana)
```bash
helm template monitoring-ingress gitops/helm-charts/monitoring-ingress | kubectl apply -f -
```

### 3. Deploy Logging Ingresses (Kibana + Elasticsearch)
```bash
helm template logging-ingress gitops/helm-charts/logging-ingress | kubectl apply -f -
```

### 4. Deploy Application Ingress
```bash
helm template simple-time-service gitops/helm-charts/simple-time-service -f gitops/helm-charts/simple-time-service/values-prod.yaml | kubectl apply -f -
```

## DNS Configuration

After deploying ingresses, get the ALB addresses and configure DNS:

```bash
# Get all ALB addresses
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.spec.rules[0].host}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
```

For each service, create a CNAME record:
- **Name:** `argocd` (or full subdomain depending on DNS provider)
- **Type:** CNAME
- **Value:** ALB hostname from ingress status

## SSL Certificates

All ingresses use:
- **ClusterIssuer:** `letsencrypt-prod`
- **Certificate Provider:** Let's Encrypt (via cert-manager)
- **Auto-renewal:** Enabled

Certificates are automatically created when ingresses are deployed. Check status:

```bash
# Check certificates
kubectl get certificate -A

# Check certificate details
kubectl describe certificate <certificate-name> -n <namespace>
```

## Access Credentials

### ArgoCD
- **URL:** https://argocd.kart24.shop
- **Username:** `admin`
- **Password:** 
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
  ```

### Grafana
- **URL:** https://grafana.kart24.shop
- **Default Username:** `admin`
- **Default Password:** Check Grafana secret or Helm values

### Prometheus
- **URL:** https://prometheus.kart24.shop
- **No authentication by default** (consider adding authentication)

### Kibana
- **URL:** https://kibana.kart24.shop
- **Default Username:** `elastic`
- **Password:** Check Elasticsearch secret

### Elasticsearch
- **URL:** https://elasticsearch.kart24.shop
- **Default Username:** `elastic`
- **Password:** Check Elasticsearch secret
- **⚠️ Security Note:** Exposing Elasticsearch publicly is not recommended for production. Consider restricting access or using authentication.

## Verification

After DNS propagation (5-15 minutes), verify access:

```bash
# Check ingress status
kubectl get ingress -A

# Check certificate status
kubectl get certificate -A

# Test endpoints (after DNS is configured)
curl -I https://argocd.kart24.shop
curl -I https://prometheus.kart24.shop
curl -I https://grafana.kart24.shop
curl -I https://kibana.kart24.shop
curl -I https://elasticsearch.kart24.shop
```

## Troubleshooting

### Ingress not creating ALB
```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check ingress events
kubectl describe ingress <ingress-name> -n <namespace>
```

### Certificate not issued
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager

# Check certificate request
kubectl describe certificaterequest -n <namespace>
```

### DNS not resolving
- Verify CNAME records are correct
- Check DNS propagation: `dig argocd.kart24.shop`
- Ensure ALB is created and has a hostname

