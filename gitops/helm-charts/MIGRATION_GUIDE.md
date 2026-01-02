# Migration Guide: Inline Parameters to Values Files

## Current State

ArgoCD Applications currently use inline `helm.parameters`:

```yaml
spec:
  source:
    helm:
      parameters:
        - name: prometheus.prometheusSpec.retention
          value: "30d"
        - name: grafana.enabled
          value: "true"
```

## Recommended Approach

Use separate `values.yaml` files for better organization:

```yaml
spec:
  source:
    helm:
      valueFiles:
        - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

## Benefits

1. **Cleaner Application Manifests:** Less clutter, easier to read
2. **Easier Updates:** Modify values without touching Application manifests
3. **Better Organization:** All Helm values in one place
4. **Reusability:** Share values across environments
5. **Version Control:** Track value changes independently

## Migration Steps

### Option 1: Keep Current Approach (Valid)

The current inline `parameters` approach works fine for simple configurations. No migration needed if:
- Configurations are simple
- You prefer everything in one file
- Values don't change frequently

### Option 2: Migrate to Values Files (Recommended for Complex Configs)

1. **Values files are already created** in `gitops/helm-charts/`

2. **Update Application manifest** to use `valueFiles`:

```yaml
# Before (inline parameters)
spec:
  source:
    helm:
      parameters:
        - name: prometheus.prometheusSpec.retention
          value: "30d"

# After (values file)
spec:
  source:
    helm:
      valueFiles:
        - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

3. **Test sync:**
```bash
argocd app sync prometheus-stack
argocd app get prometheus-stack
```

## When to Use Each Approach

### Use Inline Parameters When:
- ✅ Simple configurations (few parameters)
- ✅ Values rarely change
- ✅ Prefer single-file approach
- ✅ Quick prototyping

### Use Values Files When:
- ✅ Complex configurations (many parameters)
- ✅ Values change frequently
- ✅ Need environment-specific values
- ✅ Want better organization
- ✅ Team prefers separation of concerns

## Current Recommendation

**Both approaches are valid!** 

- **Current setup (inline parameters):** Works well, keep it if you prefer
- **Values files:** Available if you want to migrate later

You can mix both approaches:
- Use inline parameters for simple charts
- Use values files for complex charts (like prometheus-stack)

## Example: Mixed Approach

```yaml
# Simple chart - inline parameters
spec:
  source:
    helm:
      parameters:
        - name: args
          value: "{--kubelet-insecure-tls}"

# Complex chart - values file
spec:
  source:
    helm:
      valueFiles:
        - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

## Next Steps

1. **Keep current setup** - It works fine!
2. **Or migrate gradually** - Start with complex charts (prometheus-stack, elasticsearch)
3. **Or migrate all** - Update all Application manifests to use values files

The values files are ready whenever you want to use them!

