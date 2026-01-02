# Helm Charts Folder - Best Practices

## Current Structure

```
gitops/helm-charts/
├── metrics-server/
│   └── values.yaml          # Helm values only
├── prometheus-stack/
│   └── values.yaml          # Helm values only
└── ...
```

## Is This Best Practice? ✅ YES

**Yes, having a dedicated `helm-charts/` folder for values files is considered best practice** in GitOps workflows. Here's why:

### ✅ Benefits

1. **Separation of Concerns**
   - Application manifests (`argo-apps/*.yaml`) define WHAT to deploy
   - Values files (`helm-charts/*/values.yaml`) define HOW to configure it
   - Clear separation makes code easier to understand

2. **Easier Maintenance**
   - Update configuration without touching Application manifests
   - Values files are easier to read than long parameter lists
   - Better for code reviews (smaller, focused changes)

3. **Version Control**
   - Track value changes independently
   - See configuration history clearly
   - Easier to rollback configuration changes

4. **Reusability**
   - Share values across environments (prod/staging)
   - Use Kustomize overlays if needed
   - Reference values from multiple Applications

5. **Better Organization**
   - All Helm-related configs in one place
   - Easy to find and update
   - Scales well as you add more charts

## What Goes in `helm-charts/`?

### ✅ Recommended Contents

1. **Values Files** (`values.yaml`)
   - Chart-specific configuration
   - Resource limits, replicas, storage settings
   - Feature flags and toggles

2. **Environment-Specific Values** (optional)
   ```
   helm-charts/
   ├── prometheus-stack/
   │   ├── values.yaml          # Base values
   │   ├── values-prod.yaml     # Production overrides
   │   └── values-staging.yaml  # Staging overrides
   ```

3. **Documentation** (optional)
   ```
   helm-charts/
   ├── prometheus-stack/
   │   ├── values.yaml
   │   └── README.md            # Chart-specific docs
   ```

### ❌ What NOT to Put Here

1. **Custom Helm Charts** - Put in separate `charts/` directory
2. **ArgoCD Applications** - Keep in `argo-apps/`
3. **Raw Kubernetes Manifests** - Use `apps/` or component-specific folders
4. **Terraform Configs** - Keep in `infra/`

## Current State vs Best Practice

### Current State (What We Have)

**ArgoCD Applications use inline parameters:**
```yaml
# gitops/argo-apps/prometheus-stack.yaml
spec:
  source:
    helm:
      parameters:          # Inline parameters
        - name: grafana.enabled
          value: "true"
```

**Values files exist but aren't used:**
```yaml
# gitops/helm-charts/prometheus-stack/values.yaml
grafana:
  enabled: true
```

### Best Practice (Recommended)

**ArgoCD Applications reference values files:**
```yaml
# gitops/argo-apps/prometheus-stack.yaml
spec:
  source:
    helm:
      valueFiles:           # Reference values file
        - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

## When to Use Each Approach

### Use Inline Parameters When:
- ✅ Simple configurations (1-3 parameters)
- ✅ Values rarely change
- ✅ Quick prototyping
- ✅ Single environment

**Example:**
```yaml
helm:
  parameters:
    - name: args
      value: "{--kubelet-insecure-tls}"
```

### Use Values Files When:
- ✅ Complex configurations (many parameters)
- ✅ Values change frequently
- ✅ Multiple environments
- ✅ Team collaboration
- ✅ Need better organization

**Example:**
```yaml
helm:
  valueFiles:
    - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

## Recommended Structure

### Option 1: Current Approach (Mixed) ✅ Good
- Simple charts: Inline parameters
- Complex charts: Values files
- **Pros:** Flexible, pragmatic
- **Cons:** Inconsistent

### Option 2: All Values Files ✅ Best Practice
- All charts use values files
- Consistent structure
- **Pros:** Uniform, scalable, maintainable
- **Cons:** More files to manage

### Option 3: Environment-Based ✅ Advanced
```
helm-charts/
├── prometheus-stack/
│   ├── base/
│   │   └── values.yaml
│   ├── overlays/
│   │   ├── prod/
│   │   │   └── values.yaml
│   │   └── staging/
│   │       └── values.yaml
```
- **Pros:** Environment-specific configs
- **Cons:** More complex, requires Kustomize

## Migration Path

### Step 1: Keep Current Setup ✅
- Inline parameters work fine
- No immediate need to change

### Step 2: Migrate Complex Charts (Recommended)
- Start with prometheus-stack, elasticsearch
- Migrate gradually
- Test each migration

### Step 3: Migrate All (Optional)
- Move all to values files
- Consistent structure
- Better long-term maintainability

## Industry Best Practices

### ArgoCD Official Recommendation
- ✅ Use values files for complex configurations
- ✅ Keep Application manifests simple
- ✅ Reference values from Git repository

### CNCF GitOps Patterns
- ✅ Separate configuration from deployment
- ✅ Version control all configurations
- ✅ Use declarative configuration

### Helm Best Practices
- ✅ Use values files for customization
- ✅ Keep default values minimal
- ✅ Document custom values

## Summary

| Aspect | Best Practice | Current State |
|--------|--------------|---------------|
| **Folder Structure** | ✅ `helm-charts/` for values | ✅ Implemented |
| **Values Files** | ✅ Recommended for complex configs | ✅ Created but not used |
| **Inline Parameters** | ✅ OK for simple configs | ✅ Currently using |
| **Migration** | ⚠️ Optional but recommended | ⚠️ Can migrate gradually |

## Recommendation

**Your current structure is good!** The `helm-charts/` folder is best practice. You have two options:

1. **Keep current approach** - Inline parameters work fine
2. **Migrate to values files** - Better for long-term maintenance

Both are valid. Choose based on:
- Team preference
- Configuration complexity
- Maintenance needs

The values files are ready whenever you want to use them!

