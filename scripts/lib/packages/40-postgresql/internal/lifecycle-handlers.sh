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
# postgresql_internal_destroy_postgresql_core()/_brand() are environment-
# aware (issue #111): they call scripts/lib/terraform-destroy-scope.sh's
# terraform_destroy_scope directly (the same shared helper mongodb's and
# signoz's destroy handlers use), rather than shelling out to the frozen,
# DEV-hardcoded scripts/legacy/dev/destroy.sh. Both scopes are Terraform-
# only (no in-cluster Kubernetes workload to tear down for Aurora), so
# unlike mongodb/signoz's destroy handlers there is no companion k8s
# teardown call here. That legacy script is never modified and keeps
# working unchanged for DEV's own `bash scripts/destroy.sh pg`/`pg-brand`
# (no --env) path.

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
  local environment="${ENVIRONMENT:?ENVIRONMENT must be set}"
  local tf_state_key="${POSTGRESQL_CORE_STATE_KEY:?POSTGRESQL_CORE_STATE_KEY must be set}"
  local tf_state_bucket="${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set}"
  local tf_state_region="${TF_STATE_REGION:?TF_STATE_REGION must be set}"

  terraform_destroy_scope \
    "${root_dir}/platform-prerequisites/terraform/postgresql-core" \
    "$tf_state_key" \
    "$tf_state_bucket" \
    "$tf_state_region" \
    "$environment" \
    "true" \
    "${root_dir}/scripts/bootstrap-terraform-s3-backend.sh" \
    || { postgresql_internal_error "postgresql-core Terraform destroy failed"; return 1; }
}

postgresql_internal_destroy_postgresql_brand() {
  local root_dir="${_ORCHESTRATOR_ROOT_DIR:?_ORCHESTRATOR_ROOT_DIR must be set}"
  local environment="${ENVIRONMENT:?ENVIRONMENT must be set}"
  local tf_state_key="${POSTGRESQL_BRAND_STATE_KEY:?POSTGRESQL_BRAND_STATE_KEY must be set}"
  local tf_state_bucket="${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set}"
  local tf_state_region="${TF_STATE_REGION:?TF_STATE_REGION must be set}"

  terraform_destroy_scope \
    "${root_dir}/platform-prerequisites/terraform/postgresql-brand" \
    "$tf_state_key" \
    "$tf_state_bucket" \
    "$tf_state_region" \
    "$environment" \
    "true" \
    "${root_dir}/scripts/bootstrap-terraform-s3-backend.sh" \
    || { postgresql_internal_error "postgresql-brand Terraform destroy failed"; return 1; }
}
