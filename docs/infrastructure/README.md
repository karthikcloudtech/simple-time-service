# Infrastructure & Deployment Guides

Production-ready infrastructure setup, operations, and troubleshooting for Simple Time Service on AWS EKS.

## 🚀 Getting Started (Start Here)

**[→ SETUP.md](SETUP.md)** - Complete EKS cluster setup with Terraform, ArgoCD, and all required tools

## 📋 Core Documentation

| Document | Purpose |
|----------|---------|
| **[SETUP.md](SETUP.md)** | Step-by-step EKS deployment with prerequisites and verification |
| **[MONITORING_ACCESS.md](MONITORING_ACCESS.md)** | Access monitoring dashboards (Prometheus, Grafana, Kibana) |
| **[SECRETS_MANAGEMENT.md](SECRETS_MANAGEMENT.md)** | Store and manage secrets via GitLab CI/CD |
| **[DNS_SETUP.md](DNS_SETUP.md)** | Configure DNS and automatic SSL certificates |

## 🔧 Reference & Troubleshooting

| Document | Purpose |
|----------|---------|
| **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** | Complete folder structure and component overview |
| **[IAM_ROLE_ANNOTATION_FIX.md](IAM_ROLE_ANNOTATION_FIX.md)** | Fix ServiceAccount IAM credential errors |
| **[TROUBLESHOOTING_AWS_LB_CONTROLLER.md](TROUBLESHOOTING_AWS_LB_CONTROLLER.md)** | Debug LoadBalancer controller issues |

## 📖 Related Documentation

- **Application**: [README.md](../../README.md) - Features and local development
- **Architecture**: [ARCHITECTURE.md](../../ARCHITECTURE.md) - System design and data flow
- **Quick Start**: [QUICK_START.md](../../QUICK_START.md) - Run locally in minutes
