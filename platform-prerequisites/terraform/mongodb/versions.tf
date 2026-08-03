terraform {
  required_version = ">= 1.10.0"
  backend "s3" {
    use_lockfile = true
  }
  required_providers {
    aws        = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.26" }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
