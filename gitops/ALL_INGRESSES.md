# Complete Ingress & Certificate Configuration

All applications and UIs have been configured with ingress resources and Let's Encrypt SSL certificates.

## ✅ All Services Configured

| Service | Domain | Namespace | Certificate Issuer | Status |
|---------|--------|-----------|-------------------|--------|
| **ArgoCD** | `argocd.trainerkarthik.shop` | `argocd` | `letsencrypt-prod` | ✅ Complete |
| **Prometheus** | `prometheus.trainerkarthik.shop` | `monitoring` | `letsencrypt-prod` | ✅ Complete |
| **Grafana** | `grafana.trainerkarthik.shop` | `monitoring` | `letsencrypt-prod` | ✅ Complete |
| **Kibana** | `kibana.trainerkarthik.shop` | `logging` | `letsencrypt-prod` | ✅ Complete |
| **Elasticsearch** | `elasticsearch.trainerkarthik.shop` | `logging` | `letsencrypt-prod` | ✅ Complete |
| **Simple Time Service (Prod)** | `time.trainerkarthik.shop` | `simple-time-service` | `letsencrypt-prod` | ✅ Complete |
| **Simple Time Service (Staging)** | `staging.time.trainerkarthik.shop` | `simple-time-service-staging` | `letsencrypt-staging` | ✅ Complete |

## File Locations

### Infrastructure Services
- **ArgoCD**: `gitops/argocd/argocd-ingress.yaml`
- **Prometheus**: `gitops/monitoring/prometheus-ingress.yaml`
- **Grafana**: `gitops/monitoring/grafana-ingress.yaml`
- **Kibana**: `gitops/logging/kibana-ingress.yaml`
- **Elasticsearch**: `gitops/logging/elasticsearch-ingress.yaml`

### Application Services
- **Base Ingress**: `gitops/apps/simple-time-service/base/ingress.yaml`
- **Prod Patch**: `gitops/apps/simple-time-service/overlays/prod/patch-ingress-prod.yaml`
- **Staging Patch**: `gitops/apps/simple-time-service/overlays/staging/patch-ingress-staging.yaml`

## Certificate Configuration

All ingresses include:
- ✅ `cert-manager.io/cluster-issuer` annotation
- ✅ TLS section with host and secretName
- ✅ Let's Encrypt SSL certificates (automatic issuance and renewal)

### Certificate Issuers
- **Production**: `letsencrypt-prod` (used for all prod services)
- **Staging**: `letsencrypt-staging` (used for staging environment)

## Deployment Commands

### Deploy All Infrastructure Services
```bash
# ArgoCD
kubectl apply -k gitops/argocd/

# Monitoring (Prometheus + Grafana)
kubectl apply -k gitops/monitoring/

# Logging (Kibana + Elasticsearch)
kubectl apply -k gitops/logging/
```

### Deploy Application Services
```bash
# Production
kubectl apply -k gitops/apps/simple-time-service/overlays/prod/

# Staging
kubectl apply -k gitops/apps/simple-time-service/overlays/staging/
```

## Verification

### Check All Ingresses
```bash
kubectl get ingress -A
```

### Check All Certificates
```bash
kubectl get certificate -A
```

### Check Certificate Status
```bash
# Check certificate details
kubectl describe certificate -A

# Check certificate requests
kubectl get certificaterequest -A
```

### Verify Certificate Issuance
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager

# Check certificate events
kubectl describe certificate <cert-name> -n <namespace>
```

## DNS Configuration Required

After deploying ingresses, configure DNS CNAME records:

| Subdomain | Type | Points To |
|-----------|------|-----------|
| `argocd` | CNAME | ALB hostname from ingress |
| `prometheus` | CNAME | ALB hostname from ingress |
| `grafana` | CNAME | ALB hostname from ingress |
| `kibana` | CNAME | ALB hostname from ingress |
| `elasticsearch` | CNAME | ALB hostname from ingress |
| `time` | CNAME | ALB hostname from ingress |
| `staging.time` | CNAME | ALB hostname from ingress |

Get ALB addresses:
```bash
kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
```

## Access URLs

Once DNS is configured and certificates are issued:

- 🔵 **ArgoCD**: https://argocd.trainerkarthik.shop
- 📊 **Prometheus**: https://prometheus.trainerkarthik.shop
- 📈 **Grafana**: https://grafana.trainerkarthik.shop
- 🔍 **Kibana**: https://kibana.trainerkarthik.shop
- 🔎 **Elasticsearch**: https://elasticsearch.trainerkarthik.shop
- ⏰ **Time Service (Prod)**: https://time.trainerkarthik.shop
- ⏰ **Time Service (Staging)**: https://staging.time.trainerkarthik.shop

## Summary

✅ **8 Ingress Resources** configured
✅ **8 SSL Certificates** configured (via cert-manager)
✅ **7 Domains** configured (prod + staging)
✅ **All using Let's Encrypt** for SSL certificates
✅ **All using ALB Ingress Controller** for load balancing
✅ **All configured with HTTPS redirect** (HTTP → HTTPS)

All applications and UIs are ready for deployment with SSL certificates!

