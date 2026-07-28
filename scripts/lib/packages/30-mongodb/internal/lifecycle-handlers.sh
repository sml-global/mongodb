#!/usr/bin/env bash
#
# MongoDB lifecycle handler implementation (stubs).
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side mongodb_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

mongodb_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

mongodb_internal_provision_mongodb() {
  printf 'INFO: mongodb provision: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}

mongodb_internal_provision_mongodb_access() {
  printf 'INFO: mongodb-access provision: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}

mongodb_internal_destroy_mongodb() {
  printf 'INFO: mongodb destroy: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}

mongodb_internal_destroy_mongodb_access() {
  printf 'INFO: mongodb-access destroy: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}
