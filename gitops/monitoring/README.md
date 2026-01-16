# Monitoring Stack Ingress Configuration

This directory contains Ingress resources for accessing Prometheus and Grafana via your domain.

## Domains

- **Prometheus**: `prometheus.kart24.shop`
- **Grafana**: `grafana.kart24.shop`

## Prerequisites

1. **Wildcard Certificate Secret**: You need to create a Kubernetes secret with your wildcard certificate:

```bash
# Using the provided script
CERT_FILE=/path/to/your/cert.crt KEY_FILE=/path/to/your/key.key \
  ./scripts/create-wildcard-cert-secret.sh

# Or manually
kubectl create secret tls wildcard-trainerkarthik-shop-tls \
  --cert=/path/to/cert.crt \
  --key=/path/to/key.key \
  -n monitoring
```

2. **DNS Configuration**: Point the subdomains to your ALB:
   - `prometheus.kart24.shop` → ALB
   - `grafana.kart24.shop` → ALB

## Deployment

```bash
# Apply monitoring ingresses
kubectl apply -k gitops/monitoring/

# Or via ArgoCD (recommended)
kubectl apply -f gitops/argo-apps/monitoring.yaml  # Create this if needed
```

## Access

After deployment and DNS propagation:

- **Prometheus**: https://prometheus.kart24.shop
- **Grafana**: https://grafana.kart24.shop
  - Default username: `admin`
  - Get password: `kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d`

## Troubleshooting

1. **Certificate not found**: Ensure the secret exists in the `monitoring` namespace
2. **502 Bad Gateway**: Check that Prometheus/Grafana services are running
3. **DNS not resolving**: Verify DNS records point to the ALB

