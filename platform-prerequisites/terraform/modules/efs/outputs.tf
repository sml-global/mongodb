output "file_system_id" {
  description = "EFS file system ID."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "EFS file system ARN."
  value       = aws_efs_file_system.this.arn
}

output "security_group_id" {
  description = "Security group protecting EFS mount targets."
  value       = aws_security_group.efs.id
}