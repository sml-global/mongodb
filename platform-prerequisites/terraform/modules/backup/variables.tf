variable "name_prefix" {
  description = "Prefix used for backup resources."
  type        = string
}

variable "deployment_environment" {
  description = "Environment identifier used for policy constraints."
  type        = string
}

variable "backup_retention_days" {
  description = "Retention window for backup recovery points."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "backup_retention_days must be at least 1."
  }
}

variable "backup_kms_key_arn" {
  description = "Approved KMS key ARN used by AWS Backup vault encryption."
  type        = string
}

variable "backup_target_resource_arns" {
  description = "Resource ARNs selected for backup."
  type        = list(string)
}

variable "backup_service_role_arn" {
  description = "IAM role ARN used by AWS Backup selection."
  type        = string
}

variable "vault_min_retention_days" {
  description = "Compliance metadata for backup vault lock minimum retention."
  type        = number

  validation {
    condition     = var.vault_min_retention_days >= 1
    error_message = "vault_min_retention_days must be at least 1."
  }
}

variable "vault_max_retention_days" {
  description = "Compliance metadata for backup vault lock maximum retention."
  type        = number

  validation {
    condition     = var.vault_max_retention_days >= var.vault_min_retention_days
    error_message = "vault_max_retention_days must be >= vault_min_retention_days."
  }
}