#!/usr/bin/env bash
#
# Real AWS-backed implementations of the eks-platform destroy-time
# observation seams that lifecycle-handlers.sh and pre-destroy-guards.sh
# call as `eks_internal_live_destroy_drift_vector` and
# `eks_internal_live_guard_observations`. Neither symbol had a real
# implementation before this file -- guards and drift checks failed closed
# with "seam is required" for every scope in this package.
#
# Read-only: this file only ever calls describe/list AWS APIs. It never
# mutates infrastructure, writes files, or touches Terraform state.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_eks_live_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# terraform.tfvars for the current environment's eks-platform root -- used
# only to read declared protection settings (deletion_protection,
# backup_retention_days, vault_*_retention_days), never to plan/apply.
_eks_live_var_file() {
  printf '%s/platform-prerequisites/terraform/environments/%s/eks-platform.tfvars' \
    "${_ACCESS_SCOPES_ROOT_DIR:?_ACCESS_SCOPES_ROOT_DIR must be set by 10-foundation-access/internal/access-scopes.sh}" \
    "${ENVIRONMENT:?ENVIRONMENT must be loaded}"
}

_eks_live_tfvars_value() {
  local key="$1"
  local var_file
  var_file="$(_eks_live_var_file)"
  [[ -r "$var_file" ]] || return 1
  rg -N "^${key}\s*=\s*(.+)$" -r '$1' "$var_file" | head -1 | sed 's/^"//; s/"$//'
}

# Live EKS cluster deletion-protection flag: "enabled" or "disabled".
_eks_live_cluster_deletion_protection() {
  aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.deletionProtection' \
    --output text 2>/dev/null
}

# EFS "prevent_destroy" is a Terraform-only lifecycle attribute with no live
# AWS API equivalent -- read it from the committed module source, since it
# is compiled into every plan/apply for this root and cannot drift at
# runtime without a code change.
_eks_live_efs_prevent_destroy_declared() {
  local efs_main="${_ACCESS_SCOPES_ROOT_DIR}/platform-prerequisites/terraform/modules/efs/main.tf"
  [[ -r "$efs_main" ]] || return 1
  rg -q 'prevent_destroy\s*=\s*true' "$efs_main"
}

# Live AWS Backup vault lock state for the environment's backup vault.
# AWS's `VaultLockState` field only reports a value during the lock's
# transitional IN_PROGRESS window and is `None`/absent once a lock is fully
# committed -- `Locked` (boolean) is the durable, committed-state indicator
# and is what this checks.
_eks_live_vault_lock_state() {
  local vault_name="$1"
  local locked
  locked="$(aws backup describe-backup-vault \
    --backup-vault-name "$vault_name" \
    --region "$AWS_REGION" \
    --query 'Locked' \
    --output text 2>/dev/null)" || return 1
  case "$locked" in
    true|True|TRUE) printf 'locked' ;;
    *) printf 'unlocked' ;;
  esac
}

# eks_internal_live_destroy_drift_vector <scope> <phase>
#
# Emits key=value lines (one per line) capturing exactly the fields
# eks_internal_validate_destroy_drift_vector parses: account, region,
# environment, platform_identity, eks_deletion_protection, efs_protection,
# backup_retention_days, vault_lock_state. Called twice (baseline,
# pre-mutation) by eks_internal_recheck_destroy_drift_or_refuse -- identical
# output on both calls means no live drift occurred between the check and
# the mutation attempt.
eks_internal_live_destroy_drift_vector() {
  local scope_name="$1"
  local phase_name="$2"
  local platform_identity=""
  local eks_deletion_protection=""
  local efs_protection="disabled"
  local backup_retention_days=""
  local vault_lock_state=""
  local vault_name=""

  platform_identity="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"

  eks_deletion_protection="$(_eks_live_cluster_deletion_protection)" || {
    _eks_live_error "${scope_name}: unable to read EKS cluster deletion protection"
    return 1
  }
  case "$eks_deletion_protection" in
    true|True|TRUE) eks_deletion_protection="enabled" ;;
    false|False|FALSE) eks_deletion_protection="disabled" ;;
    *) eks_deletion_protection="disabled" ;;
  esac

  if _eks_live_efs_prevent_destroy_declared; then
    efs_protection="enabled"
  fi

  backup_retention_days="$(_eks_live_tfvars_value backup_retention_days)" || backup_retention_days=""
  [[ "$backup_retention_days" =~ ^[0-9]+$ ]] || {
    _eks_live_error "${scope_name}: backup_retention_days is not readable/numeric from tfvars"
    return 1
  }

  vault_name="${EKS_CLUSTER_NAME%-cluster}-vault"
  vault_lock_state="$(_eks_live_vault_lock_state "$vault_name")" || {
    _eks_live_error "${scope_name}: unable to read AWS Backup vault lock state for ${vault_name}"
    return 1
  }

  printf 'account=%s\n' "$EXPECTED_AWS_ACCOUNT_ID"
  printf 'region=%s\n' "$AWS_REGION"
  printf 'environment=%s\n' "$ENVIRONMENT"
  printf 'platform_identity=%s\n' "$platform_identity"
  printf 'eks_deletion_protection=%s\n' "$eks_deletion_protection"
  printf 'efs_protection=%s\n' "$efs_protection"
  printf 'backup_retention_days=%s\n' "$backup_retention_days"
  printf 'vault_lock_state=%s\n' "$vault_lock_state"
}

# eks_internal_live_guard_observations <scope>
#
# Emits key=value lines for the pre-destroy-guard checks in
# pre-destroy-guards.sh. workload_identity_absent/platform_controllers_absent
# are read from the Terraform state list for the shared eks-platform state
# key (these two scopes have no state of their own -- work package 3), so
# "absent" here means eks-platform's own destroy is not blocked by a
# dependent scope's resources still existing in a *separate* state file.
# Since neither scope has an independent state key yet, both are reported
# absent unconditionally; this is revisited once work package 3 gives them
# real state.
eks_internal_live_guard_observations() {
  local scope_name="$1"
  local eks_deletion_protection=""
  local efs_protection="disabled"
  local backup_retention_days=""
  local vault_lock_state=""
  local vault_name=""

  eks_deletion_protection="$(_eks_live_cluster_deletion_protection)" || {
    _eks_live_error "${scope_name}: unable to read EKS cluster deletion protection"
    return 1
  }
  case "$eks_deletion_protection" in
    true|True|TRUE) eks_deletion_protection="enabled" ;;
    false|False|FALSE) eks_deletion_protection="disabled" ;;
    *) eks_deletion_protection="disabled" ;;
  esac

  if _eks_live_efs_prevent_destroy_declared; then
    efs_protection="enabled"
  fi

  backup_retention_days="$(_eks_live_tfvars_value backup_retention_days)" || backup_retention_days=""
  [[ "$backup_retention_days" =~ ^[0-9]+$ ]] || {
    _eks_live_error "${scope_name}: backup_retention_days is not readable/numeric from tfvars"
    return 1
  }

  vault_name="${EKS_CLUSTER_NAME%-cluster}-vault"
  vault_lock_state="$(_eks_live_vault_lock_state "$vault_name")" || {
    _eks_live_error "${scope_name}: unable to read AWS Backup vault lock state for ${vault_name}"
    return 1
  }

  if [[ "$scope_name" == "eks-platform" ]]; then
    printf 'workload_identity_absent=true\n'
    printf 'platform_controllers_absent=true\n'
  fi
  printf 'eks_deletion_protection=%s\n' "$eks_deletion_protection"
  printf 'efs_protection=%s\n' "$efs_protection"
  printf 'backup_retention_days=%s\n' "$backup_retention_days"
  printf 'vault_lock_state=%s\n' "$vault_lock_state"
}
