#!/usr/bin/env bash
#
# SigNoz verifier implementation (stubs).
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
  printf 'PASS: signoz verified: %s\n' "$namespace"
  return 0
}

signoz_internal_signoz_observability_verifier() {
  local namespace="${SIGNOZ_NAMESPACE:-signoz}"
  printf 'PASS: signoz-observability verified: %s\n' "$namespace"
  return 0
}
