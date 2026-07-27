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

# Account ID for sandbox (production account used as temporary sandbox for Phase 2)
expected_account_id = "632674123947"

# Networking (minimal single-AZ for plan validation only)
vpc_cidr             = "10.90.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
private_subnet_cidrs = ["10.90.0.0/20", "10.90.16.0/20"]
public_subnet_cidrs  = ["10.90.128.0/20", "10.90.144.0/20"]
nat_gateway_count    = 1
nat_mode             = "single"

# EKS Cluster
kubernetes_version      = "1.33"
authentication_mode     = "API"
endpoint_public_access  = false
endpoint_private_access = true
deletion_protection     = true

# Node group (minimal for plan validation)
node_instance_type    = "m6i.large"
node_min_size         = 2
node_desired_size     = 2
node_max_size         = 4
node_root_volume_size = 50
node_spot_enabled     = false

# KMS Key for EKS encryption (dummy ARN for sandbox validation)
# Terraform plan validates syntax only; does not check existence
cluster_kms_key_arn = "arn:aws:kms:us-east-1:632674123947:key/11111111-2222-3333-4444-555555555555"

# OIDC Provider for workload identity (dummy values for sandbox validation)
oidc_provider             = "arn:aws:iam::632674123947:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/DUMMY12345"
cluster_oidc_thumbprint   = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url   = "https://oidc.eks.us-east-1.amazonaws.com/id/DUMMY12345"

# Optional features (enabled to exercise full module code paths during plan)
enable_load_balancer_controller = true
efs_enabled                     = true
efs_throughput_mode             = "bursting"

# Disable features not needed for plan validation
enable_cluster_autoscaling = false
enable_ebs_encryption      = true
backup_enabled             = true
backup_retention_days      = 7
backup_kms_key_arn         = "arn:aws:kms:us-east-1:632674123947:key/22222222-3333-4444-5555-666666666666"
backup_service_role_arn    = "arn:aws:iam::632674123947:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days   = 7
vault_max_retention_days   = 35

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
