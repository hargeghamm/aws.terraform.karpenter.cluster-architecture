# ──────────────────────────────────────────────────────────────────────
# Remote backend for 02-karpenter state
# Run ../scripts/bootstrap-backend.sh before terraform init.
# Replace REPLACE_ME with your actual bucket name.
# ──────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tf-state-startup-eks-poc"
    key            = "eks-poc/02-karpenter/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
