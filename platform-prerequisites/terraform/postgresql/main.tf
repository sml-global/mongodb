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
