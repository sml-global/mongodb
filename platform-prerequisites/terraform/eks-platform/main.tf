module "network" {
  source = "../modules/network"

  name_prefix           = var.name_prefix
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  private_subnet_cidrs  = var.private_subnet_cidrs
  public_subnet_cidrs   = var.public_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  nat_gateway_count     = var.nat_gateway_count
  nat_mode              = var.nat_mode
}

module "eks" {
  source = "../modules/eks"

  name_prefix             = var.name_prefix
  kubernetes_version      = var.kubernetes_version
  authentication_mode     = var.authentication_mode
  endpoint_public_access  = var.endpoint_public_access
  endpoint_private_access = var.endpoint_private_access
  deletion_protection     = var.deletion_protection

  cluster_role_arn      = module.iam.cluster_role_arn
  node_role_arn         = module.iam.node_role_arn
  addon_role_arn        = module.iam.addon_role_arn
  private_subnet_ids    = module.network.private_subnet_ids
  node_instance_type    = var.node_instance_type
  node_min_size         = var.node_min_size
  node_desired_size     = var.node_desired_size
  node_max_size         = var.node_max_size
  node_root_volume_size = var.node_root_volume_size
  node_spot_enabled     = var.node_spot_enabled
  cluster_kms_key_arn   = var.cluster_kms_key_arn
  addons                = var.addons

  depends_on = [module.network]
}

module "iam" {
  source = "../modules/iam"

  name_prefix                     = var.name_prefix
  cluster_oidc_issuer_url         = var.cluster_oidc_issuer_url
  cluster_oidc_thumbprint         = var.cluster_oidc_thumbprint
  node_group_name                 = "${var.name_prefix}-primary"
  enable_load_balancer_controller = var.enable_load_balancer_controller
}

module "efs" {
  count  = var.efs_enabled ? 1 : 0
  source = "../modules/efs"

  name_prefix        = var.name_prefix
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  throughput_mode    = var.efs_throughput_mode

  depends_on = [module.network]
}

module "backup" {
  count  = var.backup_enabled ? 1 : 0
  source = "../modules/backup"

  name_prefix              = var.name_prefix
  deployment_environment   = var.environment
  backup_retention_days    = var.backup_retention_days
  backup_kms_key_arn       = var.backup_kms_key_arn
  backup_service_role_arn  = var.backup_service_role_arn
  vault_min_retention_days = var.vault_min_retention_days
  vault_max_retention_days = var.vault_max_retention_days
  backup_target_resource_arns = compact([
    module.eks.cluster_arn,
    try(module.efs[0].file_system_arn, null),
  ])
}