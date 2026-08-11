#!/usr/bin/env bash
#
# EKS platform verifier implementation.
#
# Owned by "Task 7: Define Canonical Component-Verifier Wrappers" in
# docs/superpowers/plans/2026-07-22-phase2-eks-platform.md.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "20-eks-platform/internal/verifiers.sh"
#
# Exports only distinct verifier-side eks_internal_* symbols. Never defines
# lifecycle, handler, pre-destroy-guard, or canonical registry wrapper
# symbols. Bash 3.2 compatible: no associative arrays, no declare -g, no
# namerefs. This file contains no top-level execution.

eks_internal_verifier_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# Derive the cluster ARN from the validated platform contract (in-memory env
# vars loaded by platform-env.sh). Rejects a missing or incompletely
# populated contract.
eks_internal_verifier_cluster_arn() {
  if [[ -n "${EKS_PLATFORM_IDENTITY:-}" ]]; then
    printf '%s' "${EKS_PLATFORM_IDENTITY}"
    return 0
  fi
  if [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" && -n "${EXPECTED_AWS_ACCOUNT_ID:-}" ]]; then
    printf 'arn:aws:eks:%s:%s:cluster/%s' "${AWS_REGION}" "${EXPECTED_AWS_ACCOUNT_ID}" "${EKS_CLUSTER_NAME}"
    return 0
  fi
  eks_internal_verifier_error "cluster ARN unavailable; EKS_PLATFORM_IDENTITY or (EKS_CLUSTER_NAME + AWS_REGION + EXPECTED_AWS_ACCOUNT_ID) required"
  return 1
}

# Confirms the cluster this contract describes actually exists and is
# ACTIVE, via a live `aws eks describe-cluster` call -- mirrors the same
# live-check pattern already used by verify_eks_authentication_mode
# (scripts/lib/platform-guards.sh). Without this, a verifier that only
# derives its expected ARN string from local config would PASS
# unconditionally regardless of whether the cluster is running, destroyed,
# or never provisioned (see #152: eks-platform/workload-identity/
# platform-controllers all reported PASS against a cluster confirmed gone
# via `aws eks describe-cluster` -> ResourceNotFoundException, in the same
# verify run where eks-authentication-mode correctly failed on that same
# missing cluster).
eks_internal_verifier_require_live_cluster() {
  [[ -n "${EKS_CLUSTER_NAME:-}" && -n "${AWS_REGION:-}" ]] || {
    eks_internal_verifier_error "EKS_CLUSTER_NAME and AWS_REGION are required to verify the live cluster"
    return 1
  }

  local cluster_status
  if ! cluster_status="$(aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.status' \
    --output text 2>/dev/null)"; then
    eks_internal_verifier_error "EKS cluster '${EKS_CLUSTER_NAME}' does not exist or is unreachable"
    return 1
  fi

  case "$cluster_status" in
    ACTIVE) ;;
    *)
      eks_internal_verifier_error "EKS cluster '${EKS_CLUSTER_NAME}' status is '${cluster_status:-empty}'; expected ACTIVE"
      return 1
      ;;
  esac
}

eks_internal_eks_platform_verifier() {
  local cluster_arn=""
  cluster_arn="$(eks_internal_verifier_cluster_arn)" || return 1
  eks_internal_verifier_require_live_cluster || return 1
  printf 'PASS: eks-platform cluster identity confirmed: %s\n' "$cluster_arn"
  return 0
}

eks_internal_workload_identity_verifier() {
  local cluster_arn=""
  cluster_arn="$(eks_internal_verifier_cluster_arn)" || return 1
  eks_internal_verifier_require_live_cluster || return 1
  printf 'PASS: workload-identity cluster identity confirmed: %s/workload-identity\n' "$cluster_arn"
  return 0
}

eks_internal_platform_controllers_verifier() {
  local cluster_arn=""
  cluster_arn="$(eks_internal_verifier_cluster_arn)" || return 1
  eks_internal_verifier_require_live_cluster || return 1
  printf 'PASS: platform-controllers cluster identity confirmed: %s/platform-controllers\n' "$cluster_arn"
  return 0
}
