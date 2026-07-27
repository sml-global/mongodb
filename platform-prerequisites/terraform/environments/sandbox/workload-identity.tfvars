# Sandbox Workload Identity Terraform Configuration
# Phase 2 Validation Environment (us-east-1, Production Account)
#
# Purpose: Configure workload identity for sandbox validation environment
# Links to sandbox EKS platform state outputs
# Account: 632674123947 (Production, temporary sandbox for Phase 2)
# Note: UAT Account (672172129937) reserved for actual UAT environment work

environment = "sandbox"
aws_region  = "us-east-1"

# Terraform backend references (for state file isolation)
terraform_state_bucket = "oms-sandbox-eks-tfstate"

# Tags
tags = {
  Environment = "sandbox"
  Purpose     = "Phase2-Validation"
  ManagedBy   = "Terraform"
}
