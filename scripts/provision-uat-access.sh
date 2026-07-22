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

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_ENV_LIBRARY="$ROOT_DIR/scripts/lib/platform-env.sh"
BACKEND_BOOTSTRAP="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"
PRINCIPAL_VALIDATOR="$ROOT_DIR/scripts/validate-uat-workforce-principals.sh"
ACCESS_ROOT="$ROOT_DIR"

configure_access_root() {
  local requested_root="${UAT_ACCESS_TEST_ROOT:-}"
  local temp_root=""

  if [[ -z "$requested_root" ]]; then
    [[ "${UAT_ACCESS_TEST_MODE:-}" != "1" ]] || fail "UAT_ACCESS_TEST_MODE=1 requires UAT_ACCESS_TEST_ROOT"
    return 0
  fi

  [[ "${UAT_ACCESS_TEST_MODE:-}" == "1" ]] || fail "UAT_ACCESS_TEST_ROOT requires UAT_ACCESS_TEST_MODE=1"
  [[ "$requested_root" == /* ]] || fail "UAT_ACCESS_TEST_ROOT must be an absolute existing directory"
  [[ -d "$requested_root" ]] || fail "UAT_ACCESS_TEST_ROOT must be an absolute existing directory"

  requested_root="$(cd -- "$requested_root" && pwd -P)"
  temp_root="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
  if [[ "$requested_root" == "/" || "$requested_root" == "$ROOT_DIR" ||
        "$requested_root" == "$temp_root" || "$requested_root" != "$temp_root"/* ]]; then
    fail "UAT_ACCESS_TEST_ROOT must be a safe temporary directory below $temp_root"
  fi

  ACCESS_ROOT="$requested_root"
}

configure_access_root
PRINCIPAL_INPUT="$ACCESS_ROOT/config/environments/uat-workforce-principals.json"
GOVERNANCE_TF_DIR="$ACCESS_ROOT/platform-prerequisites/terraform/access-governance"
EKS_TF_DIR="$ACCESS_ROOT/platform-prerequisites/terraform/eks-access"
EKS_TFVARS="$EKS_TF_DIR/generated.auto.tfvars.json"
PLAN_NAME="uat-access.tfplan"
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
    ACTIVE_GENERATED_TFVARS=""
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
  local plan_path="$tf_dir/$PLAN_NAME"

  ACTIVE_PLAN="$plan_path"
  rm -f "$plan_path"
  terraform -chdir="$tf_dir" fmt -check -recursive
  terraform -chdir="$tf_dir" validate
  terraform -chdir="$tf_dir" plan -input=false -out="$PLAN_NAME" -var-file=uat.tfvars
  remove_generated_tfvars
  confirm_apply "$root_name"
  terraform -chdir="$tf_dir" apply -input=false "$PLAN_NAME"
  rm -f "$plan_path"
  ACTIVE_PLAN=""
}

provision_governance() {
  verify_aws_identity
  bootstrap_backend "$GOVERNANCE_TF_DIR" "$ACCESS_GOVERNANCE_STATE_KEY"
  run_terraform "$GOVERNANCE_TF_DIR"
}

provision_eks_access() {
  verify_aws_identity
  verify_kubernetes_context

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
    provision_governance
    ;;
  eks-access)
    provision_eks_access
    ;;
  all)
    provision_governance
    provision_eks_access
    ;;
esac