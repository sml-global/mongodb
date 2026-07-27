variable "aws_region" {
  description = "AWS region for platform resources."
  type        = string
}

variable "expected_account_id" {
  description = "Approved AWS account for deployment."
  type        = string
}

variable "environment" {
  description = "Environment identifier (for example, sandbox or uat)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming platform resources."
  type        = string
}

variable "cnpg_backup_bucket_name" {
  description = "S3 bucket for CloudNativePG WAL archive and base backup (from Phase 2 platform_contract)."
  type        = string
}

variable "postgresql_operator_iam_role_arn" {
  description = "From platform_contract.postgresql_operator_iam_role_arn (Phase 2 output)."
  type        = string
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN for CNPG S3 backup encryption."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
