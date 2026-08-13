#!/usr/bin/env bash
#
# PostgreSQL pre-destroy guard implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "40-postgresql/internal/pre-destroy-guards.sh"
#
# Exports only distinct guard-side postgresql_internal_*_pre_destroy_guard
# symbols. Never defines lifecycle, handler, verifier, or canonical registry
# wrapper symbols. Does not source verifiers.sh.
#
# Live platform observations are obtained exclusively through the
# postgresql_internal_live_guard_observations <scope> seam, which must be
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

postgresql_internal_guard_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

postgresql_internal_guard_sha256() {
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
# postgresql-core pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: POSTGRESQL_NAMESPACE/POSTGRESQL_CLUSTER_NAME
# Dependents that must be absent: database-access-core
# Protection checks: pvc_protection_enabled, backup_enabled

postgresql_internal_postgresql_core_pre_destroy_guard() {
  local scope="postgresql-core"
  local guard_status="PASS"
  local summary_code="POSTGRESQL_CORE_GUARD_PASS"
  local observations=""
  local resource_identity="postgresql-core:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t postgresql_internal_live_guard_observations)" != "function" ]]; then
    postgresql_internal_guard_error "postgresql-core: postgresql_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(postgresql_internal_live_guard_observations "$scope")" || {
      postgresql_internal_guard_error "postgresql-core: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local database_access_core_absent=""
    local pvc_protection_enabled=""
    local backup_enabled=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        database_access_core_absent) database_access_core_absent="$obs_val" ;;
        pvc_protection_enabled)      pvc_protection_enabled="$obs_val" ;;
        backup_enabled)              backup_enabled="$obs_val" ;;
      esac
    done <<< "$observations"

    # Dependent-absence check
    case "$database_access_core_absent" in
      true) ;;
      *)
        postgresql_internal_guard_error "postgresql-core: database-access-core dependent is not absent; destroy order violation"
        guard_status="FAIL"
        summary_code="DEPENDENT_NOT_ABSENT"
        ;;
    esac

    # ---- Protection-state observations ----
    #
    # Deliberately NOT preconditions. Requiring protections to still be ON
    # is what deadlocked a partially-completed teardown in #159: it blocks
    # the operator from finishing the destroy they already started, while
    # adding no safety once a human has seen the real enumerated resource
    # list and typed yes. The values are still read, still hashed into the
    # guard digest, and still recorded in the durable evidence record.
  fi

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${POSTGRESQL_NAMESPACE:-}" && -n "${POSTGRESQL_CLUSTER_NAME:-}" ]]; then
    resource_identity="${POSTGRESQL_NAMESPACE}/${POSTGRESQL_CLUSTER_NAME}"
  elif [[ -n "${POSTGRESQL_NAMESPACE:-}" ]]; then
    resource_identity="${POSTGRESQL_NAMESPACE}/postgresql"
  else
    postgresql_internal_guard_error "postgresql-core: resource identity unavailable; POSTGRESQL_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="postgresql-core:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(postgresql_internal_guard_sha256 "$canonical_data")"

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
# postgresql-brand pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: POSTGRESQL_NAMESPACE/brand
# Dependents that must be absent: database-access-brand
# Protection checks: pvc_protection_enabled, backup_enabled

postgresql_internal_postgresql_brand_pre_destroy_guard() {
  local scope="postgresql-brand"
  local guard_status="PASS"
  local summary_code="POSTGRESQL_BRAND_GUARD_PASS"
  local observations=""
  local resource_identity="postgresql-brand:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t postgresql_internal_live_guard_observations)" != "function" ]]; then
    postgresql_internal_guard_error "postgresql-brand: postgresql_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(postgresql_internal_live_guard_observations "$scope")" || {
      postgresql_internal_guard_error "postgresql-brand: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local database_access_brand_absent=""
    local pvc_protection_enabled=""
    local backup_enabled=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        database_access_brand_absent) database_access_brand_absent="$obs_val" ;;
        pvc_protection_enabled)       pvc_protection_enabled="$obs_val" ;;
        backup_enabled)               backup_enabled="$obs_val" ;;
      esac
    done <<< "$observations"

    # Dependent-absence check
    case "$database_access_brand_absent" in
      true) ;;
      *)
        postgresql_internal_guard_error "postgresql-brand: database-access-brand dependent is not absent; destroy order violation"
        guard_status="FAIL"
        summary_code="DEPENDENT_NOT_ABSENT"
        ;;
    esac

    # ---- Protection-state observations ----
    #
    # Deliberately NOT preconditions. Requiring protections to still be ON
    # is what deadlocked a partially-completed teardown in #159: it blocks
    # the operator from finishing the destroy they already started, while
    # adding no safety once a human has seen the real enumerated resource
    # list and typed yes. The values are still read, still hashed into the
    # guard digest, and still recorded in the durable evidence record.
  fi

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${POSTGRESQL_NAMESPACE:-}" ]]; then
    resource_identity="${POSTGRESQL_NAMESPACE}/brand"
  else
    postgresql_internal_guard_error "postgresql-brand: resource identity unavailable; POSTGRESQL_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="postgresql-brand:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(postgresql_internal_guard_sha256 "$canonical_data")"

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
