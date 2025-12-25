# Simple Time Service - Overall Picture

**Flask microservice** providing UTC timestamp and client IP info.

Deployed on **AWS EKS** with **Terraform** infrastructure.

Uses **GitOps** (Argo CD) and **CI/CD** (GitLab).

Includes monitoring (Prometheus/OpenTelemetry), multi-platform Docker builds,
and automated deployments across staging/prod environments.

