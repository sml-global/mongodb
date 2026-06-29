variable "aws_region" {
  description = "AWS region for the Aurora PostgreSQL resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for generated resource names."
  type        = string
  default     = "dev-pg18"
}

variable "vpc_id" {
  description = "VPC ID where the database security group is created."
  type        = string
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs used by the DB subnet group."
  type        = list(string)
}

variable "allowed_source_security_group_id" {
  description = "Optional application security group ID allowed to connect on 5432."
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "Optional CIDR blocks allowed to connect on 5432. Keep this empty unless needed."
  type        = list(string)
  default     = []
}

variable "db_identifier" {
  description = "Aurora cluster identifier."
  type        = string
  default     = "pg18-dev"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Set null to let AWS select a default for the region."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Aurora provisioned instance class for the single writer (such as db.t4g.medium)."
  type        = string
  default     = "db.t4g.medium"
}

variable "writer_availability_zone" {
  description = "Optional AZ for the only writer instance (such as ap-southeast-1a). Leave empty for AWS placement."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "app"
}

variable "db_master_username" {
  description = "Master username for the database."
  type        = string
  default     = "pgadmin"
}

variable "db_master_password" {
  description = "Master password for the dev database (stored in terraform state). Keep local only."
  type        = string
  sensitive   = true
}
