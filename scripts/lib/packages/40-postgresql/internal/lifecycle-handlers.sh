#!/usr/bin/env bash
#
# PostgreSQL lifecycle handler implementation (stubs).
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "40-postgresql/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side postgresql_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

postgresql_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

postgresql_internal_provision_postgresql_core() {
  printf 'INFO: postgresql-core provision: namespace=%s\n' "${POSTGRESQL_NAMESPACE:-postgresql}"
  return 0
}

postgresql_internal_provision_postgresql_brand() {
  printf 'INFO: postgresql-brand provision: namespace=%s\n' "${POSTGRESQL_NAMESPACE:-postgresql}"
  return 0
}

postgresql_internal_destroy_postgresql_core() {
  printf 'INFO: postgresql-core destroy: namespace=%s\n' "${POSTGRESQL_NAMESPACE:-postgresql}"
  return 0
}

postgresql_internal_destroy_postgresql_brand() {
  printf 'INFO: postgresql-brand destroy: namespace=%s\n' "${POSTGRESQL_NAMESPACE:-postgresql}"
  return 0
}
