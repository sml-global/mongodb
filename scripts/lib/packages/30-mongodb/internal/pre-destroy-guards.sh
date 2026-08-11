#!/usr/bin/env bash
#
# MongoDB pre-destroy guard implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "30-mongodb/internal/pre-destroy-guards.sh"
#
# Exports only distinct guard-side mongodb_internal_*_pre_destroy_guard
# symbols. Never defines lifecycle, handler, verifier, or canonical registry
# wrapper symbols. Does not source verifiers.sh.
#
# Live platform observations are obtained exclusively through the
# mongodb_internal_live_guard_observations <scope> seam, which must be
# defined externally before any guard function is called.
#
# Each guard:
#   1. Reads observations from the seam
#   2. Validates protection state and dependent-scope absence
#   3. Derives canonical resource identity from validated env vars
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
# Shared helpers
# ---------------------------------------------------------------------------

mongodb_internal_guard_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

mongodb_internal_guard_sha256() {
  local data="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$data" | sha256sum | cut -c1-64
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$data" | shasum -a 256 | cut -c1-64
  else
    printf '%s' "$data" | openssl dgst -sha256 -r | cut -d' ' -f1
  fi
}

# ---------------------------------------------------------------------------
# mongodb pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: MONGODB_NAMESPACE/MONGODB_REPLICA_SET_NAME
# Dependents that must be absent: mongodb-access
# Protection checks: pvc_protection_enabled, pbm_backup_enabled

mongodb_internal_mongodb_pre_destroy_guard() {
  local scope="mongodb"
  local guard_status="PASS"
  local summary_code="MONGODB_GUARD_PASS"
  local observations=""
  local resource_identity="mongodb:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t mongodb_internal_live_guard_observations)" != "function" ]]; then
    mongodb_internal_guard_error "mongodb: mongodb_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(mongodb_internal_live_guard_observations "$scope")" || {
      mongodb_internal_guard_error "mongodb: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local mongodb_access_absent=""
    local pvc_protection_enabled=""
    local pbm_backup_enabled=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        mongodb_access_absent)  mongodb_access_absent="$obs_val" ;;
        pvc_protection_enabled) pvc_protection_enabled="$obs_val" ;;
        pbm_backup_enabled)     pbm_backup_enabled="$obs_val" ;;
      esac
    done <<< "$observations"

    # Dependent-absence check
    case "$mongodb_access_absent" in
      true) ;;
      *)
        mongodb_internal_guard_error "mongodb: mongodb-access dependent is not absent; destroy order violation"
        guard_status="FAIL"
        summary_code="DEPENDENT_NOT_ABSENT"
        ;;
    esac

    # Protection-state checks
    if [[ "$guard_status" == "PASS" ]]; then
      case "$pvc_protection_enabled" in
        enabled|true) ;;
        *)
          mongodb_internal_guard_error "mongodb: PVC deletion protection is not enabled"
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi

    if [[ "$guard_status" == "PASS" ]]; then
      case "$pbm_backup_enabled" in
        enabled|true|absent) ;;
        *)
          mongodb_internal_guard_error "mongodb: PBM backup is not enabled"
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi
  fi

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${MONGODB_NAMESPACE:-}" && -n "${MONGODB_REPLICA_SET_NAME:-}" ]]; then
    resource_identity="${MONGODB_NAMESPACE}/${MONGODB_REPLICA_SET_NAME}"
  elif [[ -n "${MONGODB_NAMESPACE:-}" ]]; then
    resource_identity="${MONGODB_NAMESPACE}/mongodb"
  else
    mongodb_internal_guard_error "mongodb: resource identity unavailable; MONGODB_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="mongodb:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(mongodb_internal_guard_sha256 "$canonical_data")"

  # ---- Step 5: invoke callback exactly once ----
  record_pre_destroy_guard_result \
    "$scope" "$guard_status" "$resource_identity" "sha256:${digest_hex}" "$summary_code"
  local callback_rc=$?

  # ---- Step 6: return matching exit code ----
  if [[ "$guard_status" == "PASS" && "$callback_rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# mongodb-access pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: MONGODB_NAMESPACE/access
# No dependent-absence check (mongodb-access has no declared dependents)
# Protection checks: pvc_protection_enabled, pbm_backup_enabled

mongodb_internal_mongodb_access_pre_destroy_guard() {
  local scope="mongodb-access"
  local guard_status="PASS"
  local summary_code="MONGODB_ACCESS_GUARD_PASS"
  local observations=""
  local resource_identity="mongodb-access:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t mongodb_internal_live_guard_observations)" != "function" ]]; then
    mongodb_internal_guard_error "mongodb-access: mongodb_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(mongodb_internal_live_guard_observations "$scope")" || {
      mongodb_internal_guard_error "mongodb-access: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local pvc_protection_enabled=""
    local pbm_backup_enabled=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        pvc_protection_enabled) pvc_protection_enabled="$obs_val" ;;
        pbm_backup_enabled)     pbm_backup_enabled="$obs_val" ;;
      esac
    done <<< "$observations"

    case "$pvc_protection_enabled" in
      enabled|true) ;;
      *)
        mongodb_internal_guard_error "mongodb-access: PVC deletion protection is not enabled"
        guard_status="FAIL"
        summary_code="PROTECTION_ABSENT"
        ;;
    esac

    if [[ "$guard_status" == "PASS" ]]; then
      case "$pbm_backup_enabled" in
        enabled|true|absent) ;;
        *)
          mongodb_internal_guard_error "mongodb-access: PBM backup is not enabled"
          guard_status="FAIL"
          summary_code="PROTECTION_ABSENT"
          ;;
      esac
    fi
  fi

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${MONGODB_NAMESPACE:-}" ]]; then
    resource_identity="${MONGODB_NAMESPACE}/access"
  else
    mongodb_internal_guard_error "mongodb-access: resource identity unavailable; MONGODB_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="mongodb-access:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(mongodb_internal_guard_sha256 "$canonical_data")"

  # ---- Step 5: invoke callback exactly once ----
  record_pre_destroy_guard_result \
    "$scope" "$guard_status" "$resource_identity" "sha256:${digest_hex}" "$summary_code"
  local callback_rc=$?

  # ---- Step 6: return matching exit code ----
  if [[ "$guard_status" == "PASS" && "$callback_rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}
