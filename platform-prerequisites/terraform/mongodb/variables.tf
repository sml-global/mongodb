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

variable "cluster_name" {
  description = "EKS cluster name used for Pod Identity association (passed through to the reusable module)."
  type        = string
}

variable "mongodb_namespace" {
  description = "Namespace where MongoDB components run (passed through to the reusable module)."
  type        = string
  default     = "mongodb"
}

variable "mongodb_workload_service_account_name" {
  description = "ServiceAccount used by MongoDB workload pods, including the PBM sidecar path (passed through to the reusable module)."
  type        = string
  default     = "psmdb-db"
}

variable "pbm_bucket_name" {
  description = "S3 bucket name used by PBM for backups. Created by the reusable module using this name."
  type        = string
}

variable "iam_role_name" {
  description = "IAM role name for MongoDB workload backup/encryption access (passed through to the reusable module)."
  type        = string
  default     = "mongodb-pbm-role"
}

variable "use_pod_identity" {
  description = "Use EKS Pod Identity association instead of IRSA annotation (passed through to the reusable module)."
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
  description = "Optional KMS key ARN for PBM S3 encryption access policy."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
