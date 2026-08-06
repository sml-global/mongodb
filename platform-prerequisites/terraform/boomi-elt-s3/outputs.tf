output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.elt.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.elt.arn
}

output "bucket_region" {
  description = "S3 bucket region"
  value       = aws_s3_bucket.elt.region
}

output "iam_role_arn" {
  description = "IAM role ARN for this environment"
  value       = local.is_prod ? aws_iam_role.prod_admin[0].arn : aws_iam_role.cross_account[0].arn
}

output "iam_role_name" {
  description = "IAM role name for this environment"
  value       = local.is_prod ? aws_iam_role.prod_admin[0].name : aws_iam_role.cross_account[0].name
}

output "instance_profile_name" {
  description = "Instance profile name (prod only)"
  value       = local.is_prod ? aws_iam_instance_profile.prod_admin[0].name : null
}

output "external_id" {
  description = "External ID for AssumeRole (non-prod only)"
  value       = local.is_prod ? null : "boomi-elt-${var.environment}"
  sensitive   = true
}

output "cross_account_role_arns" {
  description = "ARNs of assumable roles in target accounts (prod only)"
  value = local.is_prod ? {
    uat = "arn:aws:iam::${var.uat_account_id}:role/sml-elt-cross-account-uat"
    dev = "arn:aws:iam::${var.dev_account_id}:role/sml-elt-cross-account-dev"
    sit = "arn:aws:iam::${var.sit_account_id}:role/sml-elt-cross-account-sit"
  } : null
}
