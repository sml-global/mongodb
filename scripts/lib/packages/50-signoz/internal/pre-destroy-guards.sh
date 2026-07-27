#!/usr/bin/env bash
#
# SigNoz pre-destroy guard implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "50-signoz/internal/pre-destroy-guards.sh"
#
# Exports only distinct guard-side signoz_internal_*_pre_destroy_guard
# symbols. Never defines lifecycle, handler, verifier, or canonical registry
# wrapper symbols. Does not source verifiers.sh.
#
# Live platform observations are obtained exclusively through the
# signoz_internal_live_guard_observations <scope> seam, which must be
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

signoz_internal_guard_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

signoz_internal_guard_sha256() {
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
# signoz pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: SIGNOZ_NAMESPACE
# Dependents that must be absent: signoz-observability
# Protection checks: none (telemetry platform)

signoz_internal_signoz_pre_destroy_guard() {
  local scope="signoz"
  local guard_status="PASS"
  local summary_code="SIGNOZ_GUARD_PASS"
  local observations=""
  local resource_identity="signoz:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t signoz_internal_live_guard_observations)" != "function" ]]; then
    signoz_internal_guard_error "signoz: signoz_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(signoz_internal_live_guard_observations "$scope")" || {
      signoz_internal_guard_error "signoz: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  if [[ "$guard_status" == "PASS" ]]; then
    local signoz_observability_absent=""
    local obs_key="" obs_val=""

    while IFS='=' read -r obs_key obs_val; do
      case "$obs_key" in
        signoz_observability_absent) signoz_observability_absent="$obs_val" ;;
      esac
    done <<< "$observations"

    # Dependent-absence check
    case "$signoz_observability_absent" in
      true) ;;
      *)
        signoz_internal_guard_error "signoz: signoz-observability dependent is not absent; destroy order violation"
        guard_status="FAIL"
        summary_code="DEPENDENT_NOT_ABSENT"
        ;;
    esac
  fi

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${SIGNOZ_NAMESPACE:-}" ]]; then
    resource_identity="${SIGNOZ_NAMESPACE}"
  else
    signoz_internal_guard_error "signoz: resource identity unavailable; SIGNOZ_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="signoz:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(signoz_internal_guard_sha256 "$canonical_data")"

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
# signoz-observability pre-destroy guard
# ---------------------------------------------------------------------------
#
# Identity: SIGNOZ_NAMESPACE/observability
# Dependents that must be absent: none
# Protection checks: none (telemetry platform)

signoz_internal_signoz_observability_pre_destroy_guard() {
  local scope="signoz-observability"
  local guard_status="PASS"
  local summary_code="SIGNOZ_OBSERVABILITY_GUARD_PASS"
  local observations=""
  local resource_identity="signoz-observability:identity-unavailable"
  local canonical_data=""
  local digest_hex=""

  # ---- Step 1: read live observations via seam ----
  if [[ "$(type -t signoz_internal_live_guard_observations)" != "function" ]]; then
    signoz_internal_guard_error "signoz-observability: signoz_internal_live_guard_observations seam is required"
    guard_status="FAIL"
    summary_code="OBSERVATIONS_UNAVAILABLE"
  else
    observations="$(signoz_internal_live_guard_observations "$scope")" || {
      signoz_internal_guard_error "signoz-observability: failed to read live guard observations"
      guard_status="FAIL"
      summary_code="OBSERVATIONS_UNAVAILABLE"
    }
  fi

  # ---- Step 2: parse and validate observations ----
  # (signoz-observability has no dependent scopes, so no validation needed)

  # ---- Step 3: derive canonical identity from validated platform contract ----
  if [[ -n "${SIGNOZ_NAMESPACE:-}" ]]; then
    resource_identity="${SIGNOZ_NAMESPACE}/observability"
  else
    signoz_internal_guard_error "signoz-observability: resource identity unavailable; SIGNOZ_NAMESPACE is required"
    guard_status="FAIL"
    summary_code="IDENTITY_UNAVAILABLE"
    resource_identity="signoz-observability:identity-unavailable"
  fi

  # ---- Step 4: build canonical data and compute SHA-256 digest ----
  canonical_data="scope=${scope}
identity=${resource_identity}
status=${guard_status}
${observations}"

  digest_hex="$(signoz_internal_guard_sha256 "$canonical_data")"

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
