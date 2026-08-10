#!/usr/bin/env bash
#
# SigNoz lifecycle handler implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "50-signoz/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side signoz_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.
#
# Reuses the same runners the legacy dev path uses
# (scripts/provision-k8s-components.sh signoz,
# scripts/provision-signoz-observability.sh), both of which read
# SIGNOZ_NAMESPACE/AWS_REGION/etc. already exported by load_platform_env
# before this handler runs — no new orchestration logic is reimplemented
# here.
#
# signoz_internal_destroy_signoz()/signoz_internal_destroy_signoz_observability()
# are environment-aware (issue #111): they call destroy-k8s.sh/
# destroy-observability.sh's parameterized teardown functions directly,
# rather than shelling out to the frozen, DEV-hardcoded
# scripts/legacy/dev/destroy.sh. That legacy script is never modified and
# keeps working unchanged for DEV's own `bash scripts/destroy.sh signoz`
# (no --env) path.

signoz_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

signoz_internal_provision_signoz() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  bash "${root_dir}/scripts/provision-k8s-components.sh" signoz \
    || { signoz_internal_error "signoz provision failed"; return 1; }
}

signoz_internal_destroy_signoz() {
  local namespace="${SIGNOZ_NAMESPACE:?SIGNOZ_NAMESPACE must be set}"

  signoz_internal_destroy_k8s "$namespace" \
    || { signoz_internal_error "signoz Kubernetes teardown failed"; return 1; }
}

signoz_internal_provision_signoz_observability() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  TF_STATE_KEY="${SIGNOZ_OBSERVABILITY_STATE_KEY:-${TF_STATE_KEY:-}}" \
    bash "${root_dir}/scripts/provision-signoz-observability.sh" --auto-approve \
    || { signoz_internal_error "signoz-observability provision failed"; return 1; }
}

signoz_internal_destroy_signoz_observability() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"
  local namespace="${SIGNOZ_NAMESPACE:?SIGNOZ_NAMESPACE must be set}"
  local environment="${ENVIRONMENT:?ENVIRONMENT must be set}"
  local tf_state_key="${SIGNOZ_OBSERVABILITY_STATE_KEY:?SIGNOZ_OBSERVABILITY_STATE_KEY must be set}"
  local tf_state_bucket="${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set}"
  local tf_state_region="${TF_STATE_REGION:?TF_STATE_REGION must be set}"

  signoz_internal_destroy_observability \
    "$namespace" \
    "${root_dir}/platform-prerequisites/terraform/signoz-observability" \
    "$tf_state_key" \
    "$tf_state_bucket" \
    "$tf_state_region" \
    "$environment" \
    "true" \
    "${root_dir}/scripts/bootstrap-terraform-s3-backend.sh" \
    || { signoz_internal_error "signoz-observability destroy failed"; return 1; }
}
