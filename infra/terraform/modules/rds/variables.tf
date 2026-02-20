variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "db_private_subnet_ids" {
  description = "DB private subnet IDs for DB subnet group"
  type        = list(string)
}


variable "node_security_group_id" {
  description = "EKS node group security group ID for ingress rules"
  type        = string
}


variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  type        = string
}
variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  type        = string
}


variable "postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "18.1"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "simple_time_service"
}

variable "master_username" {
  description = "Master database username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "master_password" {
  description = "DEPRECATED: Master password is now managed by AWS Secrets Manager"
  type        = string
  default     = ""
  sensitive   = true
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = false
}
