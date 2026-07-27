variable "aws_region" {
  description = "AWS region containing the UAT EKS cluster."
  type        = string

  validation {
    condition     = var.aws_region == "ap-east-1"
    error_message = "aws_region must be ap-east-1."
  }
}

variable "expected_account_id" {
  description = "AWS account ID containing the UAT EKS cluster."
  type        = string

  validation {
    condition     = var.expected_account_id == "672172129937"
    error_message = "expected_account_id must be 672172129937."
  }
}

variable "eks_cluster_name" {
  description = "Name of the UAT EKS cluster."
  type        = string

  validation {
    condition     = var.eks_cluster_name == "EKS-boomi-runtime-cluster"
    error_message = "eks_cluster_name must be EKS-boomi-runtime-cluster."
  }
}

variable "boomi_namespace" {
  description = "Namespace administered by the UAT Boomi administrators."
  type        = string

  validation {
    condition     = var.boomi_namespace == "boomi-uat"
    error_message = "boomi_namespace must be boomi-uat."
  }
}

variable "infra_admin_role_arn" {
  description = "UAT IAM Identity Center role ARN for infrastructure administrators."
  type        = string

  validation {
    condition = can(regex(
      "^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATInfraAdminEA_[A-Za-z0-9]+$",
      var.infra_admin_role_arn
    ))
    error_message = "infra_admin_role_arn must be the UATInfraAdminEA AWSReservedSSO role in account 672172129937."
  }
}

variable "application_developer_role_arn" {
  description = "UAT IAM Identity Center role ARN for application developers."
  type        = string

  validation {
    condition = can(regex(
      "^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATApplicationDeveloper_[A-Za-z0-9]+$",
      var.application_developer_role_arn
    ))
    error_message = "application_developer_role_arn must be the UATApplicationDeveloper AWSReservedSSO role in account 672172129937."
  }
}

variable "boomi_admin_role_arn" {
  description = "UAT IAM Identity Center role ARN for Boomi administrators."
  type        = string

  validation {
    condition = can(regex(
      "^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATBoomiAdmin_[A-Za-z0-9]+$",
      var.boomi_admin_role_arn
    ))
    error_message = "boomi_admin_role_arn must be the UATBoomiAdmin AWSReservedSSO role in account 672172129937."
  }
}