output "namespace" {
  description = "Kubernetes namespace created for the core CNPG cluster."
  value       = module.cnpg_prereqs.namespace
}

output "backup_bucket_name" {
  description = "S3 bucket name created for the core cluster's WAL archival and backups."
  value       = module.cnpg_prereqs.backup_bucket_name
}

output "operator_iam_role_arn" {
  description = "IAM role ARN created for the core CNPG workload's backup access."
  value       = module.cnpg_prereqs.operator_iam_role_arn
}

output "workload_service_account" {
  description = "ServiceAccount created for the core CNPG workload pods."
  value       = module.cnpg_prereqs.workload_service_account
}
