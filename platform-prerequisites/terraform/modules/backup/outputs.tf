output "backup_vault_name" {
  description = "AWS Backup vault name."
  value       = aws_backup_vault.this.name
}

output "backup_plan_id" {
  description = "AWS Backup plan identifier."
  value       = aws_backup_plan.this.id
}

output "vault_lock_metadata" {
  description = "Vault lock policy metadata represented as non-secret contract data."
  value = {
    min_retention_days = var.vault_min_retention_days
    max_retention_days = var.vault_max_retention_days
  }
}