#!/usr/bin/env bash
#
# SigNoz lifecycle handler implementation (stubs).
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "50-signoz/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side signoz_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

signoz_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

signoz_internal_provision_signoz() {
  printf 'INFO: signoz provision: namespace=%s\n' "${SIGNOZ_NAMESPACE:-signoz}"
  return 0
}

signoz_internal_destroy_signoz() {
  printf 'INFO: signoz destroy: namespace=%s\n' "${SIGNOZ_NAMESPACE:-signoz}"
  return 0
}

signoz_internal_provision_signoz_observability() {
  printf 'INFO: signoz-observability provision: namespace=%s\n' "${SIGNOZ_NAMESPACE:-signoz}"
  return 0
}

signoz_internal_destroy_signoz_observability() {
  printf 'INFO: signoz-observability destroy: namespace=%s\n' "${SIGNOZ_NAMESPACE:-signoz}"
  return 0
}
