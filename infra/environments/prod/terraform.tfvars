aws_region     = "us-east-1"
project_name   = "simple-time-service"
environment    = "prod"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# RDS PostgreSQL Configuration
rds_instance_class         = "db.t3.micro"
rds_allocated_storage      = 20
rds_database_name          = "simple_time_service"
rds_master_username        = "postgres"
# rds_master_password       = "YOUR_SECURE_PASSWORD_HERE"  # Set via TF_VAR_rds_master_password environment variable
rds_multi_az               = false
rds_backup_retention_days  = 7
rds_deletion_protection    = true
rds_skip_final_snapshot    = false