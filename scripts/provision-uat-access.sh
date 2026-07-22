#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-uat-access.sh <governance|eks-access|all> [--auto-approve]

Scopes:
  governance  Apply UAT account access governance.
  eks-access  Apply UAT EKS workforce access after offline principal validation.
  all         Apply governance, then EKS access.

Without --auto-approve, each saved plan requires an exact 'yes' confirmation.
Terraform applies the saved plan without an additional approval flag.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

SCOPE="$1"
case "$SCOPE" in
  governance|eks-access|all) ;;
  *)
    usage >&2
    fail "unknown scope: $SCOPE"
    ;;
esac

if [[ $# -eq 2 && "$2" != "--auto-approve" ]]; then
  usage >&2
  fail "unknown argument: $2"
fi

AUTO_APPROVE="false"
if [[ $# -eq 2 ]]; then
  AUTO_APPROVE="true"
fi

reject_terraform_environment_overrides() {
  local variable_name=""

  while IFS= read -r variable_name; do
    case "$variable_name" in
      TF_CLI_ARGS|TF_CLI_ARGS_*|TF_VAR_*|TF_WORKSPACE|TF_DATA_DIR)
        fail "Terraform environment override is not allowed: $variable_name"
        ;;
    esac
  done < <(compgen -e)
}

reject_terraform_environment_overrides

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_ENV_LIBRARY="$ROOT_DIR/scripts/lib/platform-env.sh"
BACKEND_BOOTSTRAP="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"
PRINCIPAL_VALIDATOR="$ROOT_DIR/scripts/validate-uat-workforce-principals.sh"
PRINCIPAL_INPUT="$ROOT_DIR/config/environments/uat-workforce-principals.json"
GOVERNANCE_TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/access-governance"
EKS_TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/eks-access"
EKS_TFVARS="$EKS_TF_DIR/generated.auto.tfvars.json"
[[ "$PRINCIPAL_INPUT" != "$EKS_TFVARS" ]] || fail "principal input and generated Terraform output must be distinct"
LOCK_DIR="$ROOT_DIR/.uat-access.lock"
LOCK_HELD="false"
ACTIVE_PLAN=""
ACTIVE_GENERATED_TFVARS=""

cleanup() {
  local original_status=$?
  local cleanup_status=0

  trap - EXIT
  set +e
  if [[ -n "$ACTIVE_PLAN" ]]; then
    rm -f "$ACTIVE_PLAN"
    [[ $? -eq 0 ]] || cleanup_status=1
  fi
  if [[ -n "$ACTIVE_GENERATED_TFVARS" ]]; then
    rm -f "$ACTIVE_GENERATED_TFVARS"
    [[ $? -eq 0 ]] || cleanup_status=1
  fi
  if [[ "$LOCK_HELD" == "true" ]]; then
    rmdir "$LOCK_DIR"
    [[ $? -eq 0 ]] || cleanup_status=1
  fi

  if [[ $original_status -ne 0 ]]; then
    exit "$original_status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

[[ -r "$PLATFORM_ENV_LIBRARY" ]] || fail "platform environment library is not readable: $PLATFORM_ENV_LIBRARY"
# shellcheck disable=SC1090
source "$PLATFORM_ENV_LIBRARY"
load_platform_env uat

acquire_lock() {
  if ! mkdir "$LOCK_DIR"; then
    fail "another UAT access orchestration is running: $LOCK_DIR"
  fi
  LOCK_HELD="true"
}

bootstrap_backend() {
  local tf_dir="$1"
  local state_key="$2"

  [[ -x "$BACKEND_BOOTSTRAP" ]] || fail "backend bootstrap script is not executable: $BACKEND_BOOTSTRAP"
  "$BACKEND_BOOTSTRAP" \
    --tf-dir "$tf_dir" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$state_key"
}

remove_generated_tfvars() {
  if [[ -n "$ACTIVE_GENERATED_TFVARS" ]]; then
    rm -f "$ACTIVE_GENERATED_TFVARS"
  fi
}

confirm_apply() {
  local root_name="$1"
  local response=""

  if [[ "$AUTO_APPROVE" == "true" ]]; then
    return 0
  fi

  printf "Apply saved Terraform plan for %s? Type 'yes' to continue: " "$root_name"
  if ! IFS= read -r response || [[ "$response" != "yes" ]]; then
    fail "apply aborted for Terraform root: $root_name"
  fi
}

run_terraform() {
  local tf_dir="$1"
  local root_name="${tf_dir##*/}"
  local plan_name="uat-access.$$.tfplan"
  local plan_path="$tf_dir/$plan_name"

  ACTIVE_PLAN="$plan_path"
  rm -f "$plan_path"
  terraform -chdir="$tf_dir" fmt -check -recursive
  terraform -chdir="$tf_dir" validate
  terraform -chdir="$tf_dir" plan -input=false -out="$plan_name" -var-file=uat.tfvars
  remove_generated_tfvars
  confirm_apply "$root_name"
  terraform -chdir="$tf_dir" apply -input=false "$plan_name"
  rm -f "$plan_path"
  ACTIVE_PLAN=""
}

provision_governance() {
  bootstrap_backend "$GOVERNANCE_TF_DIR" "$ACCESS_GOVERNANCE_STATE_KEY"
  run_terraform "$GOVERNANCE_TF_DIR"
}

provision_eks_access() {
  ACTIVE_GENERATED_TFVARS="$EKS_TFVARS"
  rm -f "$EKS_TFVARS"
  [[ -r "$PRINCIPAL_INPUT" ]] || fail "UAT workforce principal input is not readable: $PRINCIPAL_INPUT"
  [[ -x "$PRINCIPAL_VALIDATOR" ]] || fail "principal validator is not executable: $PRINCIPAL_VALIDATOR"
  "$PRINCIPAL_VALIDATOR" --input "$PRINCIPAL_INPUT" --output "$EKS_TFVARS"

  bootstrap_backend "$EKS_TF_DIR" "$EKS_ACCESS_STATE_KEY"
  run_terraform "$EKS_TF_DIR"
}

case "$SCOPE" in
  governance)
    verify_aws_identity
    acquire_lock
    provision_governance
    ;;
  eks-access)
    verify_aws_identity
    verify_kubernetes_context
    verify_eks_authentication_mode
    acquire_lock
    provision_eks_access
    ;;
  all)
    verify_aws_identity
    verify_kubernetes_context
    verify_eks_authentication_mode
    acquire_lock
    provision_governance
    provision_eks_access
    ;;
esac