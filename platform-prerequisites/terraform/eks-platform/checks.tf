check "eks_endpoint_access_matches_boomi_precedent" {
  assert {
    condition     = var.endpoint_public_access && !var.endpoint_private_access
    error_message = "endpoint_public_access must be true and endpoint_private_access must be false, matching the live Boomi dev cluster's proven access pattern (../boomi-infra/terraform/eks.tf, infra/tf/modules/eks/main.tf)."
  }
}

check "eks_authentication_mode_api_only" {
  assert {
    condition     = var.authentication_mode == "API"
    error_message = "authentication_mode must be API for this platform stack."
  }
}

check "eks_deletion_protection_required" {
  assert {
    condition     = var.deletion_protection
    error_message = "deletion_protection must be true for this platform stack."
  }
}

check "node_scaling_order_and_bounds" {
  assert {
    condition = (
      var.node_min_size >= 1 &&
      var.node_min_size <= var.node_desired_size &&
      var.node_desired_size <= var.node_max_size &&
      var.node_max_size <= 20
    )
    error_message = "node sizes must satisfy 1 <= min <= desired <= max <= 20."
  }
}

check "node_root_volume_floor" {
  assert {
    condition     = var.node_root_volume_size >= 20
    error_message = "node_root_volume_size must be at least 20 GiB."
  }
}

check "vault_lock_bounds" {
  assert {
    condition     = var.vault_min_retention_days <= var.vault_max_retention_days
    error_message = "vault_min_retention_days must be <= vault_max_retention_days."
  }
}

check "uat_backup_retention_floor" {
  assert {
    condition     = var.environment != "uat" || var.backup_retention_days >= 35
    error_message = "UAT backup retention must be >= 35 days."
  }
}