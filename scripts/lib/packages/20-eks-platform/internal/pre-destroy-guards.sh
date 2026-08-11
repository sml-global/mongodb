#!/usr/bin/env bash
#
# EKS platform pre-destroy guard implementation.
#
# Owned by "Task 7: Define Canonical Component-Verifier Wrappers" in
# docs/superpowers/plans/2026-07-22-phase2-eks-platform.md.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "20-eks-platform/internal/pre-destroy-guards.sh"
#
# Exports only distinct guard-side eks_internal_*_pre_destroy_guard symbols.
# Never defines lifecycle, handler, verifier, or canonical registry wrapper
# symbols. Does not source verifiers.sh.
#
# Live platform observations are obtained exclusively through the
# eks_internal_live_guard_observations <scope> seam, which must be defined
# externally before any guard function is called (same pattern as
# eks_internal_live_destroy_drift_vector in lifecycle-handlers.sh).
#
# Each guard:
#   1. Reads observations from the seam
#   2. Validates protection state and dependent-scope absence
#   3. Derives canonical resource identity from the validated platform_contract
#      (in-memory env vars; never from live AWS lookup or evidence artifact)
#   4. Computes a deterministic SHA-256 digest over the canonical observations
#   5. Chooses a foundation-defined closed summary code
#   6. Invokes record_pre_destroy_guard_result EXACTLY ONCE
#   7. Returns 0 for PASS, non-zero for FAIL
#
# Guards never create, read, touch, or access the durable evidence artifact.
# Guards never write files, initialize orchestration state, or call mutation
# APIs.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

# ---------------------------------------------------------------------------
# eks-platform pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: cluster ARN (e.g. arn:aws:eks:ap-east-1:672172129937:cluster/...)
# Dependents that must be absent: workload-identity, platform-controllers
# Protection checks: EKS deletion protection, EFS prevent_destroy,
#   backup retention >= 35 days, vault lock state

eks_internal_eks_platform_pre_destroy_guard() {
  local scope="eks-platform"
  local guard_status="PASS"
  local summary_code="EKS_PLATFORM_GUARD_PASS"
  local observations=""
  local cluster_arn="eks-platform:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t eks_internal_live_guard_observations)" != "function" ]]; then
    printf 'ERROR: %s\n' "eks-platform: eks_internal_live_guard_observations seam is required" >&2
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(eks_internal_live_guard_observations "$scope")" || {
      printf 'ERROR: %s\n' "eks-platform: failed to read live guard observations" >&2
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local workload_identity_absent=""
    local platform_controllers_absent=""
    local eks_deletion_protection=""
    local efs_protection=""
    local backup_retention_days=""
    local vault_lock_state=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        workload_identity_absent)    workload_identity_absent="$obs_val" ;;
        platform_controllers_absent) platform_controllers_absent="$obs_val" ;;
        eks_deletion_protection)     eks_deletion_protection="$obs_val" ;;
        efs_protection)              efs_protection="$obs_val" ;;
        backup_retention_days)       backup_retention_days="$obs_val" ;;
        vault_lock_state)            vault_lock_state="$obs_val" ;;
      esac
    done <<< "$observations"

    # Dependent-absence checks
    case "$workload_identity_absent" in
      true) ;;
      *)
        printf 'ERROR: %s\n' "eks-platform: workload-identity dependent is not absent; destroy order violation" >&2
        guard_status="FAIL"
        summary_code="DEPENDENT_NOT_ABSENT"
        ;;
    esac

    if [[ "$guard_status" == "PASS" ]]; then
      case "$platform_controllers_absent" in
        true) ;;
        *)
          printf 'ERROR: %s\n' "eks-platform: platform-controllers dependent is not absent; destroy order violation" >&2
          guard_status="FAIL"
          summary_code="DEPENDENT_NOT_ABSENT"
          ;;
      esac
    fi

    # Protection-state checks
    #
    # eks_deletion_protection may be 'disabled' here even on a fully
    # intended destroy, in exactly one case: an operator has already run
    # --confirm-disable-deletion-protection (validated against
    # EKS_CLUSTER_NAME in orchestrator.sh, carried here as
    # UNIFIED_CONFIRM_DISABLE_DELETION_PROTECTION) -- either in this same
    # invocation (the disable step runs inside destroy_eks_platform_scope,
    # which this guard gates access to) or in an earlier, interrupted
    # destroy attempt that already pushed deletionProtection=false live
    # before failing on something else (observed live in #142's UAT
    # teardown). Only eks-platform's own guard honors this -- workload-
    # identity's and platform-controllers' guards below still require
    # deletion_protection enabled unconditionally, since disabling it is
    # only ever confirmed for the eks-platform scope itself.
    if [[ "$guard_status" == "PASS" ]]; then
      case "$eks_deletion_protection" in
        enabled|true) ;;
        *)
          if [[ -n "${UNIFIED_CONFIRM_DISABLE_DELETION_PROTECTION:-}" ]]; then
            :
          else
            printf 'ERROR: %s\n' "eks-platform: EKS deletion protection is not enabled" >&2
            guard_status="FAIL"
            summary_code="PROTECTION_ABSENT"
          fi
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      case "$efs_protection" in
        enabled|true) ;;
        *)
          printf 'ERROR: %s\n' "eks-platform: EFS prevent_destroy protection is not enabled" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      case "$vault_lock_state" in
        locked|effective|absent) ;;
        *)
          printf 'ERROR: %s\n' "eks-platform: backup vault lock is not effective" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      local minimum_retention_days="35"
      if [[ -n "${UAT_MIN_BACKUP_RETENTION_DAYS:-}" ]]; then
        minimum_retention_days="${UAT_MIN_BACKUP_RETENTION_DAYS}"
      fi
      if [[ ! "$backup_retention_days" =~ ^[0-9]+$ ]]; then
        printf 'ERROR: %s\n' "eks-platform: backup retention days is not numeric" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      elif (( backup_retention_days < minimum_retention_days )); then
        printf 'ERROR: %s\n' "eks-platform: backup retention (${backup_retention_days}d) is below required minimum (${minimum_retention_days}d)" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      fi
    fi
  fi

  # ---- Step 3: derive canonical identity from validated platform_contract ----
  if [[ -n "${EKS_PLATFORM_IDENTITY:-}" ]]; then
    cluster_arn="${EKS_PLATFORM_IDENTITY}"
  elif [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" && -n "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    cluster_arn="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
  else
    printf 'ERROR: %s\n' "eks-platform: cluster ARN unavailable; EKS_PLATFORM_IDENTITY or (EKS_CLUSTER_NAME + AWS_REGION + EXPECTED_AWS_ACCOUNT_ID) required" >&2
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    cluster_arn="eks-platform:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${cluster_arn}
status=${guard_status}
${observations}"

  if command -v sha256sum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | sha256sum | cut -c1-64)"
  elif command -v shasum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | shasum -a 256 | cut -c1-64)"
  else
    digest_hex="$(printf '%s' "$canonical_data" | openssl dgst -sha256 -r | cut -d' ' -f1)"
  fi

  # ---- Step 5: invoke callback exactly once ----
  record_pre_destroy_guard_result "$scope" "$guard_status" "$cluster_arn" "sha256:${digest_hex}" "$summary_code"
  local callback_rc=$?

  # ---- Step 6: return matching exit code ----
  if [[ "$guard_status" == "PASS" && "$callback_rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# workload-identity pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: cluster ARN + /workload-identity
# No dependent-absence check for this guard (it is itself a dependent of
# eks-platform; platform-controllers and eks-platform must be destroyed later)
# Protection checks: EKS deletion protection, EFS prevent_destroy,
#   backup retention >= 35 days, vault lock state

eks_internal_workload_identity_pre_destroy_guard() {
  local scope="workload-identity"
  local guard_status="PASS"
  local summary_code="WORKLOAD_IDENTITY_GUARD_PASS"
  local observations=""
  local cluster_arn="workload-identity:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t eks_internal_live_guard_observations)" != "function" ]]; then
    printf 'ERROR: %s\n' "workload-identity: eks_internal_live_guard_observations seam is required" >&2
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(eks_internal_live_guard_observations "$scope")" || {
      printf 'ERROR: %s\n' "workload-identity: failed to read live guard observations" >&2
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local eks_deletion_protection=""
    local efs_protection=""
    local backup_retention_days=""
    local vault_lock_state=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        eks_deletion_protection) eks_deletion_protection="$obs_val" ;;
        efs_protection)          efs_protection="$obs_val" ;;
        backup_retention_days)   backup_retention_days="$obs_val" ;;
        vault_lock_state)        vault_lock_state="$obs_val" ;;
      esac
    done <<< "$observations"

    # Protection-state checks
    case "$eks_deletion_protection" in
      enabled|true) ;;
      *)
        printf 'ERROR: %s\n' "workload-identity: EKS deletion protection is not enabled" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
        ;;
    esac

    if [[ "$guard_status" == "PASS" ]]; then
      case "$efs_protection" in
        enabled|true) ;;
        *)
          printf 'ERROR: %s\n' "workload-identity: EFS prevent_destroy protection is not enabled" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      case "$vault_lock_state" in
        locked|effective|absent) ;;
        *)
          printf 'ERROR: %s\n' "workload-identity: backup vault lock is not effective" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      local minimum_retention_days="35"
      if [[ -n "${UAT_MIN_BACKUP_RETENTION_DAYS:-}" ]]; then
        minimum_retention_days="${UAT_MIN_BACKUP_RETENTION_DAYS}"
      fi
      if [[ ! "$backup_retention_days" =~ ^[0-9]+$ ]]; then
        printf 'ERROR: %s\n' "workload-identity: backup retention days is not numeric" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      elif (( backup_retention_days < minimum_retention_days )); then
        printf 'ERROR: %s\n' "workload-identity: backup retention (${backup_retention_days}d) is below required minimum (${minimum_retention_days}d)" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      fi
    fi
  fi

  # ---- Step 3: derive canonical identity from validated platform_contract ----
  if [[ -n "${EKS_PLATFORM_IDENTITY:-}" ]]; then
    cluster_arn="${EKS_PLATFORM_IDENTITY}/workload-identity"
  elif [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" && -n "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    cluster_arn="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}/workload-identity"
  else
    printf 'ERROR: %s\n' "workload-identity: cluster ARN unavailable; EKS_PLATFORM_IDENTITY or (EKS_CLUSTER_NAME + AWS_REGION + EXPECTED_AWS_ACCOUNT_ID) required" >&2
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    cluster_arn="workload-identity:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${cluster_arn}
status=${guard_status}
${observations}"

  if command -v sha256sum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | sha256sum | cut -c1-64)"
  elif command -v shasum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | shasum -a 256 | cut -c1-64)"
  else
    digest_hex="$(printf '%s' "$canonical_data" | openssl dgst -sha256 -r | cut -d' ' -f1)"
  fi

  # ---- Step 5: invoke callback exactly once ----
  record_pre_destroy_guard_result "$scope" "$guard_status" "$cluster_arn" "sha256:${digest_hex}" "$summary_code"
  local callback_rc=$?

  # ---- Step 6: return matching exit code ----
  if [[ "$guard_status" == "PASS" && "$callback_rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# platform-controllers pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: cluster ARN + /platform-controllers
# No dependent-absence check for this guard (it is itself a dependent of
# eks-platform; eks-platform must be destroyed later)
# Protection checks: EKS deletion protection, EFS prevent_destroy,
#   backup retention >= 35 days, vault lock state

eks_internal_platform_controllers_pre_destroy_guard() {
  local scope="platform-controllers"
  local guard_status="PASS"
  local summary_code="PLATFORM_CONTROLLERS_GUARD_PASS"
  local observations=""
  local cluster_arn="platform-controllers:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t eks_internal_live_guard_observations)" != "function" ]]; then
    printf 'ERROR: %s\n' "platform-controllers: eks_internal_live_guard_observations seam is required" >&2
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(eks_internal_live_guard_observations "$scope")" || {
      printf 'ERROR: %s\n' "platform-controllers: failed to read live guard observations" >&2
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local eks_deletion_protection=""
    local efs_protection=""
    local backup_retention_days=""
    local vault_lock_state=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        eks_deletion_protection) eks_deletion_protection="$obs_val" ;;
        efs_protection)          efs_protection="$obs_val" ;;
        backup_retention_days)   backup_retention_days="$obs_val" ;;
        vault_lock_state)        vault_lock_state="$obs_val" ;;
      esac
    done <<< "$observations"

    # Protection-state checks
    case "$eks_deletion_protection" in
      enabled|true) ;;
      *)
        printf 'ERROR: %s\n' "platform-controllers: EKS deletion protection is not enabled" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
        ;;
    esac

    if [[ "$guard_status" == "PASS" ]]; then
      case "$efs_protection" in
        enabled|true) ;;
        *)
          printf 'ERROR: %s\n' "platform-controllers: EFS prevent_destroy protection is not enabled" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      case "$vault_lock_state" in
        locked|effective|absent) ;;
        *)
          printf 'ERROR: %s\n' "platform-controllers: backup vault lock is not effective" >&2
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      local minimum_retention_days="35"
      if [[ -n "${UAT_MIN_BACKUP_RETENTION_DAYS:-}" ]]; then
        minimum_retention_days="${UAT_MIN_BACKUP_RETENTION_DAYS}"
      fi
      if [[ ! "$backup_retention_days" =~ ^[0-9]+$ ]]; then
        printf 'ERROR: %s\n' "platform-controllers: backup retention days is not numeric" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      elif (( backup_retention_days < minimum_retention_days )); then
        printf 'ERROR: %s\n' "platform-controllers: backup retention (${backup_retention_days}d) is below required minimum (${minimum_retention_days}d)" >&2
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
      fi
    fi
  fi

  # ---- Step 3: derive canonical identity from validated platform_contract ----
  if [[ -n "${EKS_PLATFORM_IDENTITY:-}" ]]; then
    cluster_arn="${EKS_PLATFORM_IDENTITY}/platform-controllers"
  elif [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" && -n "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    cluster_arn="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}/platform-controllers"
  else
    printf 'ERROR: %s\n' "platform-controllers: cluster ARN unavailable; EKS_PLATFORM_IDENTITY or (EKS_CLUSTER_NAME + AWS_REGION + EXPECTED_AWS_ACCOUNT_ID) required" >&2
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    cluster_arn="platform-controllers:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${cluster_arn}
status=${guard_status}
${observations}"

  if command -v sha256sum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | sha256sum | cut -c1-64)"
  elif command -v shasum >/dev/null 2>&1; then
    digest_hex="$(printf '%s' "$canonical_data" | shasum -a 256 | cut -c1-64)"
  else
    digest_hex="$(printf '%s' "$canonical_data" | openssl dgst -sha256 -r | cut -d' ' -f1)"
  fi

  # ---- Step 5: invoke callback exactly once ----
  record_pre_destroy_guard_result "$scope" "$guard_status" "$cluster_arn" "sha256:${digest_hex}" "$summary_code"
  local callback_rc=$?

  # ---- Step 6: return matching exit code ----
  if [[ "$guard_status" == "PASS" && "$callback_rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}
