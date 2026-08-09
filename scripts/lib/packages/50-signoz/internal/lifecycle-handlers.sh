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
# CAUTION (see issue #95): the destroy handlers below are NOT actually
# environment-aware yet — they shell out to the frozen, DEV-hardcoded
# legacy destroy script regardless of $ENVIRONMENT. They refuse to run
# whenever the resolved EXPECTED_AWS_ACCOUNT_ID is on the forbidden-account
# list in scripts/lib/environment-contracts.sh's
# destroy_account_id_forbidden_for_legacy_shellout (the single source of
# truth for this restriction) until rewritten to target the requested
# environment's own cluster/account/state. Do not remove this guard without
# that rewrite.

signoz_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

signoz_internal_provision_signoz() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  bash "${root_dir}/scripts/provision-k8s-components.sh" signoz \
    || { signoz_internal_error "signoz provision failed"; return 1; }
}

signoz_internal_destroy_signoz() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  if destroy_account_id_forbidden_for_legacy_shellout "${EXPECTED_AWS_ACCOUNT_ID:-}"; then
    signoz_internal_error "signoz destroy is not yet environment-aware (issue #95) — it would target the DEV-hardcoded legacy script regardless of the requested account. Refusing to run against forbidden AWS account ${EXPECTED_AWS_ACCOUNT_ID:-<unset>}."
    return 1
  fi

  bash "${root_dir}/scripts/legacy/dev/destroy.sh" signoz --auto-approve \
    || { signoz_internal_error "signoz destroy failed"; return 1; }
}

signoz_internal_provision_signoz_observability() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  TF_STATE_KEY="${SIGNOZ_OBSERVABILITY_STATE_KEY:-${TF_STATE_KEY:-}}" \
    bash "${root_dir}/scripts/provision-signoz-observability.sh" --auto-approve \
    || { signoz_internal_error "signoz-observability provision failed"; return 1; }
}

signoz_internal_destroy_signoz_observability() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  if destroy_account_id_forbidden_for_legacy_shellout "${EXPECTED_AWS_ACCOUNT_ID:-}"; then
    signoz_internal_error "signoz-observability destroy is not yet environment-aware (issue #95) — it would target the DEV-hardcoded legacy script regardless of the requested account. Refusing to run against forbidden AWS account ${EXPECTED_AWS_ACCOUNT_ID:-<unset>}."
    return 1
  fi

  bash "${root_dir}/scripts/legacy/dev/destroy.sh" signoz-observability --auto-approve \
    || { signoz_internal_error "signoz-observability destroy failed"; return 1; }
}
