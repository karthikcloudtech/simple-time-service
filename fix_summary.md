# Fix Summary — 10 February 2026

## 1. GitHub Actions Terraform Workflow

**File:** `.github/workflows/terraform.yml`

| Misconfig | Fix |
|-----------|-----|
| `apply` job had `if: github.event_name == 'pull_request'` but `workflow_dispatch` was also a trigger — apply would never run on manual dispatch | Removed `workflow_dispatch` trigger entirely; both `plan` and `apply` now run only on PRs to main/develop |
| `paths` filter (`infra/**`) prevented workflow from triggering when infra files weren't changed | Removed `paths` filter so workflow triggers on all PRs |

---

## 2. EKS Cluster Security Group — kubectl Timeout

**File:** `infra/terraform/modules/eks/main.tf`, `infra/environments/prod/`

| Misconfig | Fix |
|-----------|-----|
| EKS cluster security group only allowed port 443 from VPC CIDR (`10.0.0.0/16`). Local machine outside VPC could not reach the API server → `kubectl` timed out with `dial tcp 52.7.184.253:443: i/o timeout` | Added `allowed_external_cidrs` variable with an extra ingress rule on port 443 for external access |

---

## 3. ArgoCD Server — Target Unhealthy (Draining)

**Files:** `gitops/helm-charts/platform/argocd/values.yaml`, `gitops/helm-charts/platform/argocd-ingress/values.yaml`

| Misconfig | Fix |
|-----------|-----|
| ArgoCD server runs TLS by default on port 8080, returning a **302 redirect** to HTTPS. ALB health check on `/healthz` over HTTP expected **200** → target went Unhealthy/Draining | Added `--insecure` flag via `extraArgs` in ArgoCD Helm values. Server now serves plain HTTP on 8080; TLS is terminated at the ALB |
| Hardcoded `secretKey: argocd-secret-key-do-not-use-in-prod-generate-random` in values — insecure, anyone can forge JWT tokens | Removed hardcoded `secretKey`; ArgoCD auto-generates a secure random key in the `argocd-secret` Secret |
| Dex server crash-looping (`BackOff restarting failed container dex-server`) because no SSO connectors were configured | Disabled Dex (`dex.enabled: false`) since SSO is not in use |

---

## 4. All Ingresses — Missing `backend-protocol` & Inconsistent Annotations

**Files:** All ingress `values.yaml` files across apps, platform, and observability charts

| Misconfig | Fix |
|-----------|-----|
| `backend-protocol: HTTP` annotation missing on simple-time-service, monitoring-ingress, logging-ingress, prometheus-stack | Added `alb.ingress.kubernetes.io/backend-protocol: HTTP` to all ingress configs |
| `ssl-policy` annotation missing on simple-time-service ingress | Added `alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06` |
| `listen-ports` had invalid format `[{"HTTP":80,"HTTPS":443}]` (single object) in simple-time-service | Fixed to `[{"HTTP":80},{"HTTPS":443}]` (separate objects) |
| `success-codes: '200-399'` masked real health issues by accepting redirects (302) as healthy | Changed to `success-codes: '200'` across all ingresses |

---

## 5. Per-Service Health Check Paths

**Files:** monitoring-ingress, logging-ingress templates and values

| Misconfig | Fix |
|-----------|-----|
| All services under monitoring-ingress shared one health check path (`/api/health`) — wrong for Prometheus | Prometheus ingress now uses `/-/healthy`, Grafana uses `/api/health` (per-service `healthcheckPath` in values, override in templates) |
| All services under logging-ingress used generic `/` as health check | Elasticsearch now uses `/_cluster/health`, Kibana uses `/api/status` |

---

## 6. Monitoring Service Ports

**File:** `gitops/helm-charts/observability/monitoring-ingress/values.yaml`

| Misconfig | Fix |
|-----------|-----|
| Grafana `servicePort` was `80` but Grafana container listens on `3000` | Changed to `servicePort: 3000` |

---

## 7. Argo Rollouts — simple-time-service Pods Not Creating (0 Targets)

**Files:** `gitops/helm-charts/apps/simple-time-service/templates/rollout.yaml`, `values.yaml`

### Error 1: Invalid canary steps

| Misconfig | Fix |
|-----------|-----|
| Canary steps combined `setWeight` and `pause` in a single step object. Argo Rollouts requires each step to have **exactly one** action → `InvalidSpec: Step must have one of the following set: experiment, setWeight, setCanaryScale or pause` | Split into separate steps: `- setWeight: 20` then `- pause: 5m` etc. Fixed both the template logic and values structure |

### Error 2: Service selector mismatch

| Misconfig | Fix |
|-----------|-----|
| Stable/canary Services had `version: stable` / `version: canary` in their selectors, but the Rollout pod template had no `version` label → `Service "simple-time-service-stable" has unmatch label "version" in rollout` | Removed `version` selectors from stable and canary Services. Argo Rollouts manages traffic routing internally |

### Error 3: Ingress backend service

| Misconfig | Fix |
|-----------|-----|
| Ingress pointed to `simple-time-service` (main service) but Argo Rollouts ALB traffic routing requires the ingress to use the **stable** service → `ingress has no rules using service simple-time-service-stable backend` | Changed ingress backend from `simple-time-service` to `simple-time-service-stable` |
