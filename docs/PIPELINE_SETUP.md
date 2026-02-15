# Pipeline Setup Guide

Complete setup instructions for CI/CD pipelines and required secrets.

## Required GitHub Secrets

All secrets must be configured in: **Repository Settings → Secrets and variables → Actions**

### 1. AWS Credentials (For Infrastructure)
- `AWS_ACCESS_KEY_ID` - Your AWS access key
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret (mark as **Masked** and **Protected**)

### 2. Docker Hub Credentials (For Image Registry)
- `DOCKERHUB_USERNAME` - Your Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub personal access token (mark as **Masked** and **Protected**)

### 3. SonarQube Configuration

#### Option A: SonarQube Cloud (Free & Recommended)

1. **Create Account**
   - Go to [sonarcloud.io](https://sonarcloud.io)
   - Click "Sign up" → Choose "GitHub"
   - Authorize access to your GitHub account

2. **Create Organization**
   - Click "Create organization"
   - Choose your GitHub organization/username
   - Select your repository

3. **Get Tokens**
   - Go to https://sonarcloud.io/account/security
   - Click "Generate Tokens"
   - Create a new token (e.g., "github-actions")
   - Copy the token

4. **Configure GitHub Secrets**
   ```
   SONAR_TOKEN: <paste-the-token-from-step-3>
   SONAR_HOST_URL: https://sonarcloud.io
   ```

5. **Verify Project Key**
   - The project key should auto-generate as: `{org}_{repo-name}`
   - Or customize in SonarQube UI
   - Update in CI workflow if different from `simple-time-service`

#### Option B: Self-Hosted SonarQube Server

1. **Install SonarQube**
   ```bash
   # Docker
   docker run -d -p 9000:9000 sonarqube:latest
   # Access at http://localhost:9000
   # Default: admin/admin
   ```

2. **Create Project & Token**
   - Login to http://your-sonarqube-server:9000
   - Create new project manually
   - Go to Account → Security Tokens
   - Generate token for GitHub Actions

3. **Configure GitHub Secrets**
   ```
   SONAR_TOKEN: <your-token>
   SONAR_HOST_URL: http://your-sonarqube-server:9000
   ```

### 4. NVD API Key (For OWASP Dependency-Check)

#### Get Free NVD API Key

1. **Register with NVD**
   - Go to [nvd.nist.gov/developers/request-an-api-key](https://nvd.nist.gov/developers/request-an-api-key)
   - Fill in your information
   - Confirm email

2. **Get API Key**
   - Check your email for NVD API key
   - Copy the key

3. **Configure GitHub Secret**
   ```
   NVD_API_KEY: <your-nvd-api-key>
   ```

#### Why NVD API Key?
- **Without key**: ~50 requests per 30 seconds (slow)
- **With key**: ~100 requests per 30 seconds (faster)
- Recommended for CI/CD pipelines to avoid rate limiting

---

## Quick Setup Checklist

- [ ] SonarQube account created (SonarCloud or self-hosted)
- [ ] SonarQube tokens generated
- [ ] `SONAR_TOKEN` added to GitHub secrets
- [ ] `SONAR_HOST_URL` added to GitHub secrets
- [ ] NVD API key requested
- [ ] `NVD_API_KEY` added to GitHub secrets
- [ ] Docker Hub credentials configured
- [ ] AWS credentials configured
- [ ] Branch protection rule set up (requires passing CI jobs)

---

## Pipeline Status Summary

### ✅ Complete
- **CI Workflow** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))
  - ✅ Build stage (Python compile check)
  - ✅ Docker build & push (multi-arch: amd64, arm64)
  - ✅ Semgrep SAST scan (Python/Flask/Docker/OWASP rules)
  - ✅ Trivy scans (filesystem + Docker image CVEs)

### ⏳ Pending Secrets
- **SonarQube Job**
  - Requires: `SONAR_TOKEN`, `SONAR_HOST_URL`
  - Status: Code ready, waiting for secret setup
  - Purpose: Code quality, security issues, enforced quality gate (5-min timeout)

- **OWASP Dependency-Check Job**
  - Requires: `NVD_API_KEY`
  - Status: Code ready, waiting for secret setup
  - Purpose: Scan Python dependencies for known CVEs, fail on CVSS ≥ 9
  - Note: Works without key, but much slower (rate limited)

### ✅ Ready to Use
- **Terraform Workflow** ([`.github/workflows/terraform.yml`](.github/workflows/terraform.yml))
  - Requires: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
  - Plan & apply infrastructure

- **ArgoCD Bootstrap Workflow** ([`.github/workflows/addons.yml`](.github/workflows/addons.yml))
  - Requires: AWS credentials
  - Manual trigger for cluster setup

---

## Testing Pipeline

Once secrets are configured:

1. **Test Build**
   ```bash
   git push origin feature-branch
   ```
   - Watch Actions tab for build status
   - All parallel jobs should start after build completes

2. **Valid Trigger Paths**
   - Changes to `app/**`, `Dockerfile`, `requirements.txt`, or `.github/workflows/`
   - Push to `main`, `develop`, or tag `v*.*.*`

3. **Expected Results**
   - ✅ Build: ~30s
   - ✅ Docker: ~3-5 min (multi-arch build)
   - ✅ Semgrep: ~1-2 min
   - ✅ Trivy: ~2-3 min
   - ✅ SonarQube: ~2-3 min (+ quality gate wait)
   - ✅ OWASP: ~3-5 min (depends on NVD API key)

---

## Troubleshooting

### SonarQube Quality Gate Fails
- **Issue**: Quality gate takes >5 minutes
- **Solution**: Increase timeout in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) line 169

### OWASP Dependency-Check Timeout
- **Issue**: Scan times out or rate limited
- **Solution**: 
  - Ensure `NVD_API_KEY` is correctly added
  - Check GitHub secret isn't masked incorrectly

### Trivy Image Scan Fails
- **Issue**: "Image not found"
- **Solution**: Ensure docker job completed successfully and image pushed to Docker Hub

### All Jobs Waiting
- **Issue**: Artifacts visible but jobs don't start
- **Solution**: Check GitHub Actions permissions in Settings → Actions → General

---

## Next Steps

1. **Set up secrets** using the instructions above
2. **Enable branch protection** (require passing CI before merging)
3. **Test with a PR** to verify all jobs pass
4. **Monitor artifacts** in Actions tab for scan results
5. **Review scan reports** for security issues

---

See [PIPELINES.md](../../PIPELINES.md) for detailed pipeline architecture and [SECURITY.md](../../SECURITY.md) for security scanning details.
