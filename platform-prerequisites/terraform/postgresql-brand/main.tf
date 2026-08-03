# Brand Aurora database — independent sibling of postgresql-core, invoking
# the same shared module so a brand outage/misconfiguration/destroy cannot
# touch core. See docs/guides/enterprise-architecture.md § Production
# Readiness Assessment — Now — "Aurora brand database" for the design
# rationale (state-key convention for this split already existed in
# config/environments/*.env before this root did:
# POSTGRESQL_BRAND_STATE_KEY).
#
# Unlike postgresql-core, this root has no CNPG operator IAM policy — brand
# is a plain Aurora database with no in-cluster CNPG Cluster CR pointed at
# it (yet). If a brand-specific operator/workload identity is needed later,
# add it here following postgresql-core/main.tf's cnpg_backup_access pattern.

module "postgresql" {
  source = "../modules/postgresql"

  name_prefix                      = var.name_prefix
  vpc_id                           = var.vpc_id
  database_subnet_ids              = var.database_subnet_ids
  allowed_source_security_group_id = var.allowed_source_security_group_id
  aurora_engine_version            = var.aurora_engine_version
  aurora_instance_class            = var.aurora_instance_class
  aurora_instance_count            = var.aurora_instance_count
  aurora_database_name             = var.aurora_database_name
  aurora_master_username           = var.aurora_master_username
  cluster_kms_key_arn              = var.cluster_kms_key_arn
  tags                             = var.tags
}
