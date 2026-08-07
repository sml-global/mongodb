terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via backend-config:
    # terraform init \
    #   -backend-config="bucket=sml-oms-prod-tfstate" \
    #   -backend-config="key=argocd-iam/{environment}.tfstate" \
    #   -backend-config="region=ap-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy   = "Terraform"
        Environment = var.environment
        Project     = "OMS-ArgoCD-IAM"
        Component   = "ArgoCD"
      },
      var.tags
    )
  }
}

locals {
  is_prod = var.environment == "prod"

  # OIDC provider for EKS (required for IRSA)
  # This will be fetched from eks-platform remote state
  cluster_name        = var.cluster_name
  oidc_provider_arn   = var.oidc_provider_arn
  oidc_provider_url   = replace(var.oidc_provider_arn, "/^(.*provider/)/", "")

  # ArgoCD namespace and ServiceAccount
  argocd_namespace = "argocd"
  argocd_sa_name   = "argocd-application-controller"
}
