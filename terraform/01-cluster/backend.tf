# ──────────────────────────────────────────────────────────────────────
# Remote backend for 01-cluster state
# Run ../scripts/bootstrap-backend.sh before terraform init.
# Replace REPLACE_ME with your actual bucket name.
# ──────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tf-state-startup-eks-poc"
    key            = "eks-poc/01-cluster/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
