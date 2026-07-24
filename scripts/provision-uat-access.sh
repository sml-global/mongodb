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

AUTO_APPROVE_ARGS=()
if [[ $# -eq 2 ]]; then
  AUTO_APPROVE_ARGS=("--auto-approve")
fi

# This wrapper is temporary (owned by "Task 5: Supply Reviewed UAT Access
# Symbols To Unified Provisioning" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md)
# and contains no account, backend, Terraform, kubectl, lock, plan,
# generated-file, or cleanup logic of its own: it only maps its old scope
# grammar to the public unified provision command and forwards. Its removal
# is a handoff item for the post-UAT migration plan.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROVISION="$ROOT_DIR/scripts/provision.sh"

echo "DEPRECATED: use scripts/provision.sh --env uat <access-governance|eks-access>" >&2

case "$SCOPE" in
  governance)
    exec "$PROVISION" --env uat access-governance "${AUTO_APPROVE_ARGS[@]+"${AUTO_APPROVE_ARGS[@]}"}"
    ;;
  eks-access)
    exec "$PROVISION" --env uat eks-access "${AUTO_APPROVE_ARGS[@]+"${AUTO_APPROVE_ARGS[@]}"}"
    ;;
  all)
    # The old `all` expands to the two access scopes this script has always
    # owned; it does not forward to unified `--env uat all`, which correctly
    # includes the full platform and fails on deferred work package 3.
    "$PROVISION" --env uat access-governance "${AUTO_APPROVE_ARGS[@]+"${AUTO_APPROVE_ARGS[@]}"}"
    exec "$PROVISION" --env uat eks-access "${AUTO_APPROVE_ARGS[@]+"${AUTO_APPROVE_ARGS[@]}"}"
    ;;
esac