terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.name_prefix}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-subnet-group"
  }
}

resource "aws_security_group" "postgresql" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for dev PostgreSQL"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_app_sg" {
  count = var.allowed_source_security_group_id == "" ? 0 : 1

  security_group_id            = aws_security_group.postgresql.id
  referenced_security_group_id = var.allowed_source_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow PostgreSQL from app security group"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.postgresql.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "Allow PostgreSQL from approved CIDR"
}

resource "aws_vpc_security_group_egress_rule" "postgresql_all_outbound" {
  security_group_id = aws_security_group.postgresql.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}

resource "aws_rds_cluster" "postgresql" {
  cluster_identifier = var.db_identifier
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  backup_retention_period         = 1
  copy_tags_to_snapshot           = true
  deletion_protection             = false
  skip_final_snapshot             = true
  storage_encrypted               = true
  apply_immediately               = true
  enabled_cloudwatch_logs_exports = []

  tags = {
    Name        = var.db_identifier
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_rds_cluster_instance" "postgresql_writer" {
  identifier         = "${var.db_identifier}-writer"
  cluster_identifier = aws_rds_cluster.postgresql.id
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
  instance_class     = var.instance_class

  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = false
  monitoring_interval          = 0
  apply_immediately            = true

  availability_zone = var.writer_availability_zone == "" ? null : var.writer_availability_zone

  tags = {
    Name        = "${var.db_identifier}-writer"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# ─── CloudWatch metrics monitoring (read-only) ──────────────────────────────
# Grants a Kubernetes pod (via EKS Pod Identity) least-privilege, read-only
# access to CloudWatch metrics so Aurora/RDS metrics (CPU, IOPS, connections,
# replication lag) can be scraped and forwarded into SigNoz, without exposing
# any database credentials or write access to AWS resources.
data "aws_iam_policy_document" "postgres_cloudwatch_monitor_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "postgres_cloudwatch_monitor" {
  name               = var.cloudwatch_monitor_role_name
  assume_role_policy = data.aws_iam_policy_document.postgres_cloudwatch_monitor_assume_role.json
}

data "aws_iam_policy_document" "postgres_cloudwatch_monitor" {
  statement {
    sid    = "CloudWatchMetricsReadOnly"
    effect = "Allow"
    actions = [
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
    ]
    # CloudWatch metric-read actions do not support resource-level restriction.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "postgres_cloudwatch_monitor" {
  name   = "${var.cloudwatch_monitor_role_name}-policy"
  role   = aws_iam_role.postgres_cloudwatch_monitor.id
  policy = data.aws_iam_policy_document.postgres_cloudwatch_monitor.json
}

resource "aws_eks_pod_identity_association" "postgres_cloudwatch_monitor" {
  cluster_name    = var.eks_cluster_name
  namespace       = var.cloudwatch_monitor_namespace
  service_account = var.cloudwatch_monitor_service_account_name
  role_arn        = aws_iam_role.postgres_cloudwatch_monitor.arn
}
