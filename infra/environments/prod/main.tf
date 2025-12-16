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

# VPC Module
module "vpc" {
  source = "../../terraform/modules/vpc"

  project_name           = var.project_name
  environment            = var.environment
  vpc_cidr               = var.vpc_cidr
  availability_zones     = var.availability_zones
  private_subnet_cidrs   = var.private_subnet_cidrs
  public_subnet_cidrs    = var.public_subnet_cidrs
  eks_cluster_name       = var.eks_cluster_name
}

# EKS Module
module "eks" {
  source = "../../terraform/modules/eks"

  project_name            = var.project_name
  environment             = var.environment
  cluster_name            = var.eks_cluster_name
  cluster_version         = var.eks_cluster_version
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnet_ids
  node_group_desired_size = var.eks_node_group_desired_size
  node_group_min_size     = var.eks_node_group_min_size
  node_group_max_size     = var.eks_node_group_max_size
  node_instance_types     = var.eks_node_instance_types
  node_capacity_type      = var.eks_node_capacity_type
}
