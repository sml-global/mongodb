variable "environment" {
  description = "Environment name (prod, uat, dev, sit)"
  type        = string
  validation {
    condition     = contains(["prod", "uat", "dev", "sit"], var.environment)
    error_message = "Environment must be one of: prod, uat, dev, sit"
  }
}

variable "aws_account_id" {
  description = "AWS Account ID for this environment"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS Account ID must be 12 digits"
  }
}

variable "prod_account_id" {
  description = "AWS Account ID for production (only required for non-prod environments)"
  type        = string
  default     = ""
}

variable "uat_account_id" {
  description = "AWS Account ID for UAT (only required for prod environment)"
  type        = string
  default     = ""
}

variable "dev_account_id" {
  description = "AWS Account ID for DEV (only required for prod environment)"
  type        = string
  default     = ""
}

variable "sit_account_id" {
  description = "AWS Account ID for SIT (only required for prod environment)"
  type        = string
  default     = ""
}

variable "bucket_name_override" {
  description = "Override default bucket name (default: sml-elt-{environment})"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "lifecycle_days" {
  description = "Number of days before objects are moved to IA storage class"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
