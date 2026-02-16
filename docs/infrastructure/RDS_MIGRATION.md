# PostgreSQL Migration: ArgoCD to AWS RDS

## Overview

The PostgreSQL database has been migrated from an in-cluster deployment (managed by ArgoCD) to AWS RDS (Relational Database Service) for better reliability, scalability, and managed operations.

## Changes Made

### Terraform Infrastructure

**New RDS Module**: `/infra/terraform/modules/rds/`
- `main.tf` - RDS instance, security group, and DB subnet group
- `variables.tf` - All configurable parameters
- `outputs.tf` - Database connection details

**Updated Production Configuration**: `/infra/environments/prod/`
- `main.tf` - Added RDS module instantiation
- `variables.tf` - Added RDS-related variables
- `outputs.tf` - Added RDS outputs for connection details
- `terraform.tfvars` - Added RDS configuration values

### Disabled ArgoCD Application

**File**: `gitops/argo-apps/platform/postgresql.yaml`
- Commented out the ArgoCD Application resource
- PostgreSQL is now managed by Terraform, not ArgoCD
- The Helm chart in `gitops/helm-charts/platform/postgresql/` is no longer deployed

## RDS Configuration Details

### Default Settings

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Engine | PostgreSQL 15.5 | Latest stable version |
| Instance Class | db.t3.micro | Cost-effective for dev/test |
| Storage | 20 GB | Scalable up as needed |
| Multi-AZ | Disabled | Single-AZ deployment (cost-optimized) |
| Backup Retention | 7 days | Automated backups |
| Encryption | Enabled | Data at rest encryption |
| Deletion Protection | Enabled | Prevents accidental deletion |

### Security

- **Security Group**: Automatically created and restricts access
  - Ingress: Port 5432 from EKS cluster only
  - Egress: All outbound traffic allowed

- **Network Placement**: 
  - Database deployed in private subnets
  - Not publicly accessible
  - Only accessible from within VPC and EKS cluster

- **Credentials**:
  - Master username: `postgres` (configurable)
  - Master password: Set via `rds_master_password` variable
  - Sensitive values are marked in Terraform outputs

## Deployment Instructions

### 1. Set RDS Master Password

```bash
# Using environment variable (recommended for CI/CD)
export TF_VAR_rds_master_password="YourSecurePassword123!"

# Or add to terraform.tfvars (not recommended for production)
# rds_master_password = "YourSecurePassword123!"
```

### 2. Initialize and Plan

```bash
cd infra/environments/prod
terraform init
terraform plan
```

### 3. Apply Configuration

```bash
terraform apply
```

### 4. Retrieve Connection Details

After deployment, get RDS connection details:

```bash
# Get all RDS outputs
terraform output | grep rds_

# Get specific endpoint
terraform output rds_db_host
terraform output rds_db_endpoint
```

## Application Configuration

Your application needs to connect to RDS instead of the in-cluster PostgreSQL. Update environment variables:

```yaml
# Old (in-cluster)
DATABASE_HOST: postgresql.postgres.svc.cluster.local
DATABASE_PORT: 5432

# New (RDS)
DATABASE_HOST: <rds_host_from_terraform_output>
DATABASE_PORT: 5432
DATABASE_NAME: simple_time_service
DATABASE_USER: postgres
DATABASE_PASSWORD: <your_rds_master_password>
```

### Using Terraform Outputs for Configuration

```bash
# Export as environment variables for application configuration
export DB_HOST=$(terraform output -raw rds_db_host)
export DB_PORT=$(terraform output -raw rds_db_port)
export DB_NAME=$(terraform output -raw rds_db_name)
export DB_USER=$(terraform output -raw rds_master_username)
```

## Customization

To customize RDS deployment, modify variables in `terraform.tfvars`:

```terraform
# Change instance class for production workloads
rds_instance_class = "db.t3.small"  # or db.t4g.medium, db.r6g.large, etc.

# Increase storage
rds_allocated_storage = 100

# Extend backup retention
rds_backup_retention_days = 30

# Use multi-AZ for high availability
rds_multi_az = true
```

## Monitoring

### CloudWatch Metrics

RDS automatically publishes metrics to CloudWatch:
- CPU utilization
- Database connections
- Read/write latency
- Storage usage
- Network throughput

Access via AWS Console: RDS Dashboard → DB Instances → [simple-time-service-postgres]

### Database Backups

- **Automated backups**: Retained for 7 days (configurable)
- **Manual snapshots**: Available in AWS Console
- **Restore from backup**: Can restore to new instance or point-in-time recovery

## Terraform State

RDS resources are stored in the Terraform state:
- **Bucket**: `simple-time-service-tf-state-prod`
- **Key**: `prod/terraform.tfstate`
- **Encryption**: Enabled
- **Locking**: DynamoDB-based locking enabled

**⚠️ Important**: Never commit `terraform.tfstate` or `terraform.tfvars` (with passwords) to Git.

## Cleanup

To remove RDS instance:

```bash
# Display resources to be destroyed
terraform destroy -auto-approve=false

# Actually destroy (requires confirmation)
terraform destroy
```

**Note**: Final snapshot will remain unless `rds_skip_final_snapshot = true` is set.

## Troubleshooting

### Connection Refused

Check security group:
```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=simple-time-service-rds-sg"
```

### Database Not Found

Verify database name in RDS console:
```bash
aws rds describe-db-instances \
  --db-instance-identifier simple-time-service-postgres
```

### Password Issues

Reset master password:
```bash
aws rds modify-db-instance \
  --db-instance-identifier simple-time-service-postgres \
  --master-user-password NewPassword123 \
  --apply-immediately
```

## Migration Checklist

- [ ] Back up existing in-cluster PostgreSQL data
- [ ] Export data from old database
- [ ] Deploy RDS via Terraform
- [ ] Import data into RDS
- [ ] Test application connectivity
- [ ] Update application environment variables
- [ ] Redeploy applications
- [ ] Monitor for issues
- [ ] Decommission in-cluster PostgreSQL

## References

- [AWS RDS PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Terraform RDS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
