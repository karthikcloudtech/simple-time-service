# CI/CD Pipelines Overview

All GitHub Actions workflows for this project. View live runs in the **[Actions](../../actions)** tab.

---

## 1. CI Pipeline

**File:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

**Trigger:** 
- Pull requests to `main` or `develop`
- Pushes to `main` or `develop` (with version tags `v*.*.*`)
- Manual (`workflow_dispatch`)

**Paths monitored:**
- `app/**`
- `Dockerfile`
- `requirements.txt`
- `gitops/**`
- `.github/workflows/ci.yml`

### Jobs

```
Stage 1:
  build (ubuntu-latest)
    ↓
Stage 2 (parallel):
  ├→ docker (ubuntu-latest)
  │    ↓
  │  Stage 3:
  │    └→ trivy (ubuntu-latest)
  │
  ├→ semgrep (ubuntu-latest, semgrep/semgrep container)
  │
  ├→ sonarqube (ubuntu-latest)
  │
  └→ owasp-dependency-check (ubuntu-latest)
```

| Job | Purpose | Artifacts | Secrets |
|-----|---------|-----------|---------|
| **build** | Install Python deps, compile bytecode | — | — |
| **docker** | Build & push multi-arch images to Docker Hub (or tag existing SHA) | — | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |
| **semgrep** | SAST with Python/Flask/Docker/OWASP rules | `semgrep-results.json` | — |
| **sonarqube** | Code quality & security with quality gate | — | `SONAR_TOKEN`, `SONAR_HOST_URL` |
| **owasp-dependency-check** | Scan `requirements.txt` for known CVEs; fails on CVSS ≥ 9 | `owasp-dependency-check-report/` (HTML) | `NVD_API_KEY` |
| **trivy** (after docker) | CVE scan: filesystem + Docker image | `trivy-image-results.json` | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |

---

## 2. Terraform Pipeline

**File:** [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml)

**Trigger:** Pull requests to `main` or `develop`

**Root:** `infra/environments/prod/`

### Jobs

```
plan (ubuntu-latest)
  ↓
apply (ubuntu-latest, prod environment)
```

| Job | Purpose | Steps |
|-----|---------|-------|
| **plan** | Validate TF config and preview changes | `terraform init` → `terraform validate` → `terraform plan` |
| **apply** | Apply changes (requires `prod` environment approval) | `terraform init` → `terraform apply -auto-approve` |

**Secrets:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

---

## 3. Bootstrap ArgoCD Pipeline

**File:** [`.github/workflows/addons.yml`](.github/workflows/addons.yml)

**Trigger:** Manual (`workflow_dispatch`)

**Inputs:**
- `cluster_name` (default: `simple-time-service-prod`)
- `aws_region` (default: `us-east-1`)

### Steps

1. **bootstrap** job:
   - Configures AWS credentials
   - Installs kubectl & helm
   - Updates kubeconfig
   - Runs `scripts/install-eks-addons.sh` to bootstrap ArgoCD and platform components

2. **verify** job:
   - Validates the bootstrap (checks service availability, etc.)

**Secrets:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

---

## GitHub Actions Dashboard

**View all runs:** [`Actions` tab](../../actions)

### Quick Links
- [CI run details](../../actions/workflows/ci.yml)
- [Terraform run details](../../actions/workflows/terraform.yml)
- [ArgoCD Bootstrap run details](../../actions/workflows/addons.yml)

### Tips

1. **Filter runs by workflow** – Click the workflow name in the sidebar
2. **Rerun failed jobs** – Click "Re-run jobs" on the run detail page
3. **Download artifacts** – Expand "Artifacts" to access scan results
4. **Enable branch protection** – Require successful status checks before merging:
   - `build`
   - `docker` (or skip for PRs)
   - `semgrep`
   - `trivy`
   - `sonarqube`
   - `owasp-dependency-check`
   - `plan` (Terraform)

---

## Required Secrets

| Secret | Purpose | Workflows |
|--------|---------|-----------|
| `AWS_ACCESS_KEY_ID` | AWS authentication | CI, Terraform, ArgoCD Bootstrap |
| `AWS_SECRET_ACCESS_KEY` | AWS authentication | CI, Terraform, ArgoCD Bootstrap |
| `DOCKERHUB_USERNAME` | Docker Hub credentials | CI (docker, trivy jobs) |
| `DOCKERHUB_TOKEN` | Docker Hub authentication | CI (docker, trivy jobs) |
| `SONAR_TOKEN` | SonarQube authentication | CI (sonarqube job) |
| `SONAR_HOST_URL` | SonarQube server URL | CI (sonarqube job) |
| `NVD_API_KEY` | NVD database API key | CI (owasp-dependency-check job) |

**Configure at:** Repository Settings → Secrets and variables → Actions

---

## Pipeline Status Badge

Add to README.md:

```markdown
[![CI](https://github.com/YOUR_ORG/simple-time-service/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_ORG/simple-time-service/actions/workflows/ci.yml)
[![Terraform](https://github.com/YOUR_ORG/simple-time-service/actions/workflows/terraform.yml/badge.svg)](https://github.com/YOUR_ORG/simple-time-service/actions/workflows/terraform.yml)
```

Replace `YOUR_ORG` with your GitHub organization/username.

---

See [SECURITY.md](SECURITY.md) for detailed security scanning info.
