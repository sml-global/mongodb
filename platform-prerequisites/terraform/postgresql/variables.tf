variable "aws_region" {
  description = "AWS region for platform resources."
  type        = string
}

variable "expected_account_id" {
  description = "Approved AWS account for deployment."
  type        = string
}

variable "environment" {
  description = "Environment identifier (for example, sandbox or uat)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming platform resources."
  type        = string
}

variable "cnpg_backup_bucket_name" {
  description = "S3 bucket for CloudNativePG WAL archive and base backup (from Phase 2 platform_contract)."
  type        = string
}

variable "postgresql_operator_iam_role_arn" {
  description = "From platform_contract.postgresql_operator_iam_role_arn (Phase 2 output)."
  type        = string
}

variable "cluster_kms_key_arn" {
  description = "KMS key ARN for CNPG S3 backup encryption."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID from the eks-platform platform_contract output, for the Aurora security group."
  type        = string
}

variable "database_subnet_ids" {
  description = "Database subnet IDs from eks-platform's platform_contract.database_subnet_ids output."
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "database_subnet_ids must include at least two subnets (AWS RDS/Aurora hard requirement: a DB subnet group must span at least two Availability Zones)."
  }
}

variable "allowed_source_security_group_id" {
  description = "Security group ID (typically the EKS node/workload security group) allowed to reach Aurora on the PostgreSQL port."
  type        = string
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version, kept in lockstep between uat and prod per the Database Engine Decision in the design spec."
  type        = string
}

variable "aurora_instance_class" {
  description = "Aurora DB instance class (for example db.r6g.large)."
  type        = string
}

variable "aurora_instance_count" {
  description = "Number of Aurora cluster instances (writer + readers)."
  type        = number
  default     = 1

  validation {
    condition     = var.aurora_instance_count >= 1
    error_message = "aurora_instance_count must be at least 1."
  }
}

variable "aurora_database_name" {
  description = "Initial database name created in the Aurora cluster."
  type        = string
}

variable "aurora_master_username" {
  description = "Aurora master username. The password is managed by AWS Secrets Manager (manage_master_user_password), never set here."
  type        = string
}
