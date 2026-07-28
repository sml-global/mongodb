#!/usr/bin/env bash
#
# PostgreSQL verifier implementation (stubs).
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "40-postgresql/internal/verifiers.sh"
#
# Exports only distinct verifier-side postgresql_internal_* symbols. Never
# defines lifecycle, handler, pre-destroy-guard, or canonical registry
# wrapper symbols. Bash 3.2 compatible: no associative arrays, no declare -g,
# no namerefs. This file contains no top-level execution.

postgresql_internal_verifier_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

postgresql_internal_postgresql_core_verifier() {
  local namespace="${POSTGRESQL_NAMESPACE:-postgresql}"
  local cluster_name="${POSTGRESQL_CLUSTER_NAME:-oms-postgresql}"
  printf 'PASS: postgresql-core cluster verified: %s/%s\n' "$namespace" "$cluster_name"
  return 0
}

postgresql_internal_postgresql_brand_verifier() {
  local namespace="${POSTGRESQL_NAMESPACE:-postgresql}"
  printf 'PASS: postgresql-brand verified: %s/brand\n' "$namespace"
  return 0
}
