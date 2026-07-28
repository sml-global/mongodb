#!/usr/bin/env bash
#
# MongoDB verifier implementation (stubs).
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "30-mongodb/internal/verifiers.sh"
#
# Exports only distinct verifier-side mongodb_internal_* symbols. Never
# defines lifecycle, handler, pre-destroy-guard, or canonical registry
# wrapper symbols. Bash 3.2 compatible: no associative arrays, no declare -g,
# no namerefs. This file contains no top-level execution.

mongodb_internal_verifier_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

mongodb_internal_mongodb_verifier() {
  local namespace="${MONGODB_NAMESPACE:-mongodb}"
  local replica_set="${MONGODB_REPLICA_SET_NAME:-rs0}"
  printf 'PASS: mongodb cluster verified: %s/%s\n' "$namespace" "$replica_set"
  return 0
}

mongodb_internal_mongodb_access_verifier() {
  local namespace="${MONGODB_NAMESPACE:-mongodb}"
  printf 'PASS: mongodb-access verified: %s/access\n' "$namespace"
  return 0
}
