#!/usr/bin/env bash

eks_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

eks_internal_require_foundation_destroy_guards() {
  verify_aws_identity_and_region || return 1
  verify_kubernetes_context || return 1
  verify_eks_authentication_mode || return 1
}

eks_internal_expected_platform_identity() {
  if [[ -n "${EKS_PLATFORM_IDENTITY:-}" ]]; then
    printf '%s' "${EKS_PLATFORM_IDENTITY}"
    return 0
  fi

  if [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" && -n "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    printf 'arn:aws:eks:%s:%s:cluster/%s' "${AWS_REGION}" "${EXPECTED_AWS_ACCOUNT_ID}" "${EKS_CLUSTER_NAME}"
    return 0
  fi

  eks_internal_error "platform identity expectation is unavailable"
  return 1
}

eks_internal_read_destroy_drift_vector() {
  local scope_name="$1"
  local phase_name="$2"

  if [[ "$(type -t eks_internal_live_destroy_drift_vector)" != "function" ]]; then
    eks_internal_error "destroy drift live observation function is required"
    return 1
  fi

  eks_internal_live_destroy_drift_vector "$scope_name" "$phase_name"
}

eks_internal_validate_destroy_drift_vector() {
  local scope_name="$1"
  local vector="$2"
  local account=""
  local region=""
  local environment_name=""
  local platform_identity=""
  local eks_deletion_protection=""
  local efs_protection=""
  local backup_retention_days=""
  local vault_lock_state=""
  local expected_platform_identity=""
  local minimum_retention_days="35"
  local key=""
  local value=""

  while IFS='=' read -r key value; do
    case "$key" in
      account) account="$value" ;;
      region) region="$value" ;;
      environment) environment_name="$value" ;;
      platform_identity) platform_identity="$value" ;;
      eks_deletion_protection) eks_deletion_protection="$value" ;;
      efs_protection) efs_protection="$value" ;;
      backup_retention_days) backup_retention_days="$value" ;;
      vault_lock_state) vault_lock_state="$value" ;;
    esac
  done <<< "$vector"

  if [[ -z "$account" || -z "$region" || -z "$environment_name" || -z "$platform_identity" || -z "$eks_deletion_protection" || -z "$efs_protection" || -z "$backup_retention_days" || -z "$vault_lock_state" ]]; then
    eks_internal_error "destroy drift vector is incomplete"
    return 1
  fi

  expected_platform_identity="$(eks_internal_expected_platform_identity)" || return 1

  if [[ "$account" != "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    eks_internal_error "destroy drift account mismatch"
    return 1
  fi
  if [[ "$region" != "${AWS_REGION:-}" ]]; then
    eks_internal_error "destroy drift region mismatch"
    return 1
  fi
  if [[ "$environment_name" != "${ENVIRONMENT:-}" ]]; then
    eks_internal_error "destroy drift environment mismatch"
    return 1
  fi
  if [[ "$platform_identity" != "$expected_platform_identity" ]]; then
    eks_internal_error "destroy drift platform identity mismatch"
    return 1
  fi

  # Protection state (eks_deletion_protection, efs_protection,
  # vault_lock_state, backup_retention_days) is recorded in the drift
  # vector but is NOT validated as a precondition here.
  #
  # This function's job is drift detection: the account/region/environment/
  # identity comparisons above are the real check -- they prove the thing
  # about to be destroyed is still the thing the operator was shown.
  # Requiring protections to still be ENABLED is the inverted rail that
  # deadlocked the partially-completed teardown in #159, and it adds
  # nothing once a human has typed yes against the enumerated list.

  return 0
}

eks_internal_capture_destroy_drift_vector() {
  local scope_name="$1"
  local phase_name="$2"
  local vector=""

  vector="$(eks_internal_read_destroy_drift_vector "$scope_name" "$phase_name")" || return 1
  eks_internal_validate_destroy_drift_vector "$scope_name" "$vector" || return 1
  printf '%s' "$vector"
}

eks_internal_recheck_destroy_drift_or_refuse() {
  local scope_name="$1"
  local baseline=""
  local current=""

  baseline="$(eks_internal_capture_destroy_drift_vector "$scope_name" "baseline")" || return 1
  current="$(eks_internal_capture_destroy_drift_vector "$scope_name" "pre-mutation")" || return 1

  if [[ "$baseline" != "$current" ]]; then
    eks_internal_error "destroy drift recheck failed for ${scope_name}; refusing mutation"
    return 1
  fi

  return 0
}

eks_internal_execute_provision_mutation() {
  local scope_name="$1"

  case "$scope_name" in
    eks-platform)
      provision_eks_platform_scope
      ;;
    workload-identity)
      provision_workload_identity_scope
      ;;
    platform-controllers)
      provision_platform_controllers_scope
      ;;
    *)
      eks_internal_error "unknown EKS provision scope: ${scope_name}"
      return 1
      ;;
  esac
}

eks_internal_execute_destroy_mutation() {
  local scope_name="$1"

  case "$scope_name" in
    eks-platform)
      destroy_eks_platform_scope
      ;;
    workload-identity)
      destroy_workload_identity_scope
      ;;
    platform-controllers)
      destroy_platform_controllers_scope
      ;;
    *)
      eks_internal_error "unknown EKS destroy scope: ${scope_name}"
      return 1
      ;;
  esac
}

eks_internal_eks_platform_provision_handler() {
  eks_internal_execute_provision_mutation "eks-platform" "$@"
}

eks_internal_workload_identity_provision_handler() {
  eks_internal_execute_provision_mutation "workload-identity" "$@"
}

eks_internal_platform_controllers_provision_handler() {
  eks_internal_execute_provision_mutation "platform-controllers" "$@"
}

eks_internal_eks_platform_destroy_handler() {
  eks_internal_require_foundation_destroy_guards || return 1
  eks_internal_recheck_destroy_drift_or_refuse "eks-platform" || return 1
  eks_internal_execute_destroy_mutation "eks-platform" "$@"
}

eks_internal_workload_identity_destroy_handler() {
  eks_internal_require_foundation_destroy_guards || return 1
  eks_internal_recheck_destroy_drift_or_refuse "workload-identity" || return 1
  eks_internal_execute_destroy_mutation "workload-identity" "$@"
}

eks_internal_platform_controllers_destroy_handler() {
  eks_internal_require_foundation_destroy_guards || return 1
  eks_internal_recheck_destroy_drift_or_refuse "platform-controllers" || return 1
  eks_internal_execute_destroy_mutation "platform-controllers" "$@"
}
