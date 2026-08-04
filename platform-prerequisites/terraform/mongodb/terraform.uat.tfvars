aws_region          = "ap-east-1"
expected_account_id = "672172129937"
environment         = "uat"
name_prefix         = "oms-uat"
cluster_name        = "oms-uat-eks-cluster"
pbm_bucket_name     = "sml-oms-uat-mongodb-pbm-672172129937"

mongodb_namespace                     = "mongodb-uat"
mongodb_workload_service_account_name = "psmdb-db"
iam_role_name                         = "oms-uat-mongodb-pbm-role"

# Keep true for EKS Pod Identity.
use_pod_identity = true

# Only needed for IRSA mode (when use_pod_identity=false).
oidc_provider_arn = ""
oidc_provider_url = ""

# Optional, only if KMS key access is required.
kms_key_arn = ""
