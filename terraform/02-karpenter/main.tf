provider "aws" {
  region = var.aws_region
}

# ECR Public is a global service — token must always come from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

################################################################################
# Read outputs from 01-cluster via remote state
################################################################################

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-poc/01-cluster/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  cluster_name      = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_endpoint  = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca        = data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider     = data.terraform_remote_state.cluster.outputs.oidc_provider
  cluster_arn       = data.terraform_remote_state.cluster.outputs.cluster_arn

  common_tags = merge(
    {
      Project     = local.cluster_name
      ManagedBy   = "Terraform"
      Environment = "poc"
    },
    var.tags,
  )
}

################################################################################
# kubernetes + helm + kubectl providers
# Configured from remote state — cluster is guaranteed to exist before
# this module is ever run.
################################################################################

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# gavinbunney/kubectl skips server-side CRD validation at plan time,
# which means EC2NodeClass / NodePool resources can be planned and applied
# in the same run as the Helm release that installs those CRDs.
provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}
