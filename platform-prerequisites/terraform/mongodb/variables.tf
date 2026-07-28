variable "aws_region" {
  description = "AWS region for platform resources."
  type        = string
}

variable "expected_account_id" {
  description = "Approved AWS account for deployment."
  type        = string
}

variable "environment" {
  description = "Environment identifier (for example, dev or uat)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming platform resources."
  type        = string
}

variable "pbm_bucket_name" {
  description = "From platform_contract.pbm_bucket_name (Phase 2 output)"
  type        = string
}

variable "operator_iam_role_arn" {
  description = "From platform_contract.operator_iam_role_arn (Phase 2 output)"
  type        = string
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN for PBM S3 encryption"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
