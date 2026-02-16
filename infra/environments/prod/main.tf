terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

terraform {
  backend "s3" {
    bucket      = "simple-time-service-tf-state-prod"
    key         = "prod/terraform.tfstate"
    region      = "us-east-1"
    use_lockfile = true
    encrypt     = true
  }
}

locals {
  eks_cluster_name = "${var.project_name}-${var.environment}"
}

module "vpc" {
  source = "../../terraform/modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  eks_cluster_name     = local.eks_cluster_name
}

module "eks" {
  source = "../../terraform/modules/eks"

  project_name = var.project_name
  cluster_name = local.eks_cluster_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
  aws_region   = var.aws_region
  # Set to true to skip automatic addon installation (install via CI/manually)
  # skip_addons_install = false
  subnet_ids   = module.vpc.private_subnet_ids
}

module "ec2" {
  source = "../../terraform/modules/ec2"
}

module "rds" {
  source = "../../terraform/modules/rds"

  project_name           = var.project_name
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  eks_security_group_id  = module.eks.cluster_security_group_id
  
  # RDS Configuration
  postgres_version       = var.postgres_version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  database_name          = var.rds_database_name
  master_username        = var.rds_master_username
  multi_az               = var.rds_multi_az
  backup_retention_days  = var.rds_backup_retention_days
  deletion_protection    = var.rds_deletion_protection
  skip_final_snapshot    = var.rds_skip_final_snapshot
}