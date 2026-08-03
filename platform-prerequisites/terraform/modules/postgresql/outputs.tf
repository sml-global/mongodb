output "cluster_identifier" {
  description = "Aurora cluster identifier, or null if no Aurora was provisioned (CNPG-only)."
  value       = length(var.database_subnet_ids) > 0 ? aws_rds_cluster.aurora[0].cluster_identifier : null
}

output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint, or null if no Aurora was provisioned (CNPG-only)."
  value       = length(var.database_subnet_ids) > 0 ? aws_rds_cluster.aurora[0].endpoint : null
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint, or null if no Aurora was provisioned (CNPG-only)."
  value       = length(var.database_subnet_ids) > 0 ? aws_rds_cluster.aurora[0].reader_endpoint : null
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the Aurora master password, or null if no Aurora was provisioned (CNPG-only)."
  value       = length(var.database_subnet_ids) > 0 ? aws_rds_cluster.aurora[0].master_user_secret[0].secret_arn : null
}

output "security_group_id" {
  description = "Aurora security group ID, or null if no Aurora was provisioned (CNPG-only)."
  value       = length(var.database_subnet_ids) > 0 ? aws_security_group.aurora[0].id : null
}
