check "cluster_kms_key_is_valid_arn_when_provided" {
  assert {
    condition     = var.cluster_kms_key_arn == "" || startswith(var.cluster_kms_key_arn, "arn:aws:kms:")
    error_message = "cluster_kms_key_arn must be a valid KMS key ARN when provided."
  }
}

check "database_subnet_ids_require_kms_key" {
  assert {
    condition     = length(var.database_subnet_ids) == 0 || length(var.cluster_kms_key_arn) > 0
    error_message = "cluster_kms_key_arn must be provided whenever database_subnet_ids is non-empty (Aurora storage encryption is mandatory)."
  }
}
