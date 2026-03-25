variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "startup-eks-poc"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR for the dedicated VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "bootstrap_instance_type" {
  description = "EC2 instance type for the bootstrap managed node group"
  type        = string
  default     = "t3.small"
}

variable "bootstrap_min_size" {
  description = "Minimum number of nodes in the bootstrap node group"
  type        = number
  default     = 2
}

variable "bootstrap_max_size" {
  description = "Maximum number of nodes in the bootstrap node group"
  type        = number
  default     = 3
}

variable "bootstrap_desired_size" {
  description = "Desired number of nodes in the bootstrap node group"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Extra tags to add to all resources"
  type        = map(string)
  default     = {}
}
