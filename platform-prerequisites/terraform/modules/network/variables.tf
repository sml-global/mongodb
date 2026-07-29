variable "name_prefix" {
  description = "Prefix used for network resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones used for subnet placement."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must include at least two AZs."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_subnet_cidrs must match availability_zones length."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs must match availability_zones length."
  }
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks, one per AZ. Empty list means no database tier (CNPG environments)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.database_subnet_cidrs) == 0 || length(var.database_subnet_cidrs) == length(var.availability_zones)
    error_message = "database_subnet_cidrs must be empty or match availability_zones length."
  }
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways for private subnet egress."
  type        = number
  default     = 1

  validation {
    condition = (
      (var.nat_mode == "single" && var.nat_gateway_count == 1) ||
      (var.nat_mode == "one-per-az" && var.nat_gateway_count == length(var.availability_zones))
    )
    error_message = "nat_gateway_count must match nat_mode (single=1, one-per-az=availability_zones length)."
  }
}

variable "nat_mode" {
  description = "NAT topology mode."
  type        = string

  validation {
    condition     = contains(["single", "one-per-az"], var.nat_mode)
    error_message = "nat_mode must be single or one-per-az."
  }
}