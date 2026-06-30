output "mongodb_namespace" {
  value = module.mongodb_prerequisites.mongodb_namespace
}

output "pbm_bucket_name" {
  value = module.mongodb_prerequisites.pbm_bucket_name
}

output "operator_iam_role_arn" {
  value = module.mongodb_prerequisites.operator_iam_role_arn
}

output "mongodb_workload_service_account" {
  value = module.mongodb_prerequisites.mongodb_workload_service_account
}
