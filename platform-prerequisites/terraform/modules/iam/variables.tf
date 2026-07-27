variable "name_prefix" {
  description = "Prefix used for IAM role names."
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL from the EKS cluster identity."
  type        = string
}

variable "cluster_oidc_thumbprint" {
  description = "Thumbprint for the EKS OIDC provider."
  type        = string
}

variable "node_group_name" {
  description = "Node group name used in autoscaler trust policy conditions."
  type        = string
}

variable "enable_load_balancer_controller" {
  description = "Whether the load balancer controller IAM role is provisioned."
  type        = bool
}