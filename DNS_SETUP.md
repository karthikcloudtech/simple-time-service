# DNS Configuration Guide

## Wildcard DNS Setup

You can configure a **single wildcard DNS record** that will work for all your subdomains:

```
*.trainerkarthik.shop → ALB (CNAME or A record)
```

## How It Works

1. **DNS Resolution**: All subdomains resolve to the same ALB
   - `prometheus.trainerkarthik.shop` → ALB
   - `grafana.trainerkarthik.shop` → ALB
   - `kibana.trainerkarthik.shop` → ALB
   - `time.trainerkarthik.shop` → ALB
   - `staging.time.trainerkarthik.shop` → ALB

2. **ALB Ingress Controller Routing**: The ALB Ingress Controller uses the `Host` header to route requests:
   - Checks the `host` field in each Ingress resource
   - Routes to the correct backend service based on the hostname
   - Each Ingress has a specific `host` field that matches the subdomain

3. **Automatic Routing**: No additional configuration needed - the ingress controller handles everything

## DNS Configuration

### Option 1: Wildcard CNAME (Recommended)

```
Type: CNAME
Name: *
Value: <ALB-DNS-NAME>
TTL: 300
```

### Option 2: Wildcard A Record (if ALB has static IPs - not recommended)

```
Type: A
Name: *
Value: <ALB-IP-ADDRESS>
TTL: 300
```

**Note**: ALB IPs can change, so CNAME is preferred.

## Getting ALB DNS Name

After deploying ingresses, get the ALB DNS name:

```bash
# Get ALB address from ingress
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'

# Or describe ingress
kubectl describe ingress prometheus-ingress -n monitoring | grep Address
```

## Verification

After DNS configuration, verify:

```bash
# Check DNS resolution
dig prometheus.trainerkarthik.shop
dig grafana.trainerkarthik.shop
dig kibana.trainerkarthik.shop
dig time.trainerkarthik.shop

# All should resolve to the same ALB
```

## How ALB Routes Requests

1. **Request arrives**: `https://prometheus.trainerkarthik.shop`
2. **DNS resolves**: `*.trainerkarthik.shop` → ALB
3. **ALB receives request**: With `Host: prometheus.trainerkarthik.shop` header
4. **Ingress Controller matches**: Finds ingress with `host: prometheus.trainerkarthik.shop`
5. **Routes to service**: `prometheus-kube-prometheus-prometheus:9090`

Each ingress resource specifies:
- **host**: The subdomain (e.g., `prometheus.trainerkarthik.shop`)
- **backend service**: Where to route (e.g., `prometheus-kube-prometheus-prometheus`)

The ALB Ingress Controller automatically handles the routing based on the `Host` header.

## Benefits

✅ **Single DNS record** for all subdomains  
✅ **Automatic routing** by ingress controller  
✅ **No manual configuration** per subdomain  
✅ **Easy to add new subdomains** - just create new ingress with different host  
✅ **Works with Let's Encrypt** - each subdomain gets its own certificate automatically

## Example: Adding a New Subdomain

To add a new service (e.g., `api.trainerkarthik.shop`):

1. Create ingress with `host: api.trainerkarthik.shop`
2. Add `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation
3. Deploy - DNS wildcard already covers it!
4. Cert-manager automatically issues certificate
5. ALB automatically routes based on Host header

No DNS changes needed!

