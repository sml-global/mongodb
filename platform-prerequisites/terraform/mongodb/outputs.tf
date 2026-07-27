output "pbm_policy_arn" {
  description = "ARN of the PBM S3 access policy attached to the Phase 2 operator role"
  value       = aws_iam_role_policy.pbm_s3_access.id
}
