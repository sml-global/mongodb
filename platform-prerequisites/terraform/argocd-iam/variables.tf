variable "environment" {
  description = "Environment name (dev, uat, prod, sit)"
  type        = string

  validation {
    condition     = contains(["dev", "uat", "prod", "sit"], var.environment)
    error_message = "Environment must be one of: dev, uat, prod, sit"
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name where ArgoCD is running"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN for IRSA"
  type        = string
}

variable "prod_account_id" {
  description = "Production AWS account ID"
  type        = string
  default     = "632674123947"
}

variable "uat_account_id" {
  description = "UAT AWS account ID"
  type        = string
  default     = "672172129937"
}

variable "dev_account_id" {
  description = "DEV AWS account ID"
  type        = string
  default     = "815402439714"
}

variable "sit_account_id" {
  description = "SIT AWS account ID (TBD)"
  type        = string
  default     = ""  # To be filled when SIT account is created
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
