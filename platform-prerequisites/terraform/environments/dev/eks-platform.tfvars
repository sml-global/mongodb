aws_region           = "ap-east-1"
expected_account_id  = "815402439714"
environment          = "dev"
name_prefix          = "oms-dev-eks"

vpc_cidr             = "10.70.0.0/16"
availability_zones   = ["ap-east-1a", "ap-east-1b"]
private_subnet_cidrs = ["10.70.0.0/20", "10.70.16.0/20"]
public_subnet_cidrs  = ["10.70.128.0/20", "10.70.144.0/20"]
nat_gateway_count    = 1
nat_mode             = "single"

kubernetes_version      = "1.33"
authentication_mode     = "API"
endpoint_public_access  = false
endpoint_private_access = true
deletion_protection     = true

node_instance_type    = "m6i.large"
node_min_size         = 1
node_desired_size     = 2
node_max_size         = 3
node_root_volume_size = 80
node_spot_enabled     = false

cluster_kms_key_arn     = "arn:aws:kms:ap-east-1:815402439714:key/11111111-1111-1111-1111-111111111111"
cluster_oidc_thumbprint = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url = "https://oidc.eks.ap-east-1.amazonaws.com/id/DEVEXAMPLEOIDC"
enable_load_balancer_controller = false

efs_enabled         = true
efs_throughput_mode = "bursting"

backup_enabled            = true
backup_retention_days     = 14
backup_kms_key_arn        = "arn:aws:kms:ap-east-1:815402439714:key/22222222-2222-2222-2222-222222222222"
backup_service_role_arn   = "arn:aws:iam::815402439714:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days  = 14
vault_max_retention_days  = 120

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