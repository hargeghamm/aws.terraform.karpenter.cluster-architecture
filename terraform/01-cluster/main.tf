provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = merge(
    {
      Project     = var.cluster_name
      ManagedBy   = "Terraform"
      Environment = "poc"
    },
    var.tags,
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for idx, az in local.azs : cidrsubnet(var.vpc_cidr, 4, idx)]
  public_subnets  = [for idx, az in local.azs : cidrsubnet(var.vpc_cidr, 4, idx + 8)]

  enable_nat_gateway = true
  # POC: single NAT GW to reduce cost.
  # For production set single_nat_gateway = false for AZ-redundant NAT.
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    bootstrap = {
      name           = "bootstrap"
      instance_types = [var.bootstrap_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.bootstrap_min_size
      max_size     = var.bootstrap_max_size
      desired_size = var.bootstrap_desired_size

      # AL2023 is the recommended AMI for EKS 1.33+
      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role = "bootstrap"
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  cluster_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.common_tags
}
