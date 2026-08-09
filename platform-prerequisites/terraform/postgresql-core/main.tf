# Aurora resources are provisioned by the shared modules/postgresql module,
# also invoked by the sibling postgresql-brand root — each root passes its
# own name_prefix/database name/instance count so a brand outage or destroy
# cannot touch core. See docs/guides/enterprise-architecture.md § Production
# Readiness Assessment — Now — "Aurora brand database" for the design
# rationale.
#
# Aurora's own native backup mechanism (backup_retention_period,
# preferred_backup_window in modules/postgresql) is fully AWS-managed and
# needs no S3 bucket or IAM role of its own -- unlike self-managed CNPG
# (dev/SIT), which does need an operator IRSA role and S3 WAL-archive bucket
# via modules/cnpg-prereqs (see postgresql-coredb/postgresql-branddb). This
# root previously carried a CNPG-shaped IAM policy resource here that was
# never actually usable for Aurora (see issue #100) -- removed.
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
