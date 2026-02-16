output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "environment" {
  description = "Environment"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_name" {
  description = "VPC Name"
  value       = module.vpc.vpc_name
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager"
  value       = module.eks.cert_manager_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.eks.aws_load_balancer_controller_role_arn
}
# RDS Outputs
output "rds_db_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.db_instance_id
}

output "rds_db_endpoint" {
  description = "RDS endpoint (hostname:port)"
  value       = module.rds.db_endpoint
}

output "rds_db_host" {
  description = "RDS database hostname"
  value       = module.rds.db_host
}

output "rds_db_port" {
  description = "RDS database port"
  value       = module.rds.db_port
}

output "rds_db_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = module.rds.db_username
  sensitive   = true
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds.security_group_id
}

output "rds_credentials_secret_name" {
  description = "Name of the secret in AWS Secrets Manager containing RDS credentials"
  value       = module.rds.rds_credentials_secret_name
}

output "rds_credentials_secret_arn" {
  description = "ARN of the secret in AWS Secrets Manager containing RDS credentials"
  value       = module.rds.rds_credentials_secret_arn
}
