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

variable "vpc_cidr" {
  description = "VPC CIDR block for the EKS platform."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones used for EKS networking."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks aligned to availability_zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks aligned to availability_zones."
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks for Aurora, one per AZ. Empty list for CNPG-only environments (dev)."
  type        = list(string)
  default     = []
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways."
  type        = number
}

variable "nat_mode" {
  description = "NAT topology mode: single or one-per-az."
  type        = string

  validation {
    condition     = contains(["single", "one-per-az"], var.nat_mode)
    error_message = "nat_mode must be single or one-per-az."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
}

variable "authentication_mode" {
  description = "Authentication mode for EKS access config."
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether the EKS endpoint is publicly reachable."
  type        = bool
}

variable "endpoint_private_access" {
  description = "Whether the EKS endpoint is privately reachable."
  type        = bool
}

variable "deletion_protection" {
  description = "EKS cluster deletion protection toggle."
  type        = bool
}

variable "node_instance_type" {
  description = "Managed node group instance type."
  type        = string
}

variable "node_min_size" {
  description = "Node group minimum size."
  type        = number
}

variable "node_desired_size" {
  description = "Node group desired size."
  type        = number
}

variable "node_max_size" {
  description = "Node group maximum size."
  type        = number
}

variable "node_root_volume_size" {
  description = "Root volume size for managed nodes."
  type        = number
}

variable "node_spot_enabled" {
  description = "Whether nodes use spot capacity."
  type        = bool
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN for EKS secret encryption."
  type        = string
}

variable "cluster_oidc_thumbprint" {
  description = "OIDC thumbprint used by IAM OIDC provider."
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL used to configure IAM trust relationships."
  type        = string
}

variable "enable_load_balancer_controller" {
  description = "Whether the load balancer controller IAM identity is provisioned."
  type        = bool
}

variable "efs_enabled" {
  description = "Whether EFS resources are provisioned."
  type        = bool
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode."
  type        = string
}

variable "backup_enabled" {
  description = "Whether AWS Backup resources are provisioned."
  type        = bool
}

variable "backup_retention_days" {
  description = "Backup retention in days."
  type        = number
}

variable "backup_kms_key_arn" {
  description = "Approved KMS key ARN used by backup vault."
  type        = string
}

variable "backup_service_role_arn" {
  description = "IAM role ARN used by AWS Backup selection."
  type        = string
}

variable "vault_min_retention_days" {
  description = "Vault lock minimum retention metadata."
  type        = number
}

variable "vault_max_retention_days" {
  description = "Vault lock maximum retention metadata."
  type        = number
}

variable "addons" {
  description = "Explicit add-on version map; never use latest selectors."
  type = map(object({
    enabled              = bool
    addon_version        = string
    resolve_conflicts    = optional(string, "OVERWRITE")
    service_account_role = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for addon in values(var.addons) :
      lower(addon.addon_version) != "latest"
    ])
    error_message = "addons[*].addon_version must be explicit and cannot be latest."
  }
}