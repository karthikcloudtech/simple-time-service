variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "simple-time-service"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "eks_node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
}

variable "eks_node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "eks_node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "eks_node_instance_types" {
  description = "EKS node instance types"
  type        = list(string)
}

variable "eks_node_capacity_type" {
  description = "Capacity type for EKS nodes - ON_DEMAND (faster provisioning) or SPOT (cheaper but slower)"
  type        = string
  default     = "ON_DEMAND"
}
