# Recommendation: Where to Run EKS Addons Installation

## Answer: Use GitLab CI (Option 2)

**Recommended approach:** Run the installation script in **GitLab CI** as a manual job.

### Why GitLab CI over Terraform?

1. ✅ **Separation of concerns** - Infrastructure (Terraform) vs Operations (CI/CD)
2. ✅ **More control** - Can run/rerun independently
3. ✅ **Better for teams** - DevOps team manages CI, Platform team manages Terraform
4. ✅ **Easier troubleshooting** - Can debug in CI without affecting Terraform
5. ✅ **Flexible** - Can update addons without touching Terraform state

### Why NOT user_data?

❌ **user_data runs on EC2 nodes** - but the script installs **cluster-level components** (kubectl operations), not node-level stuff.

---

## Implementation

### Step 1: Include GitLab CI file

Add to your `.gitlab-ci.yml`:

```yaml
include:
  - local: '.gitlab-ci-addons.yml'
```

### Step 2: Configure GitLab CI Variables

In GitLab UI: Settings > CI/CD > Variables

Add:
- `AWS_ACCESS_KEY_ID` (masked)
- `AWS_SECRET_ACCESS_KEY` (masked, protected)

Or use AWS IAM roles if GitLab runners are in AWS.

### Step 3: Run After Cluster Creation

**After Terraform creates cluster:**

1. Go to GitLab: CI/CD > Pipelines
2. Click "Run pipeline"
3. Select `install_eks_addons` job
4. Click "Run job"

Or set environment variable and trigger:
```bash
INSTALL_ADDONS=true git push origin main
```

---

## Alternative: Terraform (If You Prefer IaC)

If you want everything automated in Terraform, the `addons.tf` file is ready.

**Use it by:**
1. Set `skip_addons_install = false` in module (default)
2. Ensure kubectl and helm are installed where Terraform runs
3. Run `terraform apply`

**Skip it by:**
1. Set `skip_addons_install = true` in module
2. Install via GitLab CI or manually

---

## Quick Decision

- **Want automation in CI/CD?** → Use GitLab CI (`.gitlab-ci-addons.yml`)
- **Want everything in Terraform?** → Use Terraform (`addons.tf`, set `skip_addons_install = false`)
- **Want manual control?** → Run `./scripts/install-eks-addons.sh` manually

**My recommendation: GitLab CI for better flexibility!**

