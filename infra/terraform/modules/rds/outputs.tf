output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.postgres.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.postgres.arn
}

output "db_endpoint" {
  description = "RDS endpoint (hostname:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "db_host" {
  description = "RDS database hostname"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "RDS database port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "RDS master username"
  value       = aws_db_instance.postgres.username
  sensitive   = true
}

output "db_master_user_secret_arn" {
  description = "ARN of the master user password secret in Secrets Manager"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
output "rds_credentials_secret_name" {
  description = "Name of the secret in AWS Secrets Manager containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.name
}

output "rds_credentials_secret_arn" {
  description = "ARN of the secret in AWS Secrets Manager containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}