# Brand CNPG (dev/SIT self-managed PostgreSQL) prerequisites: namespace,
# S3 backup bucket, and IAM pod-identity role, provisioned via the shared
# cnpg-prereqs module. This is a distinct root from postgresql-brand (which
# provisions Aurora for UAT/Prod) — this root exists so the brand CNPG
# cluster's namespace, bucket, and IAM role can be provisioned, resized, or
# destroyed independently of the core CNPG cluster (postgresql-coredb).
module "cnpg_prereqs" {
  source = "../modules/cnpg-prereqs"

  cluster_name                  = var.cluster_name
  namespace                     = var.namespace
  workload_service_account_name = var.workload_service_account_name
  backup_bucket_name            = var.backup_bucket_name
  iam_role_name                 = var.iam_role_name
  use_pod_identity              = var.use_pod_identity
  oidc_provider_arn             = var.oidc_provider_arn
  oidc_provider_url             = var.oidc_provider_url
  kms_key_arn                   = var.kms_key_arn
}
