# MongoDB Terraform Configuration — Sandbox (Production account as temporary sandbox)
# Account: 632674123947 (Production account; UAT 672172129937 reserved for Phase 3+)
aws_region          = "us-east-1"
expected_account_id = "632674123947"
environment         = "sandbox"
name_prefix         = "oms-sandbox-mongodb"
# Dummy values from Phase 2 platform_contract (plan validation only)
pbm_bucket_name       = "oms-sandbox-eks-pbm-backup"
operator_iam_role_arn = "arn:aws:iam::632674123947:role/oms-sandbox-eks-mongodb-operator"
cluster_kms_key_arn   = "arn:aws:kms:us-east-1:632674123947:key/11111111-2222-3333-4444-555555555555"
tags = { Environment = "sandbox", Purpose = "Phase3-Validation", ManagedBy = "Terraform" }
