#!/usr/bin/env bash
#
# Real Kubernetes-backed implementation of the mongodb destroy-time
# observation seam that pre-destroy-guards.sh calls as
# `mongodb_internal_live_guard_observations`. This symbol had no real
# implementation before this file -- guards failed closed with "seam is
# required" for both scopes in this package (see issue #108).
#
# Read-only: this file only ever calls kubectl get. It never mutates
# infrastructure, writes files, or touches Terraform state.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_mongodb_live_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# mongodb-access's own presence signal (mirrors
# mongodb_internal_mongodb_access_verifier in verifiers.sh, which checks the
# same secret to confirm the scope IS provisioned; this checks the inverse
# -- that it is NOT -- for the mongodb scope's pre-destroy guard, which must
# refuse to destroy mongodb while mongodb-access still depends on it).
_mongodb_live_access_absent() {
  local namespace="$1"
  if kubectl -n "$namespace" get secret oms-audit-writer >/dev/null 2>&1; then
    printf 'false'
  else
    printf 'true'
  fi
}

# PVC deletion protection here means the StorageClass's reclaimPolicy is
# Retain, not a Kubernetes-native "protection" API -- confirmed against
# k8s/base/storageclass-gp3-mongodb.yaml (reclaimPolicy: Retain) and the
# matching comment in scripts/legacy/dev/destroy.sh's destroy_mongodb_k8s().
_mongodb_live_pvc_protection_enabled() {
  local reclaim_policy
  reclaim_policy="$(kubectl get storageclass gp3-mongodb -o jsonpath='{.reclaimPolicy}' 2>/dev/null)" || return 1
  case "$reclaim_policy" in
    Retain) printf 'enabled' ;;
    *) printf 'disabled' ;;
  esac
}

# Percona Backup for MongoDB is enabled via the PerconaServerMongoDB CR's
# spec.backup.enabled field (k8s/base/psmdb-cluster.yaml).
#
# A missing CR (kubectl exit 1 with a NotFound stderr) is a valid platform
# state -- the cluster was never provisioned or was already torn down at the
# k8s layer -- and is distinct from a real read failure (auth/connectivity).
# Only the latter should abort the guard; the former reports psmdb_cr_absent
# so the guard can skip the backup/PVC protection checks it can't evaluate
# against a resource that isn't there.
_mongodb_live_pbm_backup_enabled() {
  local namespace="$1"
  local combined_output enabled

  combined_output="$(kubectl -n "$namespace" get perconaservermongodb psmdb -o jsonpath='{.spec.backup.enabled}' 2>&1)"
  if [[ $? -ne 0 ]]; then
    case "$combined_output" in
      *NotFound*)
        printf 'absent'
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  enabled="$combined_output"
  case "$enabled" in
    true) printf 'enabled' ;;
    *) printf 'disabled' ;;
  esac
}

# mongodb_internal_live_guard_observations <scope>
#
# Emits key=value lines for the pre-destroy-guard checks in
# pre-destroy-guards.sh. mongodb's guard validates all three keys;
# mongodb-access's guard validates only the protection-state pair (it has
# no dependent scopes of its own).
mongodb_internal_live_guard_observations() {
  local scope_name="$1"
  local namespace="${MONGODB_NAMESPACE:-mongodb}"
  local pvc_protection_enabled
  local pbm_backup_enabled

  pvc_protection_enabled="$(_mongodb_live_pvc_protection_enabled)" || {
    _mongodb_live_error "${scope_name}: unable to read gp3-mongodb StorageClass reclaimPolicy"
    return 1
  }

  pbm_backup_enabled="$(_mongodb_live_pbm_backup_enabled "$namespace")" || {
    _mongodb_live_error "${scope_name}: unable to read PerconaServerMongoDB backup.enabled"
    return 1
  }

  if [[ "$scope_name" == "mongodb" ]]; then
    local access_absent
    access_absent="$(_mongodb_live_access_absent "$namespace")" || {
      _mongodb_live_error "${scope_name}: unable to determine mongodb-access presence"
      return 1
    }
    printf 'mongodb_access_absent=%s\n' "$access_absent"
  fi

  printf 'pvc_protection_enabled=%s\n' "$pvc_protection_enabled"
  printf 'pbm_backup_enabled=%s\n' "$pbm_backup_enabled"
}
