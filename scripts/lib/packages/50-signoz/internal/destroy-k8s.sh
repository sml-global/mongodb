#!/usr/bin/env bash
#
# Environment-aware SigNoz Kubernetes-workload teardown, used by
# signoz_internal_destroy_signoz (lifecycle-handlers.sh). Ports the same
# ClickHouse-finalizer-clearing logic as scripts/legacy/dev/destroy.sh's
# destroy_signoz() (from #63's original fix), parameterized on the target
# environment's namespace instead of the legacy script's hardcoded `signoz`
# namespace.
#
# scripts/legacy/dev/destroy.sh itself is never modified -- it stays frozen
# as the current DEV production path per CLAUDE.md. This is a net-new,
# independently callable implementation for the environment-aware handler
# only.
#
# No shared/global state: every function takes its environment's values as
# explicit arguments (see issue #111 -- a shared "current environment"
# global would reintroduce the same class of cross-environment hazard #95
# found once already, through a different mechanism).
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_signoz_destroy_k8s_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# signoz_internal_destroy_k8s <namespace>
#
# The sole argument is required and explicit -- no fallback to any
# global/environment variable of the same name.
signoz_internal_destroy_k8s() {
  local namespace="$1"

  if [[ -z "$namespace" ]]; then
    _signoz_destroy_k8s_error "signoz_internal_destroy_k8s requires namespace"
    return 1
  fi

  printf 'Removing SigNoz HelmRelease and workload resources in namespace %s...\n' "$namespace"
  kubectl -n "$namespace" delete helmrelease signoz --ignore-not-found=true || true

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    printf '%s namespace already absent.\n' "$namespace"
    return 0
  fi

  printf 'Removing %s namespace (non-blocking)...\n' "$namespace"
  # --wait=false: kubectl delete on a namespace blocks until fully
  # terminated, which never happens if a ClickHouse finalizer is stuck
  # (#63). Issue the delete without waiting so we can clear finalizers
  # below, then wait explicitly.
  kubectl delete namespace "$namespace" --ignore-not-found=true --wait=false || true

  printf 'Clearing ClickHouse/namespace finalizers if present...\n'
  local deadline=$((SECONDS + 60))
  while kubectl get namespace "$namespace" >/dev/null 2>&1 && (( SECONDS < deadline )); do
    kubectl -n "$namespace" get clickhouseinstallations.clickhouse.altinity.com -o name 2>/dev/null \
      | xargs -I{} kubectl -n "$namespace" patch {} --type='json' -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
    kubectl patch namespace "$namespace" --type='json' -p='[{"op":"replace","path":"/spec/finalizers","value":[]}]' >/dev/null 2>&1 || true
    sleep 3
  done

  if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    _signoz_destroy_k8s_error "${namespace} namespace still present after finalizer cleanup attempts."
  else
    printf '%s namespace removed.\n' "$namespace"
  fi
}
