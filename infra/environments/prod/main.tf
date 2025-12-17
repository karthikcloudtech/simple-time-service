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
    bucket         = "simple-time-service-tf-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "simple-time-service-tf-lock-prod"
    encrypt        = true
  }
}

locals {
  eks_cluster_name = "${var.project_name}-${var.environment}"
}

module "vpc" {
  source = "../../terraform/modules/vpc"

  project_name         = var.project_name
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
  subnet_ids   = module.vpc.private_subnet_ids
}
