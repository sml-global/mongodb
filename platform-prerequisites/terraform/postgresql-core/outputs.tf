output "cnpg_backup_policy_id" {
  description = "ID of the CNPG backup S3 access policy (format: role_name:policy_name) attached to the Phase 2 operator role"
  value       = aws_iam_role_policy.cnpg_backup_access.id
}
