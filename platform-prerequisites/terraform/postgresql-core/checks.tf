check "cluster_kms_key_is_valid_arn" {
  assert {
    condition     = startswith(var.cluster_kms_key_arn, "arn:aws:kms:")
    error_message = "cluster_kms_key_arn must be a valid KMS key ARN."
  }
}
