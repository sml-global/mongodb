# Sandbox EKS Platform Terraform Configuration
# Phase 2 Validation Environment (us-east-1, Production Account)
#
# Purpose: Validate Phase 2 EKS Platform code using terraform plan (read-only)
# Region: us-east-1 (cheapest AWS region)
# Account: 632674123947 (Production account, used as temporary sandbox for Phase 2)
# Note: UAT Account (672172129937) reserved for actual UAT environment work
# Isolation: Distinct name_prefix (oms-sandbox-eks) to avoid IAM collision
#
# Note: Uses dummy KMS and OIDC ARNs (syntax valid for plan validation)
# Terraform plan does NOT verify existence of these resources

name_prefix    = "oms-sandbox-eks"
environment    = "sandbox"
aws_region     = "us-east-1"

# KMS Key for EKS encryption (dummy ARN for sandbox validation)
# Terraform plan validates syntax only; does not check existence
cluster_kms_key_arn = "arn:aws:kms:us-east-1:632674123947:key/11111111-2222-3333-4444-555555555555"

# OIDC Provider for workload identity (dummy ARN for sandbox validation)
oidc_provider = "arn:aws:iam::632674123947:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/DUMMY12345"

# Disable features not needed for plan validation
enable_cluster_autoscaling = false
enable_ebs_encryption      = true
enable_backup              = false

# EKS Add-ons configuration (from UAT baseline)
addons = {
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
  coredns = {
    enabled              = true
    addon_version        = "v1.12.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
  kube-proxy = {
    enabled              = true
    addon_version        = "v1.33.0-eksbuild.2"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
  aws-ebs-csi-driver = {
    enabled              = true
    addon_version        = "v2.17.0-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = true
  }
}

# Tags
tags = {
  Environment = "sandbox"
  Purpose     = "Phase2-Validation"
  ManagedBy   = "Terraform"
}
