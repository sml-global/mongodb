output "pbm_policy_id" {
  description = "ID of the PBM S3 access policy (format: role_name:policy_name) attached to the Phase 2 operator role"
  value       = aws_iam_role_policy.pbm_s3_access.id
}
