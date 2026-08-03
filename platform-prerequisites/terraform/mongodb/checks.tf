check "pbm_bucket_name_is_provided" {
  assert {
    condition     = length(var.pbm_bucket_name) > 0
    error_message = "pbm_bucket_name must be provided; this root's reusable module creates the bucket using this name."
  }
}

check "cluster_name_is_provided" {
  assert {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must be provided for the Pod Identity association."
  }
}

check "kms_key_arn_is_valid_when_provided" {
  assert {
    condition     = var.kms_key_arn == "" || startswith(var.kms_key_arn, "arn:aws:kms:")
    error_message = "kms_key_arn must be a valid KMS key ARN when provided, or empty to skip KMS access."
  }
}
