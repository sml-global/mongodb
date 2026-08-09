#!/usr/bin/env bash
#
# Real Kubernetes-backed implementation of the signoz destroy-time
# observation seam that pre-destroy-guards.sh calls as
# `signoz_internal_live_guard_observations`. This symbol had no real
# implementation before this file -- guards failed closed with "seam is
# required" for both scopes in this package (see issue #108).
#
# Read-only: this file only ever calls kubectl get. It never mutates
# infrastructure, writes files, or touches Terraform state.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_signoz_live_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# signoz-observability's own presence signal (mirrors
# signoz_internal_signoz_observability_verifier in verifiers.sh, which
# checks the same secret to confirm the scope IS provisioned; this checks
# the inverse -- that it is NOT -- for the signoz scope's pre-destroy
# guard, which must refuse to destroy signoz while signoz-observability
# still has live resources depending on it).
_signoz_live_observability_absent() {
  local namespace="$1"
  if kubectl -n "$namespace" get secret signoz-api-key >/dev/null 2>&1; then
    printf 'false'
  else
    printf 'true'
  fi
}

# signoz_internal_live_guard_observations <scope>
#
# Emits key=value lines for the pre-destroy-guard checks in
# pre-destroy-guards.sh. Only the `signoz` scope's guard validates an
# observation (signoz_observability_absent); signoz-observability's own
# guard has no dependent-absence check, so it needs no observation keys --
# but the seam function itself must still exist and be callable, since the
# guard checks `type -t` for it before calling.
signoz_internal_live_guard_observations() {
  local scope_name="$1"
  local namespace="${SIGNOZ_NAMESPACE:-signoz}"

  if [[ "$scope_name" == "signoz" ]]; then
    local observability_absent
    observability_absent="$(_signoz_live_observability_absent "$namespace")" || {
      _signoz_live_error "${scope_name}: unable to determine signoz-observability presence"
      return 1
    }
    printf 'signoz_observability_absent=%s\n' "$observability_absent"
  fi
}
