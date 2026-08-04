resource "aws_kms_key" "cluster" {
  description             = "${var.name_prefix} EKS cluster secrets envelope encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "cluster" {
  name          = "alias/${var.name_prefix}-eks-cluster"
  target_key_id = aws_kms_key.cluster.key_id
}

resource "aws_kms_key" "backup" {
  description             = "${var.name_prefix} AWS Backup vault encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.name_prefix}-backup-vault"
  target_key_id = aws_kms_key.backup.key_id
}
