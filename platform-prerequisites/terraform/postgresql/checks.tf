check "postgresql_operator_role_is_provided" {
  assert {
    condition     = length(var.postgresql_operator_iam_role_arn) > 0 && startswith(var.postgresql_operator_iam_role_arn, "arn:aws:iam::")
    error_message = "postgresql_operator_iam_role_arn must be a valid IAM role ARN from Phase 2 platform_contract. Direct IAM bypass is not allowed."
  }
}

check "cnpg_backup_bucket_is_provided" {
  assert {
    condition     = length(var.cnpg_backup_bucket_name) > 0
    error_message = "cnpg_backup_bucket_name must be provided from Phase 2 platform_contract."
  }
}

check "cluster_kms_key_is_valid_arn" {
  assert {
    condition     = startswith(var.cluster_kms_key_arn, "arn:aws:kms:")
    error_message = "cluster_kms_key_arn must be a valid KMS key ARN."
  }
}
