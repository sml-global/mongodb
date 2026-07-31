output "platform_contract" {
  description = "Non-secret platform contract consumed by downstream automation."
  value = {
    environment            = var.environment
    region                 = var.aws_region
    account_id             = var.expected_account_id
    vpc_id                 = module.network.vpc_id
    vpc_cidr               = module.network.vpc_cidr
    private_subnet_ids     = module.network.private_subnet_ids
    public_subnet_ids      = module.network.public_subnet_ids
    database_subnet_ids    = module.network.database_subnet_ids
    cluster_name           = module.eks.cluster_name
    cluster_arn            = module.eks.cluster_arn
    cluster_endpoint       = module.eks.cluster_endpoint
    node_group_name        = module.eks.node_group_name
    enabled_addon_versions = module.eks.enabled_addon_versions
    iam_roles = {
      cluster            = module.iam.cluster_role_arn
      node               = module.iam.node_role_arn
      addon              = module.iam.addon_role_arn
      autoscaler         = module.iam.autoscaler_role_arn
      cluster_autoscaler = module.iam.cluster_autoscaler_role_arn
      load_balancer      = module.iam.lbc_role_arn
      oidc_provider      = module.iam.oidc_provider_arn
    }
    efs = var.efs_enabled ? {
      file_system_id    = module.efs[0].file_system_id
      security_group_id = module.efs[0].security_group_id
    } : null
    backup = var.backup_enabled ? {
      backup_vault_name   = module.backup[0].backup_vault_name
      backup_plan_id      = module.backup[0].backup_plan_id
      vault_lock_metadata = module.backup[0].vault_lock_metadata
    } : null
  }
}