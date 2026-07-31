aws_region           = "ap-east-1"
expected_account_id  = "672172129937"
environment          = "uat"
name_prefix          = "oms-uat-eks"

vpc_cidr              = "10.200.216.0/21"
availability_zones    = ["ap-east-1a", "ap-east-1b"]
private_subnet_cidrs  = ["10.200.216.0/23", "10.200.218.0/23"]
public_subnet_cidrs   = ["10.200.220.0/26", "10.200.220.64/26"]
database_subnet_cidrs = ["10.200.220.128/25", "10.200.221.0/25"]
nat_gateway_count     = 1
nat_mode              = "single"

kubernetes_version      = "1.33"
authentication_mode     = "API"
endpoint_public_access  = false
endpoint_private_access = true
deletion_protection     = true

node_instance_type    = "m6i.large"
node_min_size         = 2
node_desired_size     = 3
node_max_size         = 6
node_root_volume_size = 100
node_spot_enabled     = false

cluster_kms_key_arn     = "arn:aws:kms:ap-east-1:672172129937:key/33333333-3333-3333-3333-333333333333"
cluster_oidc_thumbprint = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url = "https://oidc.eks.ap-east-1.amazonaws.com/id/UATEXAMPLEOIDC"
enable_load_balancer_controller = true

efs_enabled         = true
efs_throughput_mode = "bursting"

backup_enabled            = true
backup_retention_days     = 35
backup_kms_key_arn        = "arn:aws:kms:ap-east-1:672172129937:key/44444444-4444-4444-4444-444444444444"
backup_service_role_arn   = "arn:aws:iam::672172129937:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days  = 35
vault_max_retention_days  = 365

addons = {
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
    configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } })
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