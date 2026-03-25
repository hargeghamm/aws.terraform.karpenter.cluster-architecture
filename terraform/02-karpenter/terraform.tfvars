# ──────────────────────────────────────────────
# Must match values used in 01-cluster
# ──────────────────────────────────────────────
aws_region   = "eu-central-1"
cluster_name = "startup-eks-poc"

# S3 bucket (must match backend.tf and 01-cluster/backend.tf)
state_bucket = "tf-state-startup-eks-poc"

# ──────────────────────────────────────────────
# Karpenter settings
# ──────────────────────────────────────────────
karpenter_version     = "1.9.0"
nodepool_cpu_limit    = "200"
nodepool_memory_limit = "400Gi"
node_volume_size      = 50

sqs_message_retention_seconds = 300

# ──────────────────────────────────────────────
# Extra tags (optional)
# ──────────────────────────────────────────────
tags = {
  Team = "platform"
}
