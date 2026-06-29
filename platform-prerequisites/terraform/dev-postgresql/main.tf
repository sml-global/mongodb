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

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for dev PostgreSQL"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_app_sg" {
  count = var.allowed_source_security_group_id == "" ? 0 : 1

  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_source_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow PostgreSQL from app security group"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.db.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "Allow PostgreSQL from approved CIDR"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.db_identifier
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

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

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.db_identifier}-writer"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = var.instance_class

  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = false
  monitoring_interval          = 0
  apply_immediately            = true

  # Aurora storage remains distributed; this pins the only instance placement.
  availability_zone = var.writer_availability_zone == "" ? null : var.writer_availability_zone

  tags = {
    Name        = "${var.db_identifier}-writer"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
