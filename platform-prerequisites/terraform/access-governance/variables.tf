variable "aws_region" {
  description = "AWS region where UAT access governance resources are managed."
  type        = string

  validation {
    condition     = var.aws_region == "ap-east-1"
    error_message = "aws_region must be ap-east-1."
  }
}

variable "expected_account_id" {
  description = "AWS account ID where UAT access governance resources are managed."
  type        = string

  validation {
    condition     = var.expected_account_id == "672172129937"
    error_message = "expected_account_id must be 672172129937."
  }
}
