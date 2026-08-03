variable "name_prefix" {
  description = "Prefix used for naming Aurora resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the Aurora security group. Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "database_subnet_ids" {
  description = "Database subnet IDs, at least two spanning distinct Availability Zones. Empty list means no Aurora is provisioned (CNPG-only)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.database_subnet_ids) == 0 || length(var.database_subnet_ids) >= 2
    error_message = "database_subnet_ids must be empty or include at least two subnets (AWS RDS/Aurora hard requirement: a DB subnet group must span at least two Availability Zones)."
  }
}

variable "allowed_source_security_group_id" {
  description = "Security group ID (typically the EKS node/workload security group) allowed to reach Aurora on the PostgreSQL port. Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version. Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "aurora_instance_class" {
  description = "Aurora DB instance class (for example db.r6g.large). Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "aurora_instance_count" {
  description = "Number of Aurora cluster instances (writer + readers). 1 = single-AZ; >= 2 = Aurora places replicas across AZs automatically."
  type        = number
  default     = 1

  validation {
    condition     = var.aurora_instance_count >= 1
    error_message = "aurora_instance_count must be at least 1."
  }
}

variable "aurora_database_name" {
  description = "Initial database name created in the Aurora cluster. Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "aurora_master_username" {
  description = "Aurora master username. The password is managed by AWS Secrets Manager (manage_master_user_password), never set here. Empty string means no Aurora is provisioned (CNPG-only)."
  type        = string
  default     = ""
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN for Aurora storage encryption."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
