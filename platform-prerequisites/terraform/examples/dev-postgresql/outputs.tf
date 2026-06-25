output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "PostgreSQL endpoint address."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "PostgreSQL endpoint port."
  value       = aws_db_instance.this.port
}

output "db_security_group_id" {
  description = "Security group attached to the database."
  value       = aws_security_group.db.id
}

output "db_subnet_group_name" {
  description = "DB subnet group used by the instance."
  value       = aws_db_subnet_group.this.name
}
