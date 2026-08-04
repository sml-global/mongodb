output "cluster_kms_key_arn" {
  description = "KMS key ARN for EKS cluster secrets encryption."
  value       = aws_kms_key.cluster.arn
}

output "backup_kms_key_arn" {
  description = "KMS key ARN for AWS Backup vault encryption."
  value       = aws_kms_key.backup.arn
}
