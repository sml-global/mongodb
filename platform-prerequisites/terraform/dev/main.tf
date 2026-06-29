terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.26"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "target" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target.token
}

module "mongodb_prerequisites" {
  source = "../reusable"

  cluster_name                         = var.cluster_name
  mongodb_namespace                    = var.mongodb_namespace
  mongodb_workload_service_account_name = var.mongodb_workload_service_account_name
  pbm_bucket_name                      = var.pbm_bucket_name
  iam_role_name                        = var.iam_role_name
  use_pod_identity                     = var.use_pod_identity
  oidc_provider_arn                    = var.oidc_provider_arn
  oidc_provider_url                    = var.oidc_provider_url
  kms_key_arn                          = var.kms_key_arn
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
