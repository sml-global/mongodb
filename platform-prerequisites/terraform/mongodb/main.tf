# MongoDB prerequisites: namespace, PBM S3 bucket, and IAM pod-identity role,
# provisioned via the shared reusable module (see
# platform-prerequisites/terraform/reusable/main.tf). This root previously
# assumed these already existed from an external "Phase 2 platform_contract"
# source; no such source ever ran, so nothing created them. Embedding the
# module here is what this root's own README has always documented.
module "mongodb_prerequisites" {
  source = "../reusable"

  cluster_name                          = var.cluster_name
  mongodb_namespace                     = var.mongodb_namespace
  mongodb_workload_service_account_name = var.mongodb_workload_service_account_name
  pbm_bucket_name                       = var.pbm_bucket_name
  iam_role_name                         = var.iam_role_name
  use_pod_identity                      = var.use_pod_identity
  oidc_provider_arn                     = var.oidc_provider_arn
  oidc_provider_url                     = var.oidc_provider_url
  kms_key_arn                           = var.kms_key_arn
}

# Attach PBM S3 access policy to the operator role created above.
resource "aws_iam_role_policy" "pbm_s3_access" {
  name = "${var.name_prefix}-pbm-s3-access"
  role = element(split("/", module.mongodb_prerequisites.operator_iam_role_arn), length(split("/", module.mongodb_prerequisites.operator_iam_role_arn)) - 1)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.pbm_bucket_name}",
          "arn:aws:s3:::${var.pbm_bucket_name}/*"
        ]
      }],
      var.kms_key_arn != "" ? [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.kms_key_arn]
      }] : []
    )
  })
}
