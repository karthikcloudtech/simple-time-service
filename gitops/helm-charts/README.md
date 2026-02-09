# Helm Charts Configuration

Minimal structure for Helm charts used by ArgoCD.

```
gitops/helm-charts/
├── apps/
│   └── simple-time-service/
├── observability/
│   ├── monitoring-ingress/
│   ├── logging-ingress/
│   ├── prometheus-stack/
│   ├── elasticsearch/
│   ├── kibana/
│   ├── fluent-bit/
│   ├── otel-collector/
│   └── otel-collector-config/
└── platform/
    ├── argocd-ingress/
    ├── aws-load-balancer-controller/
    ├── cert-manager/
    ├── cluster-autoscaler/
    ├── cluster-issuers/
    ├── metrics-server/
    ├── serviceaccounts/
    └── storage-class/
```
