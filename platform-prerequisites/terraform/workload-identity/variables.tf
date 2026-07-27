variable "aws_region" {
  description = "AWS region for workload identity resources."
  type        = string
}

variable "expected_account_id" {
  description = "Expected AWS account ID from the platform contract."
  type        = string
}

variable "environment" {
  description = "Environment name that scopes identity role names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must use lowercase letters, numbers, and hyphens only."
  }
}

variable "cluster_name" {
  description = "Expected EKS cluster name from the platform contract."
  type        = string
}

variable "eks_platform_state_bucket" {
  description = "S3 bucket storing the eks-platform Terraform state."
  type        = string
}

variable "eks_platform_state_key" {
  description = "S3 key for the eks-platform Terraform state object."
  type        = string
}

variable "eks_platform_state_use_lockfile" {
  description = "Whether to use native S3 lockfiles while reading remote state."
  type        = bool
  default     = true
}

variable "identities" {
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
    description     = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for identity_key in keys(var.identities) :
      can(regex("^[a-z0-9-]+$", identity_key))
    ])
    error_message = "Identity map keys must use lowercase letters, numbers, and hyphens only."
  }
}
