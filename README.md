# Simple Time Service

## Document Information
**Version:** 1.0  
**Last Updated:** 2025  
**Status:** Production

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Build and Deployment](#build-and-deployment)
5. [Infrastructure Setup](#infrastructure-setup)
6. [Kubernetes Deployment](#kubernetes-deployment)
7. [Configuration](#configuration)
8. [Operations](#operations)

---

## Overview

Simple Time Service is a lightweight Flask-based microservice that provides real-time UTC timestamp and client network information. The service is designed for containerized deployment on Kubernetes with automated CI/CD pipelines.

### Service Capabilities

The application exposes a single REST endpoint that returns:
- **Current UTC timestamp** - ISO 8601 formatted timestamp
- **Client IP address** - Source IP of the requesting client
- **Proxy chain** - Complete proxy chain information (if behind reverse proxies)

### Technology Stack

- **Application Framework:** Flask (Python)
- **Container Runtime:** Docker
- **Orchestration:** Kubernetes (EKS)
- **Infrastructure as Code:** Terraform
- **CI/CD:** GitLab CI/CD
- **Cloud Provider:** Amazon Web Services (AWS)

---

## Architecture

The service is deployed as a containerized application on Amazon EKS with the following components:

- **Application Layer:** Flask service running in Kubernetes pods
- **Network Layer:** Application Load Balancer (ALB) with ingress controller
- **Infrastructure Layer:** VPC with public/private subnets, EKS cluster
      For high availability, we have used 2 subnets, where deployment pods will move to different subnet in case of one of the AZ failure.
- **State Management:** Terraform state stored in S3 with DynamoDB locking

---

## Prerequisites

### Required Tools and Software

- **Terraform** >= 1.0
- **AWS CLI** (configured with appropriate credentials)
- **kubectl** (configured to access EKS cluster)
- **Docker** (for local builds and testing)
- **Git** (for version control)

### AWS Account Requirements

- AWS account with appropriate billing and service quotas
- AWS credentials with permissions to create and manage:
  - VPC and networking resources
  - EKS clusters and node groups
  - IAM roles and policies
  - EC2 instances
  - Application Load Balancers
  - S3 buckets
  - DynamoDB tables

### AWS Resources - Pre-requisite Setup

**IMPORTANT:** Before running Terraform, you must manually create the following AWS resources:

#### 1. S3 Bucket for Terraform State

Create an S3 bucket to store Terraform state files. The bucket name must be unique and follow AWS naming conventions.

```bash
aws s3 mb s3://simple-time-service-tf-state-prod --region us-east-1
```

**Note:** If you need to use a different bucket name, update the `backend` configuration in your Terraform files (`infra/environments/prod/main.tf`) to reflect the new bucket name.

#### 2. DynamoDB Table for State Locking

Create a DynamoDB table to enable Terraform state locking and prevent concurrent modifications.

```bash
aws dynamodb create-table \
  --table-name simple-time-service-tf-lock-prod \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**Note:** If you need to use a different table name, update the `backend` configuration in your Terraform files to reflect the new table name.

### GitLab CI/CD Configuration

Configure the following variables in GitLab CI/CD Settings → Variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `AWS_ACCESS_KEY_ID` | AWS access key for CI/CD operations | Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | Yes |
| `AWS_DEFAULT_REGION` | AWS region for deployments (default: `us-east-1`) | Yes |

---

## Build and Deployment

### Docker Image Build

The Docker image build process is automated through GitLab CI/CD and triggers on merge request creation.

#### Automated Build Process

- **Trigger:** Merge request creation
- **Image Tag:** Automatically uses commit hash as the image tag
- **Multi-platform build:** 
   The Dockerfile builds multi-platform docker images. It uses commit short hash as image tag.
   It builds Docker image for both architectures ARM64 and AMD64 under same tag.
   If docker engine is in mac or ARM64 architecture, it automatically returns ARM64 image.
   If docker engine is in linux or AMD64 architecture, it automatically returns AMD64 image.

- **RELEASE versions:**   
   1. Once a docker image with specific tag is tested in dev, staging etc. We can promote it or tag a 
   release version to the image. 
   2. Tag the git commit once qa is completed and qualified for the release/deployment. 
   3. To tag or set release version of the docker inage, we just need to add git tag to the specific git commit.
   4. Once we add git tag like "1.1.2" to commit and push the tag, gitlab runner will trigger the "Release_Version" stage.
   5. In "Release_Version" stage of cicd, it pulls the fully tested existing docker image of specific commit and adds the 1.1.2 version to the same image(tag).
   6. This helps in avoiding multiple builds for the same code, after testing and merging to main. We can use the same testd image in all different enveironments including production.
   7. For production use same image, but with specific release version.
   
- **For testing locally:**  
      Use Latest Docker Image: karthikbm2k25/simple-time-service:1.1.2
   - **To run it locally:**  
      docker run -p 8080:8080 karthikbm2k25/simple-time-service:1.1.2
      http://localhost:8080/
      http://localhost:8080/healthz
      

## Infrastructure Setup

### Overview

Infrastructure provisioning is managed through Terraform with automated CI/CD integration. The infrastructure includes:

- **VPC:** Virtual Private Cloud with public and private subnets across multiple availability zones
- **EKS Cluster:** Managed Kubernetes cluster with node groups
- **IAM Roles:** Service roles and policies for EKS and node groups
- **Networking:** Security groups, route tables, and internet gateway

### GitLab CI/CD Integration

The infrastructure deployment process is fully automated:

- **Terraform Plan:** Automatically executed on merge request creation
- **Terraform Apply:** Requires manual approval via GitLab CI/CD pipeline interface



#### 1. Review Changes
   On Merge request, Terraform plan is triggered.
   Review it and approve the code changes and terraform plan output.

#### 2. Deploy Infrastructure

Once approved and merged, you can trigger the deployment / terraform apply manually on a single click.
This will create:
- VPC with public/private subnets
- EKS cluster with node groups
- Required IAM roles and policies
- Security groups and networking components

### Terraform State Management

**State Storage:**
- **Location:** S3 bucket `simple-time-service-tf-state-prod`
- **Locking:** DynamoDB table `simple-time-service-tf-lock-prod`

**Important Notes:**
- Ensure the S3 bucket and DynamoDB table exist before running Terraform (see [Prerequisites](#aws-resources---pre-requisite-setup))
- If you need to change bucket or table names, update the backend configuration in `infra/environments/prod/main.tf`
- State files contain sensitive information and should be encrypted at rest

### Configuration

Infrastructure parameters can be customized by editing `infra/environments/prod/terraform.tfvars`:

- AWS region
- VPC CIDR blocks
- Availability zones
- Subnet CIDR ranges
- EKS cluster configuration
- Node group instance types and scaling parameters

---

## Kubernetes Deployment

### Prerequisites

Before deploying the application to Kubernetes, ensure:

1. **EKS Cluster:** Successfully provisioned and accessible
2. **kubectl Configuration:** Configured to connect to the EKS cluster
3. **AWS Load Balancer Controller:** Installed in the cluster
4. **Image Registry:** Docker image is available in the configured registry

### Deploy Application

#### GitOps Deployment (Recommended)

Applications are managed via ArgoCD GitOps. See `gitops/argo-apps/README.md` for details.

```bash
# Apply ArgoCD Application manifest
kubectl apply -f gitops/argo-apps/simple-time-service-prod.yaml

# Or deploy manually via Kustomize
kubectl apply -k gitops/apps/simple-time-service/overlays/prod
```

#### Legacy Manual Deployment

For manual deployment (not recommended, use GitOps instead):

```bash
# Update image tag in gitops/apps/simple-time-service/base/deployment.yaml
kubectl apply -k gitops/apps/simple-time-service/overlays/prod
```

#### Verify Deployment

```bash
# Check pod status
kubectl get pods -l app=simple-time-service

# Check service status
kubectl get svc simple-time-service

# Get ingress URL
kubectl get ingress simple-time-service-ingress
```

### Application Resources

The deployment is configured with the following resource specifications:

| Resource | Request | Limit |
|----------|---------|-------|
| **CPU** | 100m | 500m |
| **Memory** | 128Mi | 256Mi |
| **Replicas** | 2 | - |
| **Port** | 8080 | - |

### Ingress Configuration

The Application Load Balancer Controller automatically provisions an internet-facing ALB with:

- **HTTP:** Port 80 (redirects to HTTPS)
- **HTTPS:** Port 443
- **TLS Policy:** TLS 1.2 and above
- **Automatic Certificate Management:** Via AWS Certificate Manager (ACM)

---

## Configuration

### Environment Variables

The application can be configured using environment variables defined in the Kubernetes deployment manifest.

### Terraform Variables

Infrastructure configuration is managed through Terraform variables. See `infra/environments/prod/variables.tf` for available options.

---

## Operations

### Updating Application Image




#### Manual Process

1. **Build and Push New Image:**
   ```bash
   docker build -t karthikbm2k25/simple-time-service:1.1.1 .
   docker push karthikbm2k25/simple-time-service:1.1.1
   ```

2. **Update Deployment Manifest:**
   - Edit `gitops/apps/simple-time-service/base/deployment.yaml`
   - Update the `image` field with the new tag
   - Commit and push to Git (ArgoCD will auto-sync)

3. **Apply Changes (GitOps - Automatic):**
   ```bash
   # ArgoCD automatically syncs when you push to Git
   git add gitops/apps/simple-time-service/base/deployment.yaml
   git commit -m "Update image to 1.1.1"
   git push
   
   # Or sync manually
   argocd app sync simple-time-service-prod
   kubectl rollout status deployment/simple-time-service -n simple-time-service
   ```

### Monitoring and Troubleshooting

#### Check Pod Logs

```bash
kubectl logs -l app=simple-time-service --tail=100
```

#### Describe Resources

```bash
kubectl describe pod <pod-name>
kubectl describe svc simple-time-service
kubectl describe ingress simple-time-service-ingress
```

#### Rollback Deployment

```bash
kubectl rollout undo deployment/simple-time-service
```

---

## Support and Maintenance

For issues, questions, or contributions, please refer to the project repository or contact the Devops team.

---

**Document End**
