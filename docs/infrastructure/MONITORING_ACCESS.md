# Monitoring Stack Access via Domain

This guide explains how to access Prometheus, Grafana, and Kibana using Let's Encrypt certificates automatically issued by cert-manager.

## Domains Configured

- **Prometheus**: `prometheus.kart24.shop`
- **Grafana**: `grafana.kart24.shop`
- **Kibana**: `kibana.kart24.shop`
- **Time Service**: `time.kart24.shop` (already configured)

## Automatic Certificate Management

**No manual certificate creation needed!** Cert-manager automatically:
- Issues Let's Encrypt certificates for each subdomain
- Creates TLS secrets automatically
- Renews certificates before expiration
- Handles HTTP-01 challenge via ALB

The ingresses use `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation, which triggers automatic certificate creation.

## Step 1: Configure DNS

Point the subdomains to your ALB:

- `prometheus.kart24.shop` → ALB
- `grafana.kart24.shop` → ALB
- `kibana.kart24.shop` → ALB

## Step 2: Deploy Ingress Resources

```bash
# Deploy monitoring ingresses (Prometheus + Grafana)
kubectl apply -k gitops/monitoring/

# Deploy logging ingress (Kibana)
kubectl apply -k gitops/logging/
```

## Step 3: Access Services

After DNS propagation (usually a few minutes):

### Prometheus
- **URL**: https://prometheus.kart24.shop
- **Features**: Query metrics, view targets, alerts

### Grafana
- **URL**: https://grafana.kart24.shop
- **Username**: `admin`
- **Password**: Get with:
  ```bash
  kubectl get secret prometheus-grafana -n monitoring \
    -o jsonpath="{.data.admin-password}" | base64 -d && echo
  ```

### Kibana
- **URL**: https://kibana.kart24.shop
- **Features**: View application logs, create dashboards

## Verification

Check ingress status:

```bash
# Check monitoring ingresses
kubectl get ingress -n monitoring

# Check logging ingress
kubectl get ingress -n logging

# Check ALB status
kubectl describe ingress -n monitoring
kubectl describe ingress -n logging
```

## Troubleshooting

### Certificate Issues

1. **Certificate not issued**: Check cert-manager status:
   ```bash
   kubectl get certificate -A
   kubectl get certificaterequest -A
   kubectl describe certificate <cert-name> -n <namespace>
   ```

2. **Certificate pending**: Check cert-manager logs:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

3. **HTTP-01 challenge failed**: Ensure DNS points to ALB and ALB is accessible

### DNS Issues

1. **502 Bad Gateway**: Check DNS resolution:
   ```bash
   dig prometheus.kart24.shop
   dig grafana.kart24.shop
   dig kibana.kart24.shop
   ```

2. **DNS not resolving**: Verify DNS records point to ALB

### Service Issues

1. **Service not found**: Ensure Prometheus/Grafana/Kibana are installed:
   ```bash
   kubectl get svc -n monitoring
   kubectl get svc -n logging
   ```

2. **Service not ready**: Check pod status:
   ```bash
   kubectl get pods -n monitoring
   kubectl get pods -n logging
   ```

## Certificate Management

Certificates are automatically managed by cert-manager:

- **Automatic issuance**: Certificates are created when ingresses are deployed
- **Automatic renewal**: Certificates are renewed 30 days before expiration
- **No manual intervention**: Let's Encrypt handles everything via HTTP-01 challenge

To check certificate status:
```bash
# List all certificates
kubectl get certificate -A

# Check specific certificate
kubectl describe certificate prometheus-kart24-shop-tls -n monitoring

# View certificate secret (auto-created)
kubectl get secret prometheus-kart24-shop-tls -n monitoring
```

## Security Notes

- All traffic is encrypted with TLS/SSL
- HTTPS redirect is enabled (HTTP → HTTPS)
- Each subdomain gets its own Let's Encrypt certificate
- Certificates are automatically renewed by cert-manager
- Access is via AWS ALB with proper security policies
- HTTP-01 challenge is completed automatically via ALB

