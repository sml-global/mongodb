# Attach PBM S3 access policy to Phase 2 IRSA operator role
resource "aws_iam_role_policy" "pbm_s3_access" {
  name = "${var.name_prefix}-pbm-s3-access"
  role = element(split("/", var.operator_iam_role_arn), length(split("/", var.operator_iam_role_arn)) - 1)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.pbm_bucket_name}",
        "arn:aws:s3:::${var.pbm_bucket_name}/*"
      ]
      }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [var.cluster_kms_key_arn]
    }]
  })
}

check "operator_role_is_provided" {
  assert {
    condition     = length(var.operator_iam_role_arn) > 0
    error_message = "operator_iam_role_arn must be provided from Phase 2 platform_contract. Direct IAM bypass is not allowed."
  }
}

check "pbm_bucket_is_provided" {
  assert {
    condition     = length(var.pbm_bucket_name) > 0
    error_message = "pbm_bucket_name must be provided from Phase 2 platform_contract."
  }
}
