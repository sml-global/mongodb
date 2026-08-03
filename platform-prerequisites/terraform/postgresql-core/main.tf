# Attach CNPG backup S3 access policy to Phase 2 IRSA operator role
resource "aws_iam_role_policy" "cnpg_backup_access" {
  name = "${var.name_prefix}-cnpg-backup-access"
  role = element(split("/", var.postgresql_operator_iam_role_arn), length(split("/", var.postgresql_operator_iam_role_arn)) - 1)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.cnpg_backup_bucket_name}",
        "arn:aws:s3:::${var.cnpg_backup_bucket_name}/*"
      ]
      }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [var.cluster_kms_key_arn]
    }]
  })
}

# Aurora resources are provisioned by the shared modules/postgresql module,
# also invoked by the sibling postgresql-brand root — each root passes its
# own name_prefix/database name/instance count so a brand outage or destroy
# cannot touch core. See docs/guides/enterprise-architecture.md § Production
# Readiness Assessment — Now — "Aurora brand database" for the design
# rationale.
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
