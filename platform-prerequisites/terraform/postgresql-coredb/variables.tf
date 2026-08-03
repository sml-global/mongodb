variable "aws_region" {
  description = "AWS region for platform resources."
  type        = string
}

variable "expected_account_id" {
  description = "Approved AWS account for deployment."
  type        = string
}

variable "environment" {
  description = "Environment identifier (for example, dev or sit)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming platform resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for Pod Identity association (passed through to the cnpg-prereqs module)."
  type        = string
}

variable "namespace" {
  description = "Namespace the core CNPG cluster runs in (passed through to the cnpg-prereqs module)."
  type        = string
  default     = "coredb"
}

variable "workload_service_account_name" {
  description = "ServiceAccount used by the core CNPG workload pods (passed through to the cnpg-prereqs module)."
  type        = string
  default     = "oms-postgresql-workload"
}

variable "backup_bucket_name" {
  description = "S3 bucket name used by barman-cloud for the core cluster's WAL archival and backups. Created by the cnpg-prereqs module using this name."
  type        = string
}

variable "iam_role_name" {
  description = "IAM role name for the core CNPG workload's backup/encryption access (passed through to the cnpg-prereqs module)."
  type        = string
  default     = "postgresql-coredb-cnpg-role"
}

variable "use_pod_identity" {
  description = "Use EKS Pod Identity association instead of IRSA annotation (passed through to the cnpg-prereqs module)."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA mode. Required when use_pod_identity=false."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "OIDC provider URL for IRSA mode. Required when use_pod_identity=false."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for backup bucket encryption access policy."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
