#!/usr/bin/env bash
#
# MongoDB lifecycle handler implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side mongodb_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.
#
# Reuses the same Terraform/kubectl runners the legacy dev path uses
# (scripts/provision-platform-prereq.sh, scripts/provision-k8s-components.sh),
# both parameterized by the ENVIRONMENT/TF_STATE_BUCKET/TF_STATE_REGION/
# MONGODB_STATE_KEY/MONGODB_NAMESPACE variables that load_platform_env
# (scripts/lib/platform-env.sh) already exports before this handler runs —
# no new orchestration logic is reimplemented here.
#
# CAUTION (see issue #95): the destroy handler below is NOT actually
# environment-aware yet — it shells out to the frozen, DEV-hardcoded
# legacy destroy script regardless of $ENVIRONMENT. It refuses to run
# whenever the resolved EXPECTED_AWS_ACCOUNT_ID is on the forbidden-account
# list in scripts/lib/environment-contracts.sh's
# destroy_account_id_forbidden_for_legacy_shellout (the single source of
# truth for this restriction) until it is rewritten to target the requested
# environment's own cluster/account/state, mirroring the provision-side
# environment-aware pattern already used by eks-platform/workload-identity.
# Do not remove this guard without that rewrite.

mongodb_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

mongodb_internal_provision_mongodb() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  bash "${root_dir}/scripts/provision-platform-prereq.sh" mongodb --auto-approve \
    || { mongodb_internal_error "mongodb Terraform prerequisites failed"; return 1; }
  bash "${root_dir}/scripts/provision-k8s-components.sh" mongodb \
    || { mongodb_internal_error "mongodb Kubernetes components failed"; return 1; }
}

mongodb_internal_provision_mongodb_access() {
  printf 'INFO: mongodb-access provision: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}

mongodb_internal_destroy_mongodb() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  if destroy_account_id_forbidden_for_legacy_shellout "${EXPECTED_AWS_ACCOUNT_ID:-}"; then
    mongodb_internal_error "mongodb destroy is not yet environment-aware (issue #95) — it would target the DEV-hardcoded legacy script regardless of the requested account. Refusing to run against forbidden AWS account ${EXPECTED_AWS_ACCOUNT_ID:-<unset>}."
    return 1
  fi

  bash "${root_dir}/scripts/legacy/dev/destroy.sh" mongodb --auto-approve \
    || { mongodb_internal_error "mongodb destroy failed"; return 1; }
}

mongodb_internal_destroy_mongodb_access() {
  printf 'INFO: mongodb-access destroy: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}
