# ──────────────────────────────────────────────
# Core
# ──────────────────────────────────────────────
aws_region         = "eu-central-1"
cluster_name       = "startup-eks-poc"
kubernetes_version = "1.35"

# ──────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────
vpc_cidr = "10.42.0.0/16"

# ──────────────────────────────────────────────
# Bootstrap node group
# ──────────────────────────────────────────────
bootstrap_instance_type = "t3.small"
bootstrap_min_size      = 2
bootstrap_max_size      = 3
bootstrap_desired_size  = 2

# ──────────────────────────────────────────────
# Extra tags (optional)
# ──────────────────────────────────────────────
tags = {
  Team = "platform"
}
