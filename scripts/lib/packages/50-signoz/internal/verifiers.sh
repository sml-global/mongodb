#!/usr/bin/env bash
#
# SigNoz verifier implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "50-signoz/internal/verifiers.sh"
#
# Exports only distinct verifier-side signoz_internal_* symbols. Never
# defines lifecycle, handler, pre-destroy-guard, or canonical registry
# wrapper symbols. Bash 3.2 compatible: no associative arrays, no declare -g,
# no namerefs. This file contains no top-level execution.

signoz_internal_verifier_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

signoz_internal_signoz_verifier() {
  local namespace="${SIGNOZ_NAMESPACE:-signoz}"
  local ready

  if ! kubectl -n "$namespace" get pod signoz-0 >/dev/null 2>&1; then
    signoz_internal_verifier_error "pod signoz-0 not found in namespace '$namespace'"
    return 1
  fi

  ready="$(kubectl -n "$namespace" get pod signoz-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
  if [[ "$ready" != "true" ]]; then
    signoz_internal_verifier_error "pod signoz-0 in namespace '$namespace' is not Ready"
    return 1
  fi

  printf 'PASS: signoz verified: %s\n' "$namespace"
}

signoz_internal_signoz_observability_verifier() {
  local namespace="${SIGNOZ_NAMESPACE:-signoz}"

  if ! kubectl -n "$namespace" get secret signoz-api-key >/dev/null 2>&1; then
    signoz_internal_verifier_error "signoz-api-key secret not found in namespace '$namespace'"
    return 1
  fi

  printf 'PASS: signoz-observability verified: %s\n' "$namespace"
}
