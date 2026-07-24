#!/usr/bin/env bash
#
# Foundation access-scope implementation library.
#
# Owned by "Task 5: Supply Reviewed UAT Access Symbols To Unified
# Provisioning" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md.
#
# This file is loaded only through
#   source_package_internal_library "10-foundation-access/internal/access-scopes.sh"
# from scripts/lib/scope-handlers.d/10-foundation-access.sh and
# scripts/lib/scope-verifiers.d/10-foundation-access.sh. scripts/lib/orchestrator.sh
# never sources it directly.
#
# By the time either fragment loads this file, orchestrator.sh has already
# sourced environment-contracts.sh, platform-env.sh, platform-guards.sh,
# orchestration-paths.sh, and scope-registry.sh, and `load_platform_env` has
# already populated ENVIRONMENT, EXPECTED_AWS_ACCOUNT_ID, AWS_REGION,
# EKS_CLUSTER_NAME, and every backend/state-key variable. Functions in this
# file that use `.local/<env>/...` paths (PLAN_DIR, GENERATED_DIR) are only
# ever invoked after `initialize_orchestration_paths` has completed, which is
# true for every real dispatch path.
#
# This library moves the following behaviors here, unchanged in intent, from
# the pre-unification scripts/provision-uat-access.sh:
#   provision_backend_scope
#   provision_access_governance_scope
#   verify_existing_eks_platform_dependency
#   provision_eks_access_scope
#   run_saved_terraform_plan
#   confirm_saved_plan_apply
#
# It does not broaden Terraform resources, providers, principals, policies,
# or state ownership; the two existing Terraform roots and their uat.tfvars
# are unchanged. It changes orchestration and generated-input location only.

_ACCESS_SCOPES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ACCESS_SCOPES_SCRIPTS_DIR="$(cd "${_ACCESS_SCOPES_LIB_DIR}/../../../.." && pwd)"
_ACCESS_SCOPES_ROOT_DIR="$(cd "${_ACCESS_SCOPES_SCRIPTS_DIR}/.." && pwd)"

GOVERNANCE_TF_DIR="${_ACCESS_SCOPES_ROOT_DIR}/platform-prerequisites/terraform/access-governance"
EKS_ACCESS_TF_DIR="${_ACCESS_SCOPES_ROOT_DIR}/platform-prerequisites/terraform/eks-access"
PRINCIPAL_VALIDATOR="${_ACCESS_SCOPES_SCRIPTS_DIR}/validate-uat-workforce-principals.sh"

# Once-per-orchestration-run memoization key for provision_backend_scope. Not
# reset between scopes on purpose: a single `provision.sh` invocation only
# ever needs one Terraform-owned scope's backend bootstrapped, no matter how
# many times provision_backend_scope is called during that run.
_ACCESS_SCOPES_BACKEND_BOOTSTRAPPED_FOR=""

_access_scopes_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_access_scopes_principal_input_path() {
  printf '%s/config/environments/%s.local/workforce-principals.json' \
    "${_ACCESS_SCOPES_ROOT_DIR}" "${ENVIRONMENT}"
}

# ---------------------------------------------------------------------------
# provision_backend_scope [scope-name]
# ---------------------------------------------------------------------------
#
# Idempotent, once-per-orchestration-run backend dependency handler. It
# validates/bootstraps the Terraform backend for the named scope (default
# "access-governance", the canonical form dispatched for the standalone
# "backend" registry scope) and records completion so the same scope's
# backend is never bootstrapped twice within one run. It does not create an
# EKS platform root.
provision_backend_scope() {
  local target_scope="${1:-access-governance}"
  local target_tf_dir=""

  case "$target_scope" in
    access-governance) target_tf_dir="$GOVERNANCE_TF_DIR" ;;
    eks-access) target_tf_dir="$EKS_ACCESS_TF_DIR" ;;
    *)
      _access_scopes_error "provision_backend_scope accepts only access-governance or eks-access, got: ${target_scope}"
      return 1
      ;;
  esac

  if [[ "$_ACCESS_SCOPES_BACKEND_BOOTSTRAPPED_FOR" == "$target_scope" ]]; then
    return 0
  fi

  validate_backend_contract_for_scope "$target_scope" "$target_tf_dir" || return 1
  _ACCESS_SCOPES_BACKEND_BOOTSTRAPPED_FOR="$target_scope"
}

# ---------------------------------------------------------------------------
# confirm_saved_plan_apply <scope-name>
# ---------------------------------------------------------------------------
#
# Requires an exact "yes" response before applying a saved plan, unless the
# orchestrator has set UNIFIED_AUTO_APPROVE=true for this run.
confirm_saved_plan_apply() {
  local scope_name="$1"
  local response=""

  if [[ "${UNIFIED_AUTO_APPROVE:-false}" == "true" ]]; then
    return 0
  fi

  printf "Apply saved Terraform plan for %s? Type 'yes' to continue: " "$scope_name"
  if ! IFS= read -r response || [[ "$response" != "yes" ]]; then
    _access_scopes_error "apply aborted for scope: ${scope_name}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# run_saved_terraform_plan <scope-name> <terraform-root> [extra-var-file]
# ---------------------------------------------------------------------------
#
# Formats/validates the Terraform root, saves a plan to an environment-local
# path, prompts for (or auto-approves) apply, and applies the unchanged saved
# plan. The plan path is registered before creation so orchestrator traps
# clean it up on every failure.
run_saved_terraform_plan() {
  local scope_name="$1"
  local terraform_root="$2"
  local extra_var_file="${3:-}"
  local plan_path
  local -a extra_var_file_args=()

  [[ -n "${PLAN_DIR:-}" ]] || {
    _access_scopes_error "orchestration paths are not initialized"
    return 1
  }

  plan_path="${PLAN_DIR}/${scope_name}.$$.tfplan"

  if [[ -n "$extra_var_file" ]]; then
    extra_var_file_args=(-var-file="$extra_var_file")
  fi

  register_orchestration_artifact "$plan_path" || return 1
  rm -f "$plan_path"

  terraform -chdir="$terraform_root" fmt -check -recursive || return 1
  terraform -chdir="$terraform_root" validate || return 1
  terraform -chdir="$terraform_root" plan -input=false \
    -out="$plan_path" -var-file=uat.tfvars "${extra_var_file_args[@]+"${extra_var_file_args[@]}"}" || return 1

  if [[ -n "$extra_var_file" ]]; then
    rm -f "$extra_var_file"
  fi

  confirm_saved_plan_apply "$scope_name" || return 1
  terraform -chdir="$terraform_root" apply -input=false "$plan_path"
}

# ---------------------------------------------------------------------------
# provision_access_governance_scope
# ---------------------------------------------------------------------------
provision_access_governance_scope() {
  provision_backend_scope "access-governance" || return 1
  run_saved_terraform_plan "access-governance" "$GOVERNANCE_TF_DIR"
}

# ---------------------------------------------------------------------------
# verify_existing_eks_platform_dependency
# ---------------------------------------------------------------------------
#
# Read-only pre-check that the UAT EKS cluster is reachable and configured
# the way eks-access Terraform expects, before any eks-access mutation.
# AWS identity is not re-verified here: the orchestrator has already verified
# it once, before dispatch, for the whole run.
verify_existing_eks_platform_dependency() {
  verify_kubernetes_context || return 1
  verify_eks_authentication_mode || return 1
}

# ---------------------------------------------------------------------------
# provision_eks_access_scope
# ---------------------------------------------------------------------------
provision_eks_access_scope() {
  local principal_input
  local generated_tfvars

  verify_existing_eks_platform_dependency || return 1

  principal_input="$(_access_scopes_principal_input_path)"
  [[ -r "$principal_input" ]] || {
    _access_scopes_error "UAT workforce principal input is not readable: ${principal_input}"
    return 1
  }
  [[ -x "$PRINCIPAL_VALIDATOR" ]] || {
    _access_scopes_error "principal validator is not executable: ${PRINCIPAL_VALIDATOR}"
    return 1
  }

  [[ -n "${GENERATED_DIR:-}" ]] || {
    _access_scopes_error "orchestration paths are not initialized"
    return 1
  }
  generated_tfvars="${GENERATED_DIR}/eks-access.$$.auto.tfvars.json"
  register_orchestration_artifact "$generated_tfvars" || return 1
  rm -f "$generated_tfvars"

  "$PRINCIPAL_VALIDATOR" --input "$principal_input" --output "$generated_tfvars" || return 1

  provision_backend_scope "eks-access" || return 1
  run_saved_terraform_plan "eks-access" "$EKS_ACCESS_TF_DIR" "$generated_tfvars"
}

# ---------------------------------------------------------------------------
# Read-only access-readiness verifiers
# ---------------------------------------------------------------------------
#
# These back the canonical `scope_registry_verify_backend`,
# `scope_registry_verify_access_governance`, and `scope_registry_verify_eks_access`
# symbols (scripts/lib/scope-verifiers.d/10-foundation-access.sh). They only
# read state; they never bootstrap, plan, or apply anything.

verify_backend_scope_readiness() {
  aws s3api head-bucket \
    --bucket "$TF_STATE_BUCKET" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" >/dev/null
}

verify_access_governance_scope_readiness() {
  aws s3api head-object \
    --bucket "$TF_STATE_BUCKET" \
    --key "$ACCESS_GOVERNANCE_STATE_KEY" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" >/dev/null
}

verify_eks_access_scope_readiness() {
  verify_existing_eks_platform_dependency || return 1
  aws s3api head-object \
    --bucket "$TF_STATE_BUCKET" \
    --key "$EKS_ACCESS_STATE_KEY" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" >/dev/null
}
