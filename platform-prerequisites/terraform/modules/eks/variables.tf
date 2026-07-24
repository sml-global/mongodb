variable "name_prefix" {
  description = "Prefix used for EKS platform resources."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version."
  type        = string
}

variable "authentication_mode" {
  description = "EKS access configuration authentication mode."
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether EKS API endpoint allows public access."
  type        = bool
}

variable "endpoint_private_access" {
  description = "Whether EKS API endpoint allows private VPC access."
  type        = bool
}

variable "deletion_protection" {
  description = "Whether EKS cluster deletion protection is enabled."
  type        = bool
}

variable "cluster_role_arn" {
  description = "IAM role ARN for EKS control plane."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS managed node group."
  type        = string
}

variable "addon_role_arn" {
  description = "IAM role ARN for CSI managed addons."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by EKS control plane and nodes."
  type        = list(string)
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
  description = "Root volume size in GiB for node launch template."
  type        = number
}

variable "node_spot_enabled" {
  description = "Whether the node group uses spot capacity."
  type        = bool
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN used to encrypt EKS secrets."
  type        = string
}

variable "addons" {
  description = "Explicit add-on versions and enabled flags."
  type = map(object({
    enabled              = bool
    addon_version        = string
    resolve_conflicts    = optional(string, "OVERWRITE")
    service_account_role = optional(bool, false)
  }))
}