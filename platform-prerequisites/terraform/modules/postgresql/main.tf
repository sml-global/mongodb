# Reusable Aurora PostgreSQL module — invoked by the postgresql-core and
# postgresql-brand Terraform roots, each with its own name_prefix/database
# name/instance count, so a brand outage/misconfiguration/destroy cannot
# touch core (see docs/guides/enterprise-architecture.md § Production
# Readiness Assessment — Now — "Aurora brand database").
#
# All resources are count-gated on database_subnet_ids being non-empty, so
# CNPG-only environments (dev/sit) that invoke a root without Aurora
# variables set simply provision nothing here.

resource "aws_db_subnet_group" "aurora" {
  count      = length(var.database_subnet_ids) > 0 ? 1 : 0
  name       = "${var.name_prefix}-aurora"
  subnet_ids = var.database_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "aurora" {
  count       = length(var.database_subnet_ids) > 0 ? 1 : 0
  name_prefix = "${var.name_prefix}-aurora-"
  description = "Restricts PostgreSQL traffic to the approved workload security group only."
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_source_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_rds_cluster" "aurora" {
  count                       = length(var.database_subnet_ids) > 0 ? 1 : 0
  cluster_identifier          = "${var.name_prefix}-aurora"
  engine                      = "aurora-postgresql"
  engine_version              = var.aurora_engine_version
  database_name               = var.aurora_database_name
  master_username             = var.aurora_master_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.aurora[0].name
  vpc_security_group_ids      = [aws_security_group.aurora[0].id]
  storage_encrypted           = true
  kms_key_id                  = var.cluster_kms_key_arn
  backup_retention_period     = 7
  preferred_backup_window     = "03:00-04:00"
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.name_prefix}-aurora-final"
  deletion_protection         = true

  tags = var.tags
}

resource "aws_rds_cluster_instance" "aurora" {
  count              = length(var.database_subnet_ids) > 0 ? var.aurora_instance_count : 0
  identifier         = "${var.name_prefix}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora[0].id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora[0].engine
  engine_version     = aws_rds_cluster.aurora[0].engine_version

  tags = var.tags
}
