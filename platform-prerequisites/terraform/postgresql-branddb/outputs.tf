output "namespace" {
  description = "Kubernetes namespace created for the brand CNPG cluster."
  value       = module.cnpg_prereqs.namespace
}

output "backup_bucket_name" {
  description = "S3 bucket name created for the brand cluster's WAL archival and backups."
  value       = module.cnpg_prereqs.backup_bucket_name
}

output "operator_iam_role_arn" {
  description = "IAM role ARN created for the brand CNPG workload's backup access."
  value       = module.cnpg_prereqs.operator_iam_role_arn
}

output "workload_service_account" {
  description = "ServiceAccount created for the brand CNPG workload pods."
  value       = module.cnpg_prereqs.workload_service_account
}
