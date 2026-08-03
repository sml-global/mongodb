output "cnpg_backup_policy_id" {
  description = "ID of the CNPG backup S3 access policy (format: role_name:policy_name) attached to the Phase 2 operator role"
  value       = aws_iam_role_policy.cnpg_backup_access.id
}

output "cluster_identifier" {
  description = "Aurora cluster identifier, or null if no Aurora was provisioned (CNPG-only)."
  value       = module.postgresql.cluster_identifier
}

output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint, or null if no Aurora was provisioned (CNPG-only)."
  value       = module.postgresql.cluster_endpoint
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the Aurora master password, or null if no Aurora was provisioned (CNPG-only)."
  value       = module.postgresql.master_user_secret_arn
}
