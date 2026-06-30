output "postgresql_cluster_id" {
  description = "Aurora PostgreSQL cluster identifier."
  value       = aws_rds_cluster.postgresql.id
}

output "postgresql_endpoint" {
  description = "Aurora PostgreSQL writer endpoint address."
  value       = aws_rds_cluster.postgresql.endpoint
}

output "postgresql_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint address."
  value       = aws_rds_cluster.postgresql.reader_endpoint
}

output "postgresql_port" {
  description = "PostgreSQL endpoint port."
  value       = aws_rds_cluster.postgresql.port
}

output "postgresql_security_group_id" {
  description = "Security group attached to PostgreSQL."
  value       = aws_security_group.postgresql.id
}

output "postgresql_subnet_group_name" {
  description = "DB subnet group used by PostgreSQL cluster."
  value       = aws_db_subnet_group.postgresql.name
}
