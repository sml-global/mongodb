output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "backup_bucket_name" {
  value = aws_s3_bucket.backup.bucket
}

output "operator_iam_role_arn" {
  value = aws_iam_role.workload.arn
}

output "workload_service_account" {
  value = kubernetes_service_account_v1.workload.metadata[0].name
}
