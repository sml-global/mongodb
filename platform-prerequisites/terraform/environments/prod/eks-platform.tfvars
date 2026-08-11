# Production EKS Platform Terraform Configuration
# Replaces the temporary `sandbox` validation environment in this same AWS account.
# Sandbox MUST be fully torn down first — see docs/superpowers/plans/2026-07-29-network-and-uat-provisioning.md Task 8.

name_prefix          = "oms-prod-eks"
environment          = "prod"
aws_region           = "ap-east-1"
expected_account_id  = "632674123947"

vpc_cidr              = "10.200.0.0/17"
availability_zones    = ["ap-east-1a", "ap-east-1b", "ap-east-1c"]
private_subnet_cidrs  = ["10.200.0.0/19", "10.200.32.0/19", "10.200.64.0/19"]
public_subnet_cidrs   = ["10.200.96.0/26", "10.200.96.64/26", "10.200.96.128/26"]
database_subnet_cidrs = ["10.200.97.0/24", "10.200.98.0/24", "10.200.99.0/24"]
nat_gateway_count     = 3
nat_mode              = "one-per-az"

kubernetes_version      = "1.33"
authentication_mode     = "API"
endpoint_public_access  = false
endpoint_private_access = true
deletion_protection     = true

node_instance_type    = "m6i.xlarge"
node_min_size         = 3
node_desired_size     = 3
node_max_size         = 9
node_root_volume_size = 100
node_spot_enabled     = false

# Resolved from the first eks-platform apply's `platform_contract.iam_roles.oidc_provider` output (2026-08-11).
cluster_oidc_thumbprint = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url = "https://oidc.eks.ap-east-1.amazonaws.com/id/145C35AC6D78AEF86CE1540C88F3BDF0"
enable_load_balancer_controller = true

efs_enabled         = true
efs_throughput_mode = "bursting"

backup_enabled            = true
backup_retention_days     = 35
backup_service_role_arn   = "arn:aws:iam::632674123947:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days  = 35
vault_max_retention_days  = 365

addons = {
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
    configuration_values = "{\"env\":{\"ENABLE_PREFIX_DELEGATION\":\"true\",\"WARM_PREFIX_TARGET\":\"1\"}}"
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
    addon_version        = "v1.44.0-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = true
  }
  aws-efs-csi-driver = {
    enabled              = true
    addon_version        = "v2.1.10-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = true
  }
  eks-pod-identity-agent = {
    enabled              = true
    addon_version        = "v1.3.8-eksbuild.2"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
}
