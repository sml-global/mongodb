variable "aws_region" {
  description = "AWS region hosting EKS and S3."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for Pod Identity association."
  type        = string
}

variable "mongodb_namespace" {
  description = "Namespace where MongoDB components run."
  type        = string
  default     = "mongodb"
}

variable "mongodb_workload_service_account_name" {
  description = "ServiceAccount used by MongoDB workload pods."
  type        = string
  default     = "psmdb-db"
}

variable "pbm_bucket_name" {
  description = "S3 bucket name used by PBM for backups."
  type        = string
}

variable "iam_role_name" {
  description = "IAM role name for MongoDB workload backup/encryption access."
  type        = string
  default     = "mongodb-pbm-role"
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
