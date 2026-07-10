output "mongodb_namespace" {
  value = kubernetes_namespace_v1.mongodb.metadata[0].name
}

output "pbm_bucket_name" {
  value = aws_s3_bucket.pbm.bucket
}

output "operator_iam_role_arn" {
  value = aws_iam_role.mongodb_pbm.arn
}

output "mongodb_workload_service_account" {
  value = kubernetes_service_account_v1.mongodb_workload.metadata[0].name
}