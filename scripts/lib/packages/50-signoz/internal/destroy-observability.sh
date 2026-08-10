#!/usr/bin/env bash
#
# Environment-aware SigNoz-observability teardown, used by
# signoz_internal_destroy_signoz_observability (lifecycle-handlers.sh).
# Ports the same live-endpoint-check-then-terraform-destroy logic as
# scripts/legacy/dev/destroy.sh's destroy_signoz_observability(),
# parameterized on the target environment's namespace/state
# bucket/key/region instead of the legacy script's hardcoded `signoz`
# namespace and oms/dev/signoz-observability.tfstate state key.
#
# scripts/legacy/dev/destroy.sh itself is never modified -- it stays frozen
# as the current DEV production path per CLAUDE.md. This is a net-new,
# independently callable implementation for the environment-aware handler
# only.
#
# No shared/global state: every function takes its environment's values as
# explicit arguments (see issue #111).
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_signoz_destroy_observability_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# signoz_internal_destroy_observability <namespace> <tf_dir> <tf_state_key> <tf_state_bucket> <tf_state_region> <environment> <auto_approve> <bootstrap_backend_script>
#
# All eight arguments are required and explicit -- no fallback to any
# global/environment variable of the same name.
signoz_internal_destroy_observability() {
  local namespace="$1"
  local tf_dir="$2"
  local tf_state_key="$3"
  local tf_state_bucket="$4"
  local tf_state_region="$5"
  local environment="$6"
  local auto_approve="$7"
  local bootstrap_backend_script="$8"
  local pf_pid=""

  if [[ -z "$namespace" || -z "$tf_dir" || -z "$tf_state_key" || -z "$tf_state_bucket" || -z "$tf_state_region" || -z "$bootstrap_backend_script" ]]; then
    _signoz_destroy_observability_error "signoz_internal_destroy_observability requires namespace, tf_dir, tf_state_key, tf_state_bucket, tf_state_region, environment, auto_approve, and bootstrap_backend_script"
    return 1
  fi

  if ! kubectl -n "$namespace" get secret signoz-api-key >/dev/null 2>&1; then
    printf 'signoz-api-key Secret not found; nothing to destroy for signoz-observability (or it was never applied).\n'
    return 0
  fi

  local signoz_access_token
  signoz_access_token="$(kubectl -n "$namespace" get secret signoz-api-key -o jsonpath='{.data.token}' | base64 -d)"
  local signoz_endpoint="${SIGNOZ_ENDPOINT:-http://127.0.0.1:3301}"

  # Self-manage a temporary port-forward so this scope never depends on the
  # operator having a separate `open-signoz-ui.sh` session already running.
  if [[ "$signoz_endpoint" =~ ^https?://(127\.0\.0\.1|localhost):([0-9]+)$ ]]; then
    local endpoint_local_port="${BASH_REMATCH[2]}"
    if ! curl -s -o /dev/null --max-time 2 "$signoz_endpoint/api/v1/health"; then
      printf 'Starting temporary port-forward to %s:8080 on 127.0.0.1:%s ...\n' "$namespace" "$endpoint_local_port"
      kubectl -n "$namespace" port-forward svc/signoz "${endpoint_local_port}:8080" >/tmp/signoz-observability-destroy-pf.log 2>&1 &
      pf_pid=$!
      local _attempt
      for _attempt in $(seq 1 30); do
        curl -s -o /dev/null --max-time 2 "$signoz_endpoint/api/v1/health" && break
        sleep 1
      done
    fi
  fi

  if ! curl -sf -o /dev/null "$signoz_endpoint/api/v1/health"; then
    _signoz_destroy_observability_error "SigNoz endpoint ${signoz_endpoint} is not reachable; skipping signoz-observability terraform destroy. (Its resources will be removed anyway when the ${namespace} namespace/PVCs are deleted.)"
    [[ -n "$pf_pid" ]] && kill "$pf_pid" >/dev/null 2>&1 || true
    return 0
  fi

  export SIGNOZ_ACCESS_TOKEN="$signoz_access_token"
  export SIGNOZ_ENDPOINT="$signoz_endpoint"

  terraform_destroy_scope \
    "$tf_dir" \
    "$tf_state_key" \
    "$tf_state_bucket" \
    "$tf_state_region" \
    "$environment" \
    "$auto_approve" \
    "$bootstrap_backend_script"
  local destroy_rc=$?

  [[ -n "$pf_pid" ]] && kill "$pf_pid" >/dev/null 2>&1 || true

  return "$destroy_rc"
}
