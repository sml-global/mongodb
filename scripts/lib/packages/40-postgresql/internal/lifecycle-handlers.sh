#!/usr/bin/env bash
#
# PostgreSQL lifecycle handler implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "40-postgresql/internal/lifecycle-handlers.sh"
#
# Exports only distinct handler-side postgresql_internal_* symbols. Never
# defines verifier, pre-destroy-guard, or canonical registry wrapper symbols.
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.
#
# Reuses scripts/provision-platform-prereq.sh's pg-core/pg-brand scopes
# (both parameterized by the ENVIRONMENT/TF_STATE_BUCKET/TF_STATE_REGION/
# POSTGRESQL_CORE_STATE_KEY/POSTGRESQL_BRAND_STATE_KEY variables that
# load_platform_env already exports before this handler runs) — no new
# orchestration logic is reimplemented here. postgresql-brand has no
# associated Kubernetes workload today, so its handler is Terraform-only.
#
# Dev/SIT use self-managed CloudNativePG (independent core/brand Cluster CRs
# applied via gitops/postgresql-coredb/overlays/dev and
# gitops/postgresql-branddb/overlays/dev); UAT/Prod use AWS Aurora (fully
# managed, no in-cluster Cluster CR) — see
# docs/references/postgresql-platform-contract.md.
# The Kubernetes step below is therefore only run for dev/sit.
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

postgresql_internal_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

postgresql_internal_provision_postgresql_core() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  bash "${root_dir}/scripts/provision-platform-prereq.sh" pg-core --auto-approve \
    || { postgresql_internal_error "postgresql-core Terraform prerequisites failed"; return 1; }

  case "${ENVIRONMENT:-dev}" in
    dev|sit)
      bash "${root_dir}/scripts/provision-k8s-components.sh" postgresql \
        || { postgresql_internal_error "postgresql-core Kubernetes components failed"; return 1; }
      ;;
    *)
      printf 'INFO: postgresql-core is AWS-managed Aurora for %s — no in-cluster Cluster CR to apply.\n' "${ENVIRONMENT}"
      ;;
  esac
}

postgresql_internal_provision_postgresql_brand() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  bash "${root_dir}/scripts/provision-platform-prereq.sh" pg-brand --auto-approve \
    || { postgresql_internal_error "postgresql-brand Terraform prerequisites failed"; return 1; }
}

postgresql_internal_destroy_postgresql_core() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  if destroy_account_id_forbidden_for_legacy_shellout "${EXPECTED_AWS_ACCOUNT_ID:-}"; then
    postgresql_internal_error "postgresql-core destroy is not yet environment-aware (issue #95) — it would target the DEV-hardcoded legacy script regardless of the requested account. Refusing to run against forbidden AWS account ${EXPECTED_AWS_ACCOUNT_ID:-<unset>}."
    return 1
  fi

  bash "${root_dir}/scripts/legacy/dev/destroy.sh" pg --auto-approve \
    || { postgresql_internal_error "postgresql-core destroy failed"; return 1; }
}

postgresql_internal_destroy_postgresql_brand() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"

  if destroy_account_id_forbidden_for_legacy_shellout "${EXPECTED_AWS_ACCOUNT_ID:-}"; then
    postgresql_internal_error "postgresql-brand destroy is not yet environment-aware (issue #95) — it would target the DEV-hardcoded legacy script regardless of the requested account. Refusing to run against forbidden AWS account ${EXPECTED_AWS_ACCOUNT_ID:-<unset>}."
    return 1
  fi

  bash "${root_dir}/scripts/legacy/dev/destroy.sh" pg-brand --auto-approve \
    || { postgresql_internal_error "postgresql-brand destroy failed"; return 1; }
}
