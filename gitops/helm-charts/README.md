# Helm Charts Configuration

This directory contains Helm values files for ArgoCD-managed Helm charts.

## Structure

```
gitops/helm-charts/
├── metrics-server/
│   └── values.yaml
├── aws-load-balancer-controller/
│   └── values.yaml
├── cert-manager/
│   └── values.yaml
├── prometheus-stack/
│   └── values.yaml
├── elasticsearch/
│   └── values.yaml
├── kibana/
│   └── values.yaml
├── fluent-bit/
│   └── values.yaml
├── otel-collector/
│   └── values.yaml
└── cluster-autoscaler/
    └── values.yaml
```

## Benefits

1. **Separation of Concerns:** Values files separate from Application manifests
2. **Easier Maintenance:** Update values without touching Application manifests
3. **Version Control:** Track value changes independently
4. **Reusability:** Share values across environments if needed
5. **Better Organization:** Clear structure for Helm-related configurations

## Usage

ArgoCD Applications reference these values files:

```yaml
spec:
  source:
    helm:
      valueFiles:
        - $values/gitops/helm-charts/prometheus-stack/values.yaml
```

## Migration from Inline Parameters

Current Application manifests use inline `helm.parameters`. To migrate to values files:

1. Extract parameters to `values.yaml` files
2. Update Application manifests to reference `valueFiles`
3. Test sync in ArgoCD

This is optional but recommended for complex configurations.

