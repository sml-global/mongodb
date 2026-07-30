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

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora"
  subnet_ids = var.database_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "aurora" {
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
  cluster_identifier          = "${var.name_prefix}-aurora"
  engine                      = "aurora-postgresql"
  engine_version              = var.aurora_engine_version
  database_name               = var.aurora_database_name
  master_username             = var.aurora_master_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.aurora.name
  vpc_security_group_ids      = [aws_security_group.aurora.id]
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
  count              = var.aurora_instance_count
  identifier         = "${var.name_prefix}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = var.tags
}
