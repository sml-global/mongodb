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

# Save / restore the caller's INT+TERM trap disposition around a temporary
# source-patching trap.
#
# `_access_scopes_restore_signal_traps` clears the handler for the WHOLE shell, not just
# this function, so a patching site that cleared it also deleted the
# orchestrator's own INT/TERM handler (orchestrator.sh, single-pass destroy)
# for the remainder of the run -- after which a Ctrl-C leaked the
# orchestration lock instead of releasing it. These helpers restore exactly
# what was installed before, so the outer handler survives.
_access_scopes_save_signal_traps() {
  _ACCESS_SCOPES_SAVED_INT_TRAP="$(trap -p INT)"
  _ACCESS_SCOPES_SAVED_TERM_TRAP="$(trap -p TERM)"
}

_access_scopes_restore_signal_traps() {
  trap - EXIT
  if [[ -n "${_ACCESS_SCOPES_SAVED_INT_TRAP:-}" ]]; then
    eval "$_ACCESS_SCOPES_SAVED_INT_TRAP"
  else
    trap - INT
  fi
  if [[ -n "${_ACCESS_SCOPES_SAVED_TERM_TRAP:-}" ]]; then
    eval "$_ACCESS_SCOPES_SAVED_TERM_TRAP"
  else
    trap - TERM
  fi
  unset _ACCESS_SCOPES_SAVED_INT_TRAP _ACCESS_SCOPES_SAVED_TERM_TRAP
}

# Progress/status reporting. Kept on stderr alongside _access_scopes_error so
# stdout stays clean for command output, but labelled honestly: a successful
# destroy previously ended with three ERROR:-prefixed lines that all described
# things going right, which made a working teardown read as a failure (#161).
_access_scopes_info() {
  printf 'INFO: %s\n' "$*" >&2
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
# recheck have already passed (identity/region/context verified, no live
# drift since the pre-destroy guard ran) and, above that, only after the
# operator typed yes at the orchestrator's single-pass gate against a real
# enumerated resource list (UNIFIED_DESTROY_CONFIRMED).
#
# Lifting protections is therefore automatic here -- there are no
# --confirm-remove-protected / --confirm-disable-deletion-protection flags
# any more. Both lifts remain strictly CONDITIONAL on the resource actually
# being present and actually protected:
#
#   * live EKS deletionProtection is disabled only if the cluster still
#     exists and still has it enabled (an already-absent cluster or an
#     already-false flag is a success, not a failure);
#   * Terraform lifecycle.prevent_destroy is source-patched only for the
#     protected addresses actually present in this root's state and
#     actually declaring prevent_destroy = true.
#
# Both conditions matter: hardcoding module.efs[0] as mandatory, or
# unconditionally pushing deletion_protection=false, recreates the #159
# deadlock the moment one of those resources is already gone.
destroy_eks_platform_scope() {
  local var_file

  var_file="$(_eks_platform_var_file_for_environment)"
  [[ -r "$var_file" ]] || {
    _access_scopes_error "eks-platform tfvars file is not readable: ${var_file}"
    return 1
  }

  if [[ "${UNIFIED_DESTROY_CONFIRMED:-}" != "yes" ]]; then
    _access_scopes_error "eks-platform: destroy was not confirmed at the interactive typed-yes gate; refusing to destroy or to lift any protection"
    return 1
  fi

  provision_backend_scope "eks-platform" || return 1

  _eks_platform_disable_live_deletion_protection "$var_file" || return 1

  local -a protected_addresses=()
  local address_line
  while IFS= read -r address_line; do
    [[ -n "$address_line" ]] && protected_addresses+=("$address_line")
  done <<< "$(_eks_platform_present_protected_addresses "$EKS_PLATFORM_TF_DIR")"

  if [[ "${#protected_addresses[@]}" -eq 0 ]]; then
    _access_scopes_info "eks-platform: no prevent_destroy-protected resources are present in state; destroying without any source override"
    _run_terraform_destroy_or_report_prevent_destroy \
      "eks-platform" "$EKS_PLATFORM_TF_DIR" "$var_file"
    return $?
  fi

  _run_eks_platform_destroy_with_confirmed_overrides \
    "$EKS_PLATFORM_TF_DIR" "$var_file" "${protected_addresses[@]}"
}

# ---------------------------------------------------------------------------
# _eks_platform_present_protected_addresses <tf_dir>
# ---------------------------------------------------------------------------
#
# Prints, one per line, the resource addresses that are BOTH present in
# this root's Terraform state AND still declare lifecycle.prevent_destroy =
# true in their own source block. Prints nothing (status 0) when there are
# none -- an empty result is the normal, expected outcome on a stack whose
# protected resources have already been destroyed.
#
# Derived from live state rather than a hardcoded address list on purpose:
# a hardcoded `module.efs[0]...` entry fails as soon as EFS is gone, which
# is precisely the #159 deadlock. The module-file registry
# (_eks_platform_protected_resource_module_file) is still consulted, so an
# address whose module file is unknown is skipped rather than guessed at --
# Terraform will then refuse that resource explicitly and
# _run_terraform_destroy_or_report_prevent_destroy will name it.
_eks_platform_present_protected_addresses() {
  local tf_dir="$1"
  local state_addresses address parsed module_name resource_ref
  local resource_type resource_name module_file

  state_addresses="$(terraform -chdir="$tf_dir" state list 2>/dev/null)" || return 0

  while IFS= read -r address; do
    [[ -n "$address" ]] || continue
    parsed="$(_eks_platform_parse_module_resource_address "$address")" || continue
    module_name="$(printf '%s' "$parsed" | sed -n '1p')"
    resource_ref="$(printf '%s' "$parsed" | sed -n '2p')"
    resource_type="${resource_ref%%.*}"
    resource_name="${resource_ref#*.}"

    module_file="$(_eks_platform_protected_resource_module_file "$module_name")" || continue
    [[ -f "$module_file" ]] || continue

    if _eks_platform_resource_block_declares_prevent_destroy \
      "$module_file" "$resource_type" "$resource_name"; then
      printf '%s\n' "$address"
    fi
  done <<< "$state_addresses"
}

# Returns 0 when the named resource's own block in <module_file> contains
# `prevent_destroy = true`. Block-scoped (an awk brace-depth range), so a
# file holding several resources -- e.g. modules/kms/main.tf's cluster and
# backup keys -- is answered per resource rather than per file.
_eks_platform_resource_block_declares_prevent_destroy() {
  local module_file="$1"
  local resource_type="$2"
  local resource_name="$3"

  awk -v type="$resource_type" -v name="$resource_name" '
    BEGIN { in_block = 0; depth = 0; found = 0 }
    {
      if (!in_block && $0 ~ ("resource \"" type "\" \"" name "\" \\{")) {
        in_block = 1
        depth = 1
        next
      }
      if (in_block) {
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          if (c == "}") depth--
        }
        if ($0 ~ /prevent_destroy[[:space:]]*=[[:space:]]*true/) found = 1
        if (depth == 0) in_block = 0
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$module_file"
}

# ---------------------------------------------------------------------------
# _eks_platform_disable_live_deletion_protection
# ---------------------------------------------------------------------------
#
# The EKS cluster's `deletionProtection` is a live AWS API attribute (not a
# Terraform lifecycle block) -- AWS refuses DeleteCluster while it's true,
# independent of and in addition to Terraform's own lifecycle.prevent_destroy
# resources. eks-platform's own Terraform `check "eks_deletion_protection_
# required"` block (eks-platform/checks.tf) asserts deletion_protection must
# be true, but check blocks emit a warning, not a hard plan failure --
# confirmed via `terraform plan -var-file=<patched-tfvars>`, which completes
# cleanly and shows the intended `deletion_protection: true -> false`
# in-place update. The check exists as a provisioning-time signal (don't
# provision this stack without deletion protection), not a runtime
# assertion that blocks this narrow, explicitly-confirmed destroy-time
# override.
#
# Called unconditionally on a confirmed eks-platform destroy, and is itself
# responsible for doing nothing when there is nothing to do: an absent
# cluster and an already-false flag both return success without an apply.
# Backs up the tfvars file on disk, patches deletion_protection to
# false, applies -target=module.eks.aws_eks_cluster.this to push that one
# attribute live, restores the tfvars unconditionally via a trap on
# EXIT/INT/TERM (mirroring _run_eks_platform_destroy_with_confirmed_overrides
# in this same file), and leaves the caller's normal destroy flow to run
# next -- restoring the tfvars here does NOT re-enable deletion protection
# on the now-mid-destroy cluster; it only prevents a stale tfvars edit from
# lingering on disk after this function returns.
_eks_platform_disable_live_deletion_protection() {
  local var_file="$1"
  local backup_file="${var_file}.deletion_protection_override_backup"

  # AWS rejects UpdateClusterConfig as a no-op ("InvalidParameterException:
  # No changes needed") if deletionProtection is already false live --
  # which happens if a prior destroy attempt already disabled it before
  # failing on something else downstream (observed live in #142's UAT
  # teardown). Checking first avoids treating that as a fresh failure.
  #
  # The lookup's exit status is captured separately from its output: a
  # FAILED lookup (expired credentials, missing permission, wrong region,
  # cluster already gone) must never be silently treated as "protection is
  # still enabled" and fall through to the apply. Doing so is what produced
  # #158/#159 -- expired SSO credentials returned empty, empty != "False",
  # the apply ran anyway, and AWS rejected it as a no-op, deadlocking the
  # teardown. Fail closed with the real reason instead.
  local live_deletion_protection lookup_rc
  live_deletion_protection="$(aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.deletionProtection' \
    --output text 2>&1)"
  lookup_rc=$?

  if [[ "$lookup_rc" -ne 0 ]]; then
    # The cluster being already absent is a success for this step: there is
    # no live deletion protection left to disable, so the precondition this
    # function exists to establish is already satisfied.
    if printf '%s' "$live_deletion_protection" | grep -q 'ResourceNotFoundException'; then
      _access_scopes_info "eks-platform: cluster ${EKS_CLUSTER_NAME} no longer exists; no live deletion protection to disable"
      return 0
    fi
    _access_scopes_error "eks-platform: unable to determine live deletion-protection state for ${EKS_CLUSTER_NAME} (aws exit ${lookup_rc}): ${live_deletion_protection}"
    _access_scopes_error "eks-platform: refusing to attempt the disable apply without knowing the current state; fix the AWS call above and re-run"
    return 1
  fi

  # AWS CLI renders the boolean as True/False; accept either case.
  case "$live_deletion_protection" in
    False|false)
      _access_scopes_info "eks-platform: deletion protection is already disabled on the live cluster ; skipping the apply"
      return 0
      ;;
    True|true) ;;
    *)
      _access_scopes_error "eks-platform: unexpected live deletion-protection value for ${EKS_CLUSTER_NAME}: '${live_deletion_protection}'; refusing to guess"
      return 1
      ;;
  esac

  cp "$var_file" "$backup_file"

  _eks_platform_restore_deletion_protection_tfvars() {
    [[ -f "$backup_file" ]] || return 0
    cp "$backup_file" "$var_file"
    rm -f "$backup_file"
  }
  _access_scopes_save_signal_traps
  trap _eks_platform_restore_deletion_protection_tfvars EXIT INT TERM

  if ! grep -qE '^deletion_protection[[:space:]]*=[[:space:]]*true' "$var_file"; then
    _access_scopes_error "eks-platform: expected 'deletion_protection = true' in ${var_file}; refusing to patch an unexpected tfvars shape"
    _eks_platform_restore_deletion_protection_tfvars
    _access_scopes_restore_signal_traps
    return 1
  fi

  sed -i.bak -E 's/^deletion_protection([[:space:]]*=[[:space:]]*)true/deletion_protection\1false/' "$var_file"
  rm -f "${var_file}.bak"

  _access_scopes_info "eks-platform: applying deletion_protection=false to live cluster (confirmed at the interactive typed-yes gate); tfvars restored on any exit path, including interruption"

  terraform -chdir="$EKS_PLATFORM_TF_DIR" apply -input=false -auto-approve \
    -target=module.eks.aws_eks_cluster.this -var-file="$var_file"
  local apply_rc=$?

  _eks_platform_restore_deletion_protection_tfvars
  _access_scopes_restore_signal_traps
  _access_scopes_info "eks-platform: deletion_protection tfvars restored"

  if [[ "$apply_rc" -ne 0 ]]; then
    _access_scopes_error "eks-platform: failed to disable live deletion protection; destroy not attempted"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# _eks_platform_protected_resource_module_file /
# _eks_platform_parse_module_resource_address
# ---------------------------------------------------------------------------
#
# eks-platform has exactly 3 resources with lifecycle.prevent_destroy today
# (module.kms.aws_kms_key.cluster, module.kms.aws_kms_key.backup,
# module.efs[0].aws_efs_file_system.this -- see modules/kms/main.tf and
# modules/efs/main.tf). This is an explicit, hardcoded registry rather than
# a generic Terraform-address-to-file resolver: adding a new
# prevent_destroy resource anywhere in eks-platform requires updating this
# map, by design -- an override path that silently "discovers" newly
# protected resources in arbitrary files would be an unreviewed widening
# of what a destroy is allowed to unprotect.
_eks_platform_protected_resource_module_file() {
  local module_name="$1"
  case "$module_name" in
    kms) printf '%s/platform-prerequisites/terraform/modules/kms/main.tf' "$_ACCESS_SCOPES_ROOT_DIR" ;;
    efs) printf '%s/platform-prerequisites/terraform/modules/efs/main.tf' "$_ACCESS_SCOPES_ROOT_DIR" ;;
    *) return 1 ;;
  esac
}

# Parses a Terraform resource address (as printed in `has lifecycle.
# prevent_destroy set` errors and as listed by `terraform state list`)
# into its module name and `type.name` resource reference. Handles an
# optional module index, e.g. `module.efs[0].aws_efs_file_system.this` ->
# module_name=efs, resource_ref=aws_efs_file_system.this.
_eks_platform_parse_module_resource_address() {
  local address="$1"
  case "$address" in
    module.*)
      local remainder="${address#module.}"
      local module_name="${remainder%%.*}"
      module_name="${module_name%%\[*}"
      local resource_ref="${remainder#*.}"
      printf '%s\n%s\n' "$module_name" "$resource_ref"
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _run_eks_platform_destroy_with_confirmed_overrides
# ---------------------------------------------------------------------------
#
# For each still-protected, still-present address, resolves its module file and
# resource block, backs the file up to <file>.prevent_destroy_override_backup
# (an on-disk backup, not just an in-memory copy, so a restore is still
# possible after a SIGINT/SIGTERM/crash mid-destroy -- a trap registered
# below restores from these files on any exit path), flips that resource's
# `prevent_destroy = true` to `false` (scoped to the resource's own block
# via an awk address range, so a file with multiple protected resources --
# e.g. modules/kms/main.tf's cluster and backup keys -- only has the
# explicitly confirmed one(s) patched), runs the destroy, and restores every
# backed-up file before returning the destroy's real exit status. An
# address that doesn't resolve to a known module/resource aborts before any
# file is touched -- never silently skipped, never silently expanded to
# "disable everything in this file". Callers derive the address list from
# live state (_eks_platform_present_protected_addresses), never from a
# hardcoded list, so an already-destroyed protected resource simply does
# not appear here.
_run_eks_platform_destroy_with_confirmed_overrides() {
  local tf_dir="$1"
  local var_file="$2"
  shift 2
  local -a confirmed_addresses=("$@")

  local -a backup_files=()
  local address module_name resource_ref resource_type resource_name
  local module_file parsed

  _eks_platform_restore_prevent_destroy_backups() {
    local restore_file backup_file
    for restore_file in "${backup_files[@]}"; do
      backup_file="${restore_file}.prevent_destroy_override_backup"
      [[ -f "$backup_file" ]] || continue
      cp "$backup_file" "$restore_file"
      rm -f "$backup_file"
    done
  }
  _access_scopes_save_signal_traps
  trap _eks_platform_restore_prevent_destroy_backups EXIT INT TERM

  for address in "${confirmed_addresses[@]}"; do
    parsed="$(_eks_platform_parse_module_resource_address "$address")" || {
      _access_scopes_error "eks-platform: unrecognized protected resource address (expected module.<name>.<type>.<resource>): ${address}"
      return 1
    }
    module_name="$(printf '%s' "$parsed" | sed -n '1p')"
    resource_ref="$(printf '%s' "$parsed" | sed -n '2p')"
    resource_type="${resource_ref%%.*}"
    resource_name="${resource_ref#*.}"

    module_file="$(_eks_platform_protected_resource_module_file "$module_name")" || {
      _access_scopes_error "eks-platform: no known protected-resource module file for address: ${address} (module: ${module_name})"
      return 1
    }
    [[ -f "$module_file" ]] || {
      _access_scopes_error "eks-platform: protected-resource module file does not exist: ${module_file}"
      return 1
    }
    if ! grep -q "resource \"${resource_type}\" \"${resource_name}\"" "$module_file"; then
      _access_scopes_error "eks-platform: resource ${resource_type}.${resource_name} not found in ${module_file} (from protected resource address: ${address})"
      return 1
    fi

    if ! _orchestrator_in_list "$module_file" "${backup_files[@]:-}" 2>/dev/null; then
      backup_files+=("$module_file")
      cp "$module_file" "${module_file}.prevent_destroy_override_backup"
    fi

    # Patch from the file's CURRENT on-disk content, not the backup --
    # when two confirmed resources share a module file (e.g. both KMS
    # keys in modules/kms/main.tf), the second patch must build on the
    # first's edit, or it would silently discard it by rewriting from the
    # original content.
    local patched
    patched="$(awk -v type="$resource_type" -v name="$resource_name" '
      BEGIN { in_block = 0; depth = 0 }
      {
        if (!in_block && $0 ~ ("resource \"" type "\" \"" name "\" \\{")) {
          in_block = 1
          depth = 1
          print
          next
        }
        if (in_block) {
          for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") depth++
            if (c == "}") depth--
          }
          if ($0 ~ /prevent_destroy[[:space:]]*=[[:space:]]*true/) {
            gsub(/prevent_destroy[[:space:]]*=[[:space:]]*true/, "prevent_destroy = false")
          }
          print
          if (depth == 0) in_block = 0
          next
        }
        print
      }
    ' "$module_file")"
    printf '%s\n' "$patched" > "$module_file"
  done

  _access_scopes_info "eks-platform: temporarily disabling prevent_destroy for ${#confirmed_addresses[@]} still-protected resource(s) in ${#backup_files[@]} file(s) -- restored on any exit path, including interruption"

  local destroy_rc
  _run_terraform_destroy_or_report_prevent_destroy \
    "eks-platform" "$tf_dir" "$var_file"
  destroy_rc=$?

  _eks_platform_restore_prevent_destroy_backups
  _access_scopes_restore_signal_traps
  _access_scopes_info "eks-platform: prevent_destroy override restored on ${#backup_files[@]} file(s)"

  return "$destroy_rc"
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
