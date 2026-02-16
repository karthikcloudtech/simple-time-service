# RDS PostgreSQL Database Module

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
    description     = "Allow PostgreSQL from EKS cluster"
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.eks_private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = var.master_username

  allocated_storage     = var.allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  deletion_protection   = var.deletion_protection
  backup_retention_period = var.backup_retention_days
  copy_tags_to_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  manage_master_user_password = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-postgres-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  multi_az            = var.multi_az
  auto_minor_version_upgrade = false
  
  tags = {
    Name = "${var.project_name}-postgres"
  }
}
# Custom secret for project-specific RDS credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project_name}-rds-credentials"
  description             = "RDS credentials for ${var.project_name}"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-rds-credentials"
  }
}

# Store credentials in the secret
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.postgres.username
    password = try(nonsensitive(aws_db_instance.postgres.master_user_secret[0].secret_string), "")
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = aws_db_instance.postgres.db_name
  })
}