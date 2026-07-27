variable "aws_region" {
  type = string
}

variable "expected_account_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_prefix" {
  type = string
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
  type    = map(string)
  default = {}
}
