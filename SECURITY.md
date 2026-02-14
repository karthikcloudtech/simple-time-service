# Security

## CI/CD Security Pipeline

All code changes trigger automated security scans via GitHub Actions (`.github/workflows/ci.yml`).

### Scan Stages

| Tool | Type | Trigger | Severity Threshold |
|------|------|---------|-------------------|
| **Semgrep** | SAST (static analysis) | After `build` | Advisory (non-blocking) |
| **Trivy** | Container & dependency CVE scan | After `docker` | CRITICAL, HIGH, MEDIUM |
| **SonarQube** | Code quality & security | After `build` | Quality Gate enforced |
| **OWASP Dependency-Check** | Known CVE scan on dependencies | After `build` | Fails on CVSS ≥ 9 |

### Semgrep

Runs inside the `semgrep/semgrep` container with these rulesets:

- `p/default` – general best practices
- `p/python` – Python-specific issues
- `p/flask` – Flask framework vulnerabilities
- `p/docker` – Dockerfile misconfigurations
- `p/owasp-top-ten` – OWASP Top 10
- `p/security-audit` – broad security audit

Results are uploaded as the `semgrep-results` artifact (JSON, 30-day retention).

### Trivy

Two scans run sequentially:

1. **Filesystem scan** – scans source tree and `requirements.txt` for CRITICAL/HIGH CVEs.
2. **Image scan** – pulls the built Docker image and scans for CRITICAL/HIGH/MEDIUM CVEs.

Results are uploaded as the `trivy-results` artifact (JSON, 30-day retention).

### SonarQube

Performs code quality and security analysis on `app/` with Python 3.11. Enforces the configured quality gate — the pipeline waits up to 5 minutes for the gate result.

**Required secrets:** `SONAR_TOKEN`, `SONAR_HOST_URL`

### OWASP Dependency-Check

Scans `requirements.txt` for known vulnerabilities using the NVD database. Fails the build if any dependency has a CVSS score ≥ 9.

Report is uploaded as the `owasp-dependency-check-report` artifact (HTML, 30-day retention).

**Required secret:** `NVD_API_KEY`

---

## Container Hardening

The production Docker image follows these practices:

- **Multi-stage build** – build tools are not included in the final image
- **Non-root user** – runs as `appuser`, not root
- **Minimal base** – Amazon Linux 2023 with only required packages
- **No cache** – `--no-cache-dir` on pip install
- **Explicit port** – only port 8080 exposed

## Secrets Management

| Secret | Purpose | Where |
|--------|---------|-------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Terraform & EKS access | GitHub Actions secrets |
| `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` | Docker Hub push/pull | GitHub Actions secrets |
| `SONAR_TOKEN` / `SONAR_HOST_URL` | SonarQube analysis | GitHub Actions secrets |
| `NVD_API_KEY` | OWASP Dependency-Check NVD lookups | GitHub Actions secrets |

All secrets must be marked **masked** and **protected** (available only on protected branches).

See `docs/infrastructure/SECRETS_MANAGEMENT.md` for runtime secret handling in Kubernetes.

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public issue. Instead, email the maintainers directly or use GitHub's private vulnerability reporting feature.
