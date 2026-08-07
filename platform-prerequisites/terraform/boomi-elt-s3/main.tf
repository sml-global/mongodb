terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via backend-config:
    # terraform init \
    #   -backend-config="bucket=sml-oms-dev-tfstate" \
    #   -backend-config="key=boomi-elt-s3/{environment}.tfstate" \
    #   -backend-config="region=ap-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-east-1"

  default_tags {
    tags = merge(
      {
        ManagedBy   = "Terraform"
        Environment = var.environment
        Project     = "OMS-Boomi-ELT"
      },
      var.tags
    )
  }
}

locals {
  bucket_name = var.bucket_name_override != "" ? var.bucket_name_override : "sml-elt-${var.environment}"
  is_prod     = var.environment == "prod"
}
