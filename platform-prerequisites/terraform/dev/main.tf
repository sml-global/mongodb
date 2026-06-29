terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.26"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "target" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target.token
}

module "mongodb_prerequisites" {
  source = ".."

  cluster_name                         = var.cluster_name
  mongodb_namespace                    = var.mongodb_namespace
  mongodb_workload_service_account_name = var.mongodb_workload_service_account_name
  pbm_bucket_name                      = var.pbm_bucket_name
  iam_role_name                        = var.iam_role_name
  use_pod_identity                     = var.use_pod_identity
  oidc_provider_arn                    = var.oidc_provider_arn
  oidc_provider_url                    = var.oidc_provider_url
  kms_key_arn                          = var.kms_key_arn
}
