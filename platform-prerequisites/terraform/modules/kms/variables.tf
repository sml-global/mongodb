variable "name_prefix" {
  description = "Prefix used for KMS key aliases and descriptions."
  type        = string
}

variable "deletion_window_in_days" {
  description = "KMS key deletion recovery window. Bounded to a conservative minimum so an accidental destroy leaves a recovery margin."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 30
    error_message = "deletion_window_in_days must be at least 30 to leave a real recovery margin before key material is destroyed."
  }
}
