variable "cluster_name" {
  description = "EKS cluster name used for Pod Identity association."
  type        = string
}

variable "namespace" {
  description = "Namespace this CNPG cluster's resources run in. Created by this module."
  type        = string
}

variable "workload_service_account_name" {
  description = "ServiceAccount used by the CNPG workload pods (including the barman-cloud backup path)."
  type        = string
  default     = "oms-postgresql-workload"
}

variable "backup_bucket_name" {
  description = "S3 bucket name used by barman-cloud for WAL archival and backups."
  type        = string
}

variable "iam_role_name" {
  description = "IAM role name for the CNPG workload's backup/encryption access."
  type        = string
}

variable "use_pod_identity" {
  description = "Use EKS Pod Identity association instead of IRSA annotation."
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
  description = "Optional KMS key ARN for encryption access policy."
  type        = string
  default     = ""
}
