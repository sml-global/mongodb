#!/usr/bin/env bash
#
# MongoDB verifier implementation.
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

  # Check if namespace exists and is in Active state (not Terminating)
  local ns_phase
  ns_phase="$(kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)"

  if [[ -z "$ns_phase" ]]; then
    # Namespace doesn't exist - this is expected if mongodb was never provisioned
    mongodb_internal_verifier_error "mongodb not provisioned (namespace '$namespace' not found)"
    return 1
  elif [[ "$ns_phase" == "Terminating" ]]; then
    # Namespace is terminating - treat this as "not provisioned" for verification
    mongodb_internal_verifier_error "mongodb is being destroyed (namespace '$namespace' is Terminating)"
    return 1
  fi

  if ! kubectl -n "$namespace" get perconaservermongodb psmdb >/dev/null 2>&1; then
    mongodb_internal_verifier_error "PerconaServerMongoDB 'psmdb' not found in namespace '$namespace'"
    return 1
  fi

  if ! kubectl -n "$namespace" rollout status "statefulset/psmdb-${replica_set}" --timeout=10s >/dev/null 2>&1; then
    mongodb_internal_verifier_error "StatefulSet 'psmdb-${replica_set}' in namespace '$namespace' is not rolled out"
    return 1
  fi

  printf 'PASS: mongodb cluster verified: %s/%s\n' "$namespace" "$replica_set"
}

mongodb_internal_mongodb_access_verifier() {
  local namespace="${MONGODB_NAMESPACE:-mongodb}"

  # Check if namespace exists and is Active
  local ns_phase
  ns_phase="$(kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)"

  if [[ -z "$ns_phase" ]]; then
    mongodb_internal_verifier_error "mongodb-access not configured (namespace '$namespace' not found)"
    return 1
  elif [[ "$ns_phase" == "Terminating" ]]; then
    mongodb_internal_verifier_error "mongodb-access is being destroyed (namespace '$namespace' is Terminating)"
    return 1
  fi

  if ! kubectl -n "$namespace" get secret oms-audit-writer >/dev/null 2>&1; then
    mongodb_internal_verifier_error "oms-audit-writer secret not found in namespace '$namespace'"
    return 1
  fi

  printf 'PASS: mongodb-access verified: %s/access\n' "$namespace"
}
