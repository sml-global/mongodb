variable "name_prefix" {
  description = "Prefix used for EFS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EFS security resources are created."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR used to scope NFS ingress."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where EFS mount targets are created."
  type        = list(string)
}

variable "throughput_mode" {
  description = "EFS throughput mode."
  type        = string
}