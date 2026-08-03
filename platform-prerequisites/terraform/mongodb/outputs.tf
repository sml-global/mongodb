output "pbm_policy_id" {
  description = "ID of the PBM S3 access policy (format: role_name:policy_name) attached to the operator role"
  value       = aws_iam_role_policy.pbm_s3_access.id
}

output "mongodb_namespace" {
  description = "Kubernetes namespace created for MongoDB, from the reusable module."
  value       = module.mongodb_prerequisites.mongodb_namespace
}

output "pbm_bucket_name" {
  description = "S3 bucket name created for PBM backups, from the reusable module."
  value       = module.mongodb_prerequisites.pbm_bucket_name
}

output "operator_iam_role_arn" {
  description = "IAM role ARN created for the MongoDB workload/PBM sidecar, from the reusable module."
  value       = module.mongodb_prerequisites.operator_iam_role_arn
}
