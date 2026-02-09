# Canary Deployment Setup - Complete Guide

Complete implementation of ArgoCD Rollouts with Prometheus-based canary deployment for simple-time-service.

## Quick Start (5 minutes)

### 1. Deploy to Kubernetes
```bash
helm template simple-time-service gitops/helm-charts/apps/simple-time-service -f gitops/helm-charts/apps/simple-time-service/values-prod.yaml | kubectl apply -f -
```

### 2. Trigger Canary Deployment
```bash
kubectl set image rollout/simple-time-service \
  simple-time-service=karthikbm2k25/simple-time-service:new-version \
  -n simple-time-service
```

### 3. Monitor Progress
```bash
# Watch rollout stages: 20% → 50% → 100%
kubectl get rollout -n simple-time-service -w

# Check analysis results
kubectl get analysisrun -n simple-time-service -w

# See pod distribution
kubectl get pods -n simple-time-service -L version
```

## What Was Created

### Core Resources

| Component | File | Purpose |
|-----------|------|---------|
| **Rollout** | `templates/rollout.yaml` | Canary deployment strategy (20% → 50% → 100%) |
| **4xx Analysis** | `templates/analysis-template-4xx.yaml` | Monitors client errors, rolls back if >50% |
| **5xx Analysis** | `templates/analysis-template-5xx.yaml` | Monitors server errors, rolls back if >10% |
| **Services** | `templates/service.yaml` | Main + stable + canary services |

### Environment-Specific Values
- `values.yaml` - Base configuration
- `values-staging.yaml` - Staging overrides (branch: develop)
- `values-prod.yaml` - Production overrides (branch: main, 3 replicas)

## Canary Strategy

```
Deploy New Version
    ↓
20% traffic → Analyze 4xx & 5xx errors (5 min)
    ↓
50% traffic → Analyze 4xx & 5xx errors (5 min)  
    ↓
100% traffic → Promotion complete
    ↓ (if analysis fails)
AUTOMATIC ROLLBACK to stable version
```

## Prometheus Metrics

### 4xx Error Rate
- **Query**: `(sum(rate(http_requests_total{status=~"4..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100`
- **Success**: < 10%
- **Failure**: ≥ 50%

### 5xx Error Rate
- **Query**: `(sum(rate(http_requests_total{status=~"5..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100`
- **Success**: < 2%
- **Failure**: ≥ 10%

### Canary vs Stable Comparison
- **4xx Difference**: Success ≤ 5%, Failure > 10%
- **5xx Difference**: Success ≤ 2%, Failure > 5%

## Operations Commands

### View Status
```bash
# Rollout status
kubectl get rollout -n simple-time-service
kubectl describe rollout simple-time-service -n simple-time-service

# Analysis results
kubectl get analysisrun -n simple-time-service
kubectl describe analysisrun -n simple-time-service

# Pod versions
kubectl get pods -n simple-time-service -L version
```

### Manual Rollback
```bash
kubectl rollout undo rollout.argoproj.io/simple-time-service -n simple-time-service
```

### Check Metrics
```bash
# In Prometheus UI at http://prometheus.monitoring:9090/
# Run these queries to see what analysis checks:

# 4xx rate (should be < 10%)
(sum(rate(http_requests_total{status=~"4..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100

# 5xx rate (should be < 2%)  
(sum(rate(http_requests_total{status=~"5..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100
```

## Customization

### Adjust Error Thresholds
Edit `base/analysis-template-4xx.yaml` or `base/analysis-template-5xx.yaml`:
```yaml
successCondition: result < 10  # Change this threshold
failureCondition: result >= 50 # Change this threshold
```

### Change Traffic Progression
Edit `base/rollout.yaml`:
```yaml
steps:
  - setWeight: 20      # First phase %
  - pause:
      duration: 5m     # First phase duration
  - setWeight: 50      # Second phase %
  - pause:
      duration: 5m     # Second phase duration
  - setWeight: 100     # Final promotion
```

### Add More Analysis Metrics
Create additional metrics in analysis templates for latency, throughput, etc.

## Architecture

```
                    New Version (20% traffic)
                            ↓
                    Prometheus queries
                    ├─ 4xx error rate
                    ├─ 5xx error rate
                    └─ Canary vs Stable
                            ↓
                    Metrics passing?
                    ├─ YES: Increase to 50%
                    └─ NO: ROLLBACK
```

## Prerequisites

Your cluster must have:
- ✅ Argo Rollouts controller installed
- ✅ Prometheus for metric queries
- ✅ AWS ALB Ingress Controller
- ✅ ServiceMonitor CRD (Prometheus Operator)

Your application must:
- ✅ Export `http_requests_total` metric with status labels
- ✅ Have `/healthz` health check endpoint

## Troubleshooting

### Rollout Stuck
```bash
# Check analysis status
kubectl describe analysisrun -n simple-time-service

# Check if Prometheus is accessible
kubectl run test -it --image=curlimages/curl --rm --restart=Never \
  -n simple-time-service -- \
  curl http://prometheus.monitoring:9090/api/v1/query?query=up
```

### Metrics Not Available
```bash
# Check if ServiceMonitor is scraping
kubectl get servicemonitor -n simple-time-service
kubectl describe servicemonitor simple-time-service -n simple-time-service

# Check Prometheus targets at: http://prometheus.monitoring:9090/targets
```

### All Pods Same Version
```bash
# Check pod labels - Rollout adds version label automatically
kubectl get pods -n simple-time-service -o wide -L version
```

## Expected Timeline

| Time | Event | Traffic |
|------|-------|---------|
| 0m | Deploy canary | 20% |
| 5m | Metrics pass, increase | 50% |
| 10m | Metrics pass, promote | 100% |
| 11m | Rollout complete | ✓ |

If metrics fail at any point → automatic rollback to stable.

## Services

Three services handle traffic routing:

1. **simple-time-service** (main)
   - Routes to all pods (canary + stable)
   - Used by ingress

2. **simple-time-service-stable**
   - Routes to pods labeled `version: stable`
   - Used by ALB for stable traffic

3. **simple-time-service-canary**
   - Routes to pods labeled `version: canary`
   - Used by ALB for canary traffic

## File Structure

```
gitops/helm-charts/apps/simple-time-service/
├── templates/
│   ├── rollout.yaml ..................... Canary deployment strategy
│   ├── analysis-template-4xx.yaml ....... 4xx error analysis
│   ├── analysis-template-5xx.yaml ....... 5xx error analysis
│   ├── service.yaml ..................... Three services
│   ├── ingress.yaml
│   ├── servicemonitor.yaml
│   └── namespace.yaml
├── Chart.yaml ........................... Helm chart metadata
├── values.yaml .......................... Base values
├── values-staging.yaml .................. Staging environment overrides
└── values-prod.yaml ..................... Production environment overrides
```

## Common Scenarios

### Scenario 1: Successful Canary
```bash
# Trigger deployment
kubectl set image rollout/simple-time-service \
  simple-time-service=karthikbm2k25/simple-time-service:1.2.0 \
  -n simple-time-service

# Watch progress
kubectl get rollout -n simple-time-service -w

# Result: Progressing → Progressing → Healthy ✓
# Timeline: ~10 minutes
```

### Scenario 2: Rollback Due to High Errors
```bash
# High 5xx errors detected by Prometheus
# Analysis shows > 10% 5xx rate
# System automatically rolls back
# Pods terminate, stable version restored
# Status: Degraded

# Alert sent to ops team
```

### Scenario 3: Manual Adjustment
```bash
# Edit threshold for stricter SLO
kubectl edit analysistemplate canary-5xx-regression -n simple-time-service

# Change: successCondition: result < 1  (instead of < 2)

# Next deployment uses new threshold
```

## Monitoring

### Key Metrics to Track
- Rollout phase (Progressing/Healthy/Degraded)
- AnalysisRun status (Successful/Failed)
- 4xx error rate trend
- 5xx error rate trend
- Canary vs stable comparison

### Prometheus Queries for Dashboard
```promql
# 4xx error rate
(sum(rate(http_requests_total{status=~"4..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100

# 5xx error rate
(sum(rate(http_requests_total{status=~"5..",namespace="simple-time-service"}[2m])) / sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))) * 100

# Request rate
sum(rate(http_requests_total{namespace="simple-time-service"}[2m]))
```

## Support

For issues:
1. Check rollout status: `kubectl describe rollout simple-time-service -n simple-time-service`
2. Check analysis results: `kubectl describe analysisrun -n simple-time-service`
3. Verify Prometheus is reachable
4. Check pod logs: `kubectl logs -l app=simple-time-service -n simple-time-service`

---

**Created**: 30 Jan 2026  
**Status**: Ready for Deployment ✅
