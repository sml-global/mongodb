aws_region           = "ap-east-1"
expected_account_id  = "815402439714"
environment          = "dev"
name_prefix          = "oms-dev-eks"

vpc_cidr             = "10.200.208.0/21"
availability_zones   = ["ap-east-1a", "ap-east-1b"]
private_subnet_cidrs = ["10.200.208.0/23", "10.200.210.0/23"]
public_subnet_cidrs  = ["10.200.212.0/26", "10.200.212.64/26"]
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

cluster_oidc_thumbprint = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url = "https://oidc.eks.ap-east-1.amazonaws.com/id/DEVEXAMPLEOIDC"
enable_load_balancer_controller = false

efs_enabled         = true
efs_throughput_mode = "bursting"

backup_enabled            = true
backup_retention_days     = 14
backup_service_role_arn   = "arn:aws:iam::815402439714:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days  = 14
vault_max_retention_days  = 120

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