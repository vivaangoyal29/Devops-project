variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devops-cluster"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "eks_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 3
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "devops-app"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deployment role, in owner/repo format"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must be in owner/repository format."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS public API endpoint"
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "Set at least one trusted CIDR for the EKS public API endpoint; do not expose it to all addresses."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project = "devops-final-project"
    Environment = "production"
    ManagedBy = "terraform"
  }
}
