# Sandbox EKS Platform Terraform Configuration
# Phase 2 Validation Environment (us-east-1, UAT Account)
#
# Purpose: Validate Phase 2 EKS Platform code using terraform plan (read-only)
# Region: us-east-1 (cheapest AWS region)
# Account: 672172129937 (UAT account, shared with ap-east-1 UAT environment)
# Isolation: Distinct name_prefix (oms-sandbox-eks) to avoid IAM collision
#
# Note: Uses dummy KMS and OIDC ARNs (syntax valid for plan validation)
# Terraform plan does NOT verify existence of these resources

name_prefix    = "oms-sandbox-eks"
environment    = "sandbox"
aws_region     = "us-east-1"

# KMS Key for EKS encryption (dummy ARN for sandbox validation)
# Terraform plan validates syntax only; does not check existence
cluster_kms_key_arn = "arn:aws:kms:us-east-1:672172129937:key/11111111-2222-3333-4444-555555555555"

# OIDC Provider for workload identity (dummy ARN for sandbox validation)
oidc_provider = "arn:aws:iam::672172129937:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/DUMMY12345"

# Disable features not needed for plan validation
enable_cluster_autoscaling = false
enable_ebs_encryption      = true
enable_backup              = false

# Tags
tags = {
  Environment = "sandbox"
  Purpose     = "Phase2-Validation"
  ManagedBy   = "Terraform"
}
