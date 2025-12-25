# EKS Addons Installation - Where to Run?

## ❌ NOT: user_data

**Why NOT user_data:**
- `user_data` runs on **EC2 instances** (nodes) when they boot
- The installation script installs **cluster-level components** (not node-level)
- Nodes don't have `kubectl`, `helm` by default
- Components need to be installed **once** for the cluster, not per node
- Script needs to connect to cluster API, not run on nodes

**When to use user_data:**
- Installing node-level packages (monitoring agents, security tools)
- Configuring node-specific settings
- Setting up bootstrap scripts for nodes

---

## ✅ Option 1: Terraform null_resource (RECOMMENDED)

**Best for:** Infrastructure as Code, automated provisioning

### Advantages:
- ✅ Runs automatically after cluster creation
- ✅ Part of Terraform state
- ✅ Version controlled with infrastructure
- ✅ Idempotent (safe to run multiple times)
- ✅ No separate CI job needed

### Implementation:

Already created in `infra/terraform/modules/eks/addons.tf`

**How it works:**
1. Terraform creates cluster and node group
2. After resources are ready, runs installation script
3. Script installs addons automatically
4. All part of `terraform apply`

**Usage:**
```bash
cd infra/environments/prod
terraform init
terraform apply  # Cluster + addons installed automatically
```

**Pros:**
- Fully automated
- Part of infrastructure lifecycle
- No manual steps

**Cons:**
- Requires kubectl, helm on Terraform runner machine
- Longer terraform apply time

---

## ✅ Option 2: GitLab CI (GOOD for CI/CD workflows)

**Best for:** CI/CD pipelines, separate infrastructure and application deployments

### Advantages:
- ✅ Runs in GitLab CI/CD pipeline
- ✅ Can use GitLab CI variables for credentials
- ✅ Can be triggered manually or automatically
- ✅ Runs in containerized environment
- ✅ Good separation of concerns

### Implementation:

Created `.gitlab-ci-addons.yml` - Add to your main `.gitlab-ci.yml` or include:

```yaml
include:
  - local: '.gitlab-ci-addons.yml'
```

**Usage:**
```bash
# In GitLab UI, go to CI/CD > Pipelines
# Click "Run pipeline"
# Select "install_eks_addons" job
# Or set environment variable: INSTALL_ADDONS=true
```

**Setup required:**
1. Add GitLab CI variables:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - Or use AWS IAM roles if using GitLab runners in AWS

2. Include the file in main CI:
   ```yaml
   include:
     - local: '.gitlab-ci-addons.yml'
   ```

**Pros:**
- Runs in GitLab environment
- Can be scheduled or triggered
- Good audit trail
- Can use GitLab secrets management

**Cons:**
- Requires GitLab CI setup
- Needs AWS credentials in GitLab
- Separate from Terraform lifecycle

---

## ✅ Option 3: Manual Execution (SIMPLE)

**Best for:** Initial setup, troubleshooting, one-time installations

### Advantages:
- ✅ Simple, direct control
- ✅ Easy to troubleshoot
- ✅ No dependencies on CI/CD
- ✅ Good for initial setup

### Usage:
```bash
# After cluster is created
cd /path/to/simple-time-service

# Set variables
export CLUSTER_NAME="simple-time-service-prod"
export AWS_REGION="us-east-1"

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Run script
./scripts/install-eks-addons.sh
```

**When to use:**
- Initial cluster setup
- After cluster recreation
- Troubleshooting addon issues
- One-off installations

---

## ✅ Option 4: Terraform + Separate CI Job (HYBRID)

**Best for:** Want Terraform to create infrastructure, but CI to manage addons

### How it works:
1. Terraform creates cluster (no addons)
2. GitLab CI job detects new cluster
3. CI job runs installation script
4. Addons installed via CI

### Advantages:
- ✅ Separation: Infrastructure vs Operations
- ✅ Faster Terraform runs
- ✅ Can update addons without touching Terraform
- ✅ Better for teams where different people manage infra vs apps

---

## Recommendation

### For Your Use Case:

**Recommended: Option 1 (Terraform null_resource)**

**Why:**
- ✅ You're already using Terraform for infrastructure
- ✅ Keeps everything in one place
- ✅ Automated, no manual steps
- ✅ Consistent across environments

**Implementation:**
The file `infra/terraform/modules/eks/addons.tf` is already created. Just ensure:
1. Script path is correct
2. Prerequisites (kubectl, helm) are installed where Terraform runs

### Alternative: Option 2 (GitLab CI)

**Use if:**
- You want separation between infrastructure and operations
- You prefer CI/CD for all operational tasks
- You want to update addons without touching Terraform

**Implementation:**
1. Include `.gitlab-ci-addons.yml` in your main CI
2. Configure GitLab CI variables
3. Run job manually after cluster creation

---

## Comparison Table

| Option | Automation | Complexity | Best For |
|--------|-----------|------------|----------|
| **Terraform** | ✅ Fully automated | Medium | IaC workflows |
| **GitLab CI** | ✅ Fully automated | Medium | CI/CD workflows |
| **Manual** | ❌ Manual | Low | Initial setup |
| **Hybrid** | ✅ Automated | High | Large teams |

---

## Quick Decision Guide

**Choose Terraform if:**
- ✅ You run `terraform apply` to create infrastructure
- ✅ You want everything in one command
- ✅ You use Terraform for all infrastructure

**Choose GitLab CI if:**
- ✅ You want separate pipeline for operations
- ✅ Different teams manage infra vs apps
- ✅ You prefer CI/CD for all automation

**Choose Manual if:**
- ✅ Setting up first time
- ✅ Troubleshooting
- ✅ One-off installations

---

## Final Recommendation

**Start with Terraform (Option 1)** - It's already configured and works well for your setup.

If you need more flexibility later, switch to GitLab CI (Option 2).

