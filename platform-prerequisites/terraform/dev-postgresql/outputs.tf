output "db_cluster_id" {
  description = "Aurora cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "db_endpoint" {
  description = "Aurora writer endpoint address."
  value       = aws_rds_cluster.this.endpoint
}

output "db_reader_endpoint" {
  description = "Aurora reader endpoint address."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "db_port" {
  description = "PostgreSQL endpoint port."
  value       = aws_rds_cluster.this.port
}

output "db_security_group_id" {
  description = "Security group attached to the database."
  value       = aws_security_group.db.id
}

output "db_subnet_group_name" {
  description = "DB subnet group used by the cluster."
  value       = aws_db_subnet_group.this.name
}
