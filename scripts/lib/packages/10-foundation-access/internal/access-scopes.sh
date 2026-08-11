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
EKS_PLATFORM_TF_DIR="${_ACCESS_SCOPES_ROOT_DIR}/platform-prerequisites/terraform/eks-platform"
WORKLOAD_IDENTITY_TF_DIR="${_ACCESS_SCOPES_ROOT_DIR}/platform-prerequisites/terraform/workload-identity"
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
    eks-platform) target_tf_dir="$EKS_PLATFORM_TF_DIR" ;;
    workload-identity) target_tf_dir="$WORKLOAD_IDENTITY_TF_DIR" ;;
    *)
      _access_scopes_error "provision_backend_scope accepts only access-governance, eks-access, eks-platform, or workload-identity, got: ${target_scope}"
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
# run_saved_terraform_plan <scope-name> <terraform-root> <var-file> [extra-var-file]
# ---------------------------------------------------------------------------
#
# Formats/validates the Terraform root, saves a plan to an environment-local
# path, prompts for (or auto-approves) apply, and applies the unchanged saved
# plan. The plan path is registered before creation so orchestrator traps
# clean it up on every failure.
run_saved_terraform_plan() {
  local scope_name="$1"
  local terraform_root="$2"
  local var_file="$3"
  local extra_var_file="${4:-}"
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
    -out="$plan_path" -var-file="$var_file" "${extra_var_file_args[@]+"${extra_var_file_args[@]}"}" || return 1

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
  run_saved_terraform_plan "access-governance" "$GOVERNANCE_TF_DIR" "uat.tfvars"
}

# ---------------------------------------------------------------------------
# _eks_platform_var_file_for_environment
# ---------------------------------------------------------------------------
#
# Per-environment tfvars for eks-platform live under
# platform-prerequisites/terraform/environments/<env>/eks-platform.tfvars
# (a different layout than access-governance/eks-access's in-directory
# uat.tfvars), because this root is also used by dev/prod, not only uat.
_eks_platform_var_file_for_environment() {
  printf '%s/platform-prerequisites/terraform/environments/%s/eks-platform.tfvars' \
    "${_ACCESS_SCOPES_ROOT_DIR}" "${ENVIRONMENT}"
}

# ---------------------------------------------------------------------------
# provision_eks_platform_scope
# ---------------------------------------------------------------------------
#
# Provisions the real EKS cluster (network, EKS, IAM, KMS, EFS, AWS Backup)
# for the current environment. Runs the two-phase OIDC bootstrap
# automatically on a from-scratch apply: the committed tfvars carries a
# placeholder cluster_oidc_issuer_url (the real value cannot exist before
# the cluster does); the first apply succeeds regardless since the OIDC
# provider resource only needs an explicit thumbprint, not URL
# reachability. Once the cluster exists, this reads the real issuer via
# `aws eks describe-cluster` and re-applies so the OIDC provider and every
# IRSA trust policy point at the correct issuer.
provision_eks_platform_scope() {
  local var_file
  local real_issuer
  local current_issuer

  var_file="$(_eks_platform_var_file_for_environment)"
  [[ -r "$var_file" ]] || {
    _access_scopes_error "eks-platform tfvars file is not readable: ${var_file}"
    return 1
  }

  provision_backend_scope "eks-platform" || return 1
  run_saved_terraform_plan "eks-platform" "$EKS_PLATFORM_TF_DIR" "$var_file" || return 1

  real_issuer="$(aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.identity.oidc.issuer' \
    --output text 2>/dev/null)" || {
    _access_scopes_error "unable to read the real OIDC issuer for cluster ${EKS_CLUSTER_NAME}"
    return 1
  }
  [[ -n "$real_issuer" && "$real_issuer" != "None" ]] || {
    _access_scopes_error "cluster ${EKS_CLUSTER_NAME} reported an empty OIDC issuer"
    return 1
  }

  current_issuer="$(rg -N 'cluster_oidc_issuer_url\s*=\s*"([^"]*)"' -r '$1' "$var_file")" || {
    _access_scopes_error "unable to read cluster_oidc_issuer_url from ${var_file}"
    return 1
  }

  if [[ "$current_issuer" == "$real_issuer" ]]; then
    return 0
  fi

  sed -i.bak "s#cluster_oidc_issuer_url = \"${current_issuer}\"#cluster_oidc_issuer_url = \"${real_issuer}\"#" "$var_file" || return 1
  rm -f "${var_file}.bak"

  run_saved_terraform_plan "eks-platform" "$EKS_PLATFORM_TF_DIR" "$var_file"
}

# ---------------------------------------------------------------------------
# destroy_eks_platform_scope
# ---------------------------------------------------------------------------
#
# Destroys the eks-platform Terraform root. Called only after
# eks_internal_eks_platform_destroy_handler's foundation guards and drift
# recheck have already passed (identity/region/context verified, backup
# retention/lock/deletion-protection confirmed, no live drift since the
# pre-destroy guard ran).
destroy_eks_platform_scope() {
  local var_file

  var_file="$(_eks_platform_var_file_for_environment)"
  [[ -r "$var_file" ]] || {
    _access_scopes_error "eks-platform tfvars file is not readable: ${var_file}"
    return 1
  }

  provision_backend_scope "eks-platform" || return 1
  _run_terraform_destroy_or_report_prevent_destroy \
    "eks-platform" "$EKS_PLATFORM_TF_DIR" "$var_file"
}

# ---------------------------------------------------------------------------
# _run_terraform_destroy_or_report_prevent_destroy
# ---------------------------------------------------------------------------
#
# Runs `terraform destroy` for a scope, streaming its output live, and on
# failure inspects that output for Terraform's `lifecycle.prevent_destroy`
# rejection ("Instance cannot be destroyed" / "has lifecycle.prevent_destroy
# set"). That specific failure means Terraform refused before mutating any
# state (see terraform-mode docs on prevent_destroy) -- distinct from every
# other destroy failure (auth, drift, provider errors), which this leaves
# to surface as-is. On a prevent_destroy hit, replaces the raw multi-block
# Terraform error dump with one clear, actionable summary naming every
# protected resource address found, per issue #145 (destroy wrapper gave no
# guidance when eks-platform's KMS keys / EFS filesystem blocked a full
# UAT teardown in #142 -- root cause was intentional prevent_destroy, not a
# bug, but the failure mode wasn't surfaced clearly).
_run_terraform_destroy_or_report_prevent_destroy() {
  local scope_name="$1"
  local tf_dir="$2"
  local var_file="$3"
  local output_file
  local destroy_rc

  output_file="$(mktemp)" || {
    _access_scopes_error "${scope_name}: unable to create temp file for destroy output capture"
    return 1
  }

  # A wide COLUMNS keeps each "Resource X has lifecycle.prevent_destroy
  # set" message on one line; Terraform otherwise wraps at the terminal
  # width, which breaks the resource-address parsing below. This does not
  # affect color -- the user's terminal still sees Terraform's normal
  # colored, live-streamed output via tee.
  COLUMNS=1000 terraform -chdir="$tf_dir" destroy -input=false -auto-approve -var-file="$var_file" 2>&1 | tee "$output_file"
  destroy_rc="${PIPESTATUS[0]}"

  if [[ "$destroy_rc" -ne 0 ]] && grep -q "has lifecycle.prevent_destroy set" "$output_file"; then
    local -a protected_addresses=()
    while IFS= read -r line; do
      protected_addresses+=("$line")
    done < <(grep -o 'Resource [^ ]* has$\|Resource [^ ]* has ' "$output_file" | sed -E 's/^Resource (.*) has ?$/\1/' | sort -u)

    _access_scopes_error "${scope_name}: destroy refused by Terraform's lifecycle.prevent_destroy guard on ${#protected_addresses[@]} resource(s); no state was changed:"
    local addr
    for addr in "${protected_addresses[@]}"; do
      _access_scopes_error "  - ${addr}"
    done
    _access_scopes_error "${scope_name}: this is a deliberate safety rail (see the module's main.tf), not a script defect. To proceed, explicitly remove prevent_destroy from the affected resource(s) as its own reviewed change, or destroy with -target to exclude them."
  fi

  rm -f "$output_file"
  return "$destroy_rc"
}

# ---------------------------------------------------------------------------
# _workload_identity_var_file_for_environment
# ---------------------------------------------------------------------------
#
# Same per-environment tfvars layout as eks-platform:
# platform-prerequisites/terraform/environments/<env>/workload-identity.tfvars
_workload_identity_var_file_for_environment() {
  printf '%s/platform-prerequisites/terraform/environments/%s/workload-identity.tfvars' \
    "${_ACCESS_SCOPES_ROOT_DIR}" "${ENVIRONMENT}"
}

# ---------------------------------------------------------------------------
# provision_workload_identity_scope
# ---------------------------------------------------------------------------
#
# Provisions the generic map-driven EKS Pod Identity root. The committed
# tfvars ship `identities = {}`, so a from-scratch apply creates zero
# identity resources today -- this wires the scope's Terraform lifecycle to
# the orchestrator; populating real identity entries is a data-owned change
# to the tfvars file, not a code change here.
provision_workload_identity_scope() {
  local var_file

  var_file="$(_workload_identity_var_file_for_environment)"
  [[ -r "$var_file" ]] || {
    _access_scopes_error "workload-identity tfvars file is not readable: ${var_file}"
    return 1
  }

  provision_backend_scope "workload-identity" || return 1
  run_saved_terraform_plan "workload-identity" "$WORKLOAD_IDENTITY_TF_DIR" "$var_file"
}

# ---------------------------------------------------------------------------
# destroy_workload_identity_scope
# ---------------------------------------------------------------------------
#
# Destroys the workload-identity Terraform root. Called only after
# eks_internal_workload_identity_destroy_handler's foundation guards and
# drift recheck have already passed.
destroy_workload_identity_scope() {
  local var_file

  var_file="$(_workload_identity_var_file_for_environment)"
  [[ -r "$var_file" ]] || {
    _access_scopes_error "workload-identity tfvars file is not readable: ${var_file}"
    return 1
  }

  provision_backend_scope "workload-identity" || return 1
  terraform -chdir="$WORKLOAD_IDENTITY_TF_DIR" destroy -input=false -auto-approve -var-file="$var_file"
}

# ---------------------------------------------------------------------------
# _platform_controllers_overlay_dir_for_environment
# ---------------------------------------------------------------------------
_platform_controllers_overlay_dir_for_environment() {
  printf '%s/gitops/platform-controllers/overlays/%s' \
    "${_ACCESS_SCOPES_ROOT_DIR}" "${ENVIRONMENT}"
}

# ---------------------------------------------------------------------------
# _bootstrap_flux_controllers
# ---------------------------------------------------------------------------
#
# Installs Flux's source/helm controllers via the same Helm chart and
# release name as the legacy dev-only flow's bootstrap_flux_controllers
# (scripts/provision-k8s-components.sh:261-269), so both paths converge on
# one Flux installation per cluster. Idempotent: `helm upgrade --install`
# is a no-op reconcile if Flux is already present and current.
_bootstrap_flux_controllers() {
  helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts >/dev/null || return 1
  helm repo update >/dev/null || return 1
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null || return 1
  helm upgrade --install flux2 fluxcd-community/flux2 -n flux-system
}

# ---------------------------------------------------------------------------
# provision_platform_controllers_scope
# ---------------------------------------------------------------------------
#
# platform-controllers is gitops/Flux-managed, not Terraform-owned: this
# scope has no *_STATE_KEY, matching how `mongodb`/`signoz`/`postgresql`
# already apply their gitops overlays directly via `kubectl apply -k`
# (scripts/provision-k8s-components.sh) rather than through a Terraform
# root. This follows that established, already-proven pattern -- Flux
# reconciles the applied manifests asynchronously after `kubectl apply`
# returns.
#
# Bootstraps Flux itself if its CRDs aren't already registered on the
# cluster, following the same self-sufficiency pattern as `apply_signoz` in
# provision-k8s-components.sh (which creates its own required Secret before
# applying rather than assuming it exists) -- see #41.
provision_platform_controllers_scope() {
  local overlay_dir

  overlay_dir="$(_platform_controllers_overlay_dir_for_environment)"
  [[ -d "$overlay_dir" ]] || {
    _access_scopes_error "platform-controllers overlay directory does not exist: ${overlay_dir}"
    return 1
  }

  verify_kubernetes_context || return 1
  verify_eks_authentication_mode || return 1

  if ! kubectl get crd helmreleases.helm.toolkit.fluxcd.io >/dev/null 2>&1 \
    || ! kubectl get crd helmrepositories.source.toolkit.fluxcd.io >/dev/null 2>&1; then
    _bootstrap_flux_controllers || {
      _access_scopes_error "failed to bootstrap Flux controllers for platform-controllers"
      return 1
    }
  fi

  kubectl apply -k "$overlay_dir"
}

# ---------------------------------------------------------------------------
# destroy_platform_controllers_scope
# ---------------------------------------------------------------------------
#
# Deletes the platform-controllers gitops overlay. Called only after
# eks_internal_platform_controllers_destroy_handler's foundation guards and
# drift recheck have already passed.
destroy_platform_controllers_scope() {
  local overlay_dir

  overlay_dir="$(_platform_controllers_overlay_dir_for_environment)"
  [[ -d "$overlay_dir" ]] || {
    _access_scopes_error "platform-controllers overlay directory does not exist: ${overlay_dir}"
    return 1
  }

  verify_kubernetes_context || return 1
  verify_eks_authentication_mode || return 1

  kubectl delete -k "$overlay_dir" --ignore-not-found
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
  run_saved_terraform_plan "eks-access" "$EKS_ACCESS_TF_DIR" "uat.tfvars" "$generated_tfvars"
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
  if ! aws s3api head-object \
    --bucket "$TF_STATE_BUCKET" \
    --key "$EKS_ACCESS_STATE_KEY" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" >/dev/null 2>&1; then
    _access_scopes_error "eks-access not provisioned (Terraform state not found: ${EKS_ACCESS_STATE_KEY})"
    return 1
  fi
}

verify_eks_platform_scope_readiness() {
  aws s3api head-object \
    --bucket "$TF_STATE_BUCKET" \
    --key "$EKS_PLATFORM_STATE_KEY" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" >/dev/null || return 1
  aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.status' \
    --output text 2>/dev/null | grep -qx "ACTIVE"
}
