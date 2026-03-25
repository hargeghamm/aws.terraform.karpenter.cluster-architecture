variable "aws_region" {
  description = "AWS region (must match 01-cluster)"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name (must match 01-cluster)"
  type        = string
  default     = "startup-eks-poc"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.9.0"
}

variable "nodepool_cpu_limit" {
  description = "Max vCPU limit per Karpenter NodePool"
  type        = string
  default     = "200"
}

variable "nodepool_memory_limit" {
  description = "Max memory limit per Karpenter NodePool"
  type        = string
  default     = "400Gi"
}

variable "node_volume_size" {
  description = "Root EBS volume size (GiB) for Karpenter-provisioned nodes"
  type        = number
  default     = 50
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention in seconds for Karpenter interruption queue"
  type        = number
  default     = 300
}

variable "state_bucket" {
  description = "S3 bucket name used for remote state (must match backend.tf)"
  type        = string
  default     = "REPLACE_ME_tf-state-startup-eks-poc"
}

variable "tags" {
  description = "Extra tags to add to all resources"
  type        = map(string)
  default     = {}
}
