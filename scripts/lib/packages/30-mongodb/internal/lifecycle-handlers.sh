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
# mongodb_internal_destroy_mongodb() is environment-aware (issue #111): it
# calls destroy-k8s.sh's mongodb_internal_destroy_k8s (parameterized
# Kubernetes teardown) and scripts/lib/terraform-destroy-scope.sh's
# terraform_destroy_scope (parameterized Terraform destroy) directly,
# rather than shelling out to the frozen, DEV-hardcoded
# scripts/legacy/dev/destroy.sh. That legacy script is never modified and
# keeps working unchanged for DEV's own `bash scripts/destroy.sh mongodb`
# (no --env) path.

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
  local namespace="${MONGODB_NAMESPACE:?MONGODB_NAMESPACE must be set}"
  local cluster_name="${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME must be set}"
  local aws_region="${AWS_REGION:?AWS_REGION must be set}"
  local environment="${ENVIRONMENT:?ENVIRONMENT must be set}"
  local tf_state_key="${MONGODB_STATE_KEY:?MONGODB_STATE_KEY must be set}"
  local tf_state_bucket="${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set}"
  local tf_state_region="${TF_STATE_REGION:?TF_STATE_REGION must be set}"

  mongodb_internal_destroy_k8s "$namespace" "$cluster_name" "$aws_region" "$root_dir" "$environment" \
    || { mongodb_internal_error "mongodb Kubernetes teardown failed"; return 1; }

  terraform_destroy_scope \
    "${root_dir}/platform-prerequisites/terraform/mongodb" \
    "$tf_state_key" \
    "$tf_state_bucket" \
    "$tf_state_region" \
    "$environment" \
    "true" \
    "${root_dir}/scripts/bootstrap-terraform-s3-backend.sh" \
    || { mongodb_internal_error "mongodb Terraform destroy failed"; return 1; }
}

mongodb_internal_destroy_mongodb_access() {
  printf 'INFO: mongodb-access destroy: namespace=%s\n' "${MONGODB_NAMESPACE:-mongodb}"
  return 0
}
