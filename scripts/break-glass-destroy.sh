#!/usr/bin/env bash
set -euo pipefail

# break-glass-destroy.sh -- deliberately outside scripts/destroy.sh
# ---------------------------------------------------------------------------
# Destroys ONE of the two scopes that scripts/destroy.sh permanently refuses
# to touch, by design (scripts/lib/scope-registry.sh:
# foundation_destroy_backend_blocked / foundation_destroy_access_governance_blocked):
#
#   backend            The single S3 bucket holding EVERY scope's Terraform
#                       state in the account (mongodb, eks-platform, signoz,
#                       access-governance, everything). Not "a resource" --
#                       the ledger that makes any of this scriptable at all.
#   access-governance   The account's AWS Access Analyzer -- an account-wide
#                       security/governance control, not application
#                       infrastructure. Meant to outlive any single
#                       environment's app-layer teardown.
#
# This script does NOT source scripts/lib/orchestrator.sh, scope-registry.sh,
# or any package fragment -- it is intentionally unreachable from
# `destroy.sh --env <env> <scope>`, no matter what scope string is passed,
# and immune to any future "all" scope accidentally including it. It reads
# only the plain config/environments/<env>.env contract file directly.
#
# MUST be run last, after every other scope in the environment has already
# been destroyed and re-verified empty:
#   - `backend` cannot be destroyed while any other scope's state still
#     lives in it -- doing so first would strand live AWS resources with no
#     Terraform state left to track or destroy them.
#   - `access-governance`'s Access Analyzer has no such technical
#     dependency, but this script treats both scopes the same way (last,
#     deliberate, audited) rather than special-casing which one is "more"
#     load-bearing.
#
# Confirmation ceremony (distinct from destroy.sh's --confirm/
# --confirmation-artifact two-pass protocol on purpose -- this is a
# different, rarer, higher-stakes action and should not share machinery
# that makes the routine path convenient):
#   1. --env <dev|uat|prod> and a scope (backend|access-governance) are
#      required positional-style flags.
#   2. --i-understand-this-is-irreversible must be passed literally.
#   3. The script then prompts interactively for the operator to TYPE BACK
#      (not just press enter/yes) the exact string
#      "destroy <scope> in <env> <account-id>", e.g.
#      "destroy backend in uat 672172129937". Anything else aborts.
#   4. Every invocation -- confirmed or aborted -- appends one JSON line to
#      .local/<env>/evidence/break-glass-destroy.log (created if absent),
#      recording who, what, when, and the outcome, before any destroy is
#      attempted. This is not the destroy-evidence.py schema used by the
#      orchestrator -- it is deliberately simpler and append-only, and is
#      never consumed by scripts/destroy.sh.
#
# Usage:
#   scripts/break-glass-destroy.sh --env uat --scope backend \
#     --i-understand-this-is-irreversible
#   scripts/break-glass-destroy.sh --env uat --scope access-governance \
#     --i-understand-this-is-irreversible

usage() {
  cat <<'EOF'
Usage:
  scripts/break-glass-destroy.sh --env <dev|uat|prod> --scope <backend|access-governance> --i-understand-this-is-irreversible

This script is NOT scripts/destroy.sh and is not reachable through it.
It destroys one of the two scopes scripts/destroy.sh permanently refuses
to touch: the Terraform state backend bucket, or the account's Access
Analyzer (access-governance). Both must be destroyed LAST, only after
every other scope in the environment has already been destroyed and
re-verified empty -- destroying the backend first would strand live AWS
resources with no Terraform state left to track or destroy them.

You will be asked to type back an exact confirmation phrase naming the
scope, environment, and account ID before anything runs.
EOF
}

_break_glass_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_break_glass_log() {
  local log_path="$1"
  local outcome="$2"
  local scope="$3"
  local environment="$4"
  local account_id="$5"
  local detail="$6"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$log_path")"
  printf '{"timestamp":"%s","operator":"%s","environment":"%s","scope":"%s","account_id":"%s","outcome":"%s","detail":"%s"}\n' \
    "$timestamp" "${USER:-unknown}" "$environment" "$scope" "$account_id" "$outcome" "$detail" \
    >> "$log_path"
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

environment=""
scope=""
acknowledged="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { _break_glass_error "--env requires a value"; exit 1; }
      environment="$2"
      shift 2
      ;;
    --scope)
      [[ $# -ge 2 ]] || { _break_glass_error "--scope requires a value"; exit 1; }
      scope="$2"
      shift 2
      ;;
    --i-understand-this-is-irreversible)
      acknowledged="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      _break_glass_error "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

case "$environment" in
  dev|uat|prod) ;;
  *)
    _break_glass_error "--env must be dev, uat, or prod, got: ${environment:-<empty>}"
    exit 1
    ;;
esac

case "$scope" in
  backend|access-governance) ;;
  *)
    _break_glass_error "--scope must be backend or access-governance, got: ${scope:-<empty>}"
    exit 1
    ;;
esac

if [[ "$acknowledged" != "true" ]]; then
  _break_glass_error "--i-understand-this-is-irreversible is required"
  exit 1
fi

env_file="${ROOT_DIR}/config/environments/${environment}.env"
[[ -r "$env_file" ]] || {
  _break_glass_error "environment contract file is not readable: ${env_file}"
  exit 1
}

# Deliberately not sourced through load_platform_env / environment-
# contracts.sh -- this script has no dependency on the orchestrator at all.
# shellcheck disable=SC1090
set -a
source "$env_file"
set +a

: "${EXPECTED_AWS_ACCOUNT_ID:?EXPECTED_AWS_ACCOUNT_ID must be set in ${env_file}}"
: "${AWS_REGION:?AWS_REGION must be set in ${env_file}}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set in ${env_file}}"
: "${TF_STATE_REGION:?TF_STATE_REGION must be set in ${env_file}}"

log_path="${ROOT_DIR}/.local/${environment}/evidence/break-glass-destroy.log"

live_account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || {
  _break_glass_error "unable to determine the current AWS caller identity; refusing to proceed"
  _break_glass_log "$log_path" "aborted:no-live-identity" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "aws sts get-caller-identity failed"
  exit 1
}

if [[ "$live_account_id" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  _break_glass_error "current AWS identity resolves to account ${live_account_id}, expected ${EXPECTED_AWS_ACCOUNT_ID} for --env ${environment}; refusing to proceed"
  _break_glass_log "$log_path" "aborted:account-mismatch" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "live account was ${live_account_id}"
  exit 1
fi

expected_phrase="destroy ${scope} in ${environment} ${EXPECTED_AWS_ACCOUNT_ID}"

# ---------------------------------------------------------------------------
# _break_glass_enumerate_components
# ---------------------------------------------------------------------------
#
# Lists exactly what will be destroyed for the named scope, read-only,
# before the confirmation prompt is ever shown -- mirrors the DESTROY
# PREVIEW pattern scripts/destroy.sh shows for every other scope
# (scripts/lib/enumerate-destroy-resources.sh), which this script
# deliberately does not share code with, but should give the operator the
# same "see it before you confirm it" guarantee.
_break_glass_enumerate_backend_components() {
  printf 'Live objects currently in s3://%s (region %s):\n' "$TF_STATE_BUCKET" "$TF_STATE_REGION"
  local listing
  listing="$(aws s3api list-objects-v2 \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" \
    --query 'Contents[].[Key,Size]' \
    --output text 2>/dev/null)" || listing=""
  if [[ -z "$listing" ]]; then
    printf '  (unable to list bucket contents, or bucket is already empty)\n'
  else
    printf '%s\n' "$listing" | while IFS=$'\t' read -r key size; do
      printf '  - %s (%s bytes)\n' "$key" "$size"
    done
  fi
  printf '\nThis bucket is the ONLY copy of Terraform state for every scope in this\naccount. Once deleted:\n'
  printf '  - Terraform loses all record of every AWS resource it ever created here\n'
  printf '    (EKS clusters, VPCs, IAM roles, KMS keys, RDS/Aurora instances, EFS,\n'
  printf '    backup vaults, MongoDB/Postgres prerequisites, SigNoz dashboards --\n'
  printf '    anything any scope in this repo ever provisioned).\n'
  printf '  - Any resource NOT already destroyed becomes an orphan: still running,\n'
  printf '    still billing, with no Terraform configuration able to plan, modify,\n'
  printf '    or destroy it again. Recovering from that means manually finding and\n'
  printf '    deleting every such resource by hand across the AWS console/CLI, or\n'
  printf '    re-importing each one into a fresh empty state file one at a time.\n'
  printf '  - There is no undo. S3 versioning on this bucket does not help --\n'
  printf '    deleting the bucket itself removes all versions and delete markers\n'
  printf '    with it; there is nothing left to roll back to.\n'
}

_break_glass_enumerate_access_governance_components() {
  local tf_dir="${ROOT_DIR}/platform-prerequisites/terraform/access-governance"
  printf 'Live resources currently tracked in the access-governance Terraform root:\n'
  if [[ -d "${tf_dir}/.terraform" ]] || [[ -f "${tf_dir}/.terraform.lock.hcl" ]]; then
    local state_list
    state_list="$(terraform -chdir="$tf_dir" state list 2>/dev/null)" || state_list=""
    if [[ -n "$state_list" ]]; then
      printf '%s\n' "$state_list" | sed 's/^/  - /'
    else
      printf '  (terraform state list returned nothing, or backend is not yet initialized here -- re-run after backend init to see the live list)\n'
    fi
  else
    printf '  (Terraform not yet initialized in this script'"'"'s process -- the AWS Access Analyzer resource, e.g. aws_accessanalyzer_analyzer.uat_account, is what this destroys)\n'
  fi
  printf '\nThis is the account'"'"'s AWS Access Analyzer -- a continuous, account-wide\nsecurity control that flags IAM policies, S3 bucket policies, KMS key\npolicies, and other resource policies granting unintended access to\nprincipals outside this account. Once deleted:\n'
  printf '  - The account loses ALL ongoing external-access findings immediately --\n'
  printf '    not just new ones going forward, but the entire finding history tied\n'
  printf '    to this analyzer.\n'
  printf '  - Any existing IAM/S3/KMS misconfiguration that was previously flagged\n'
  printf '    (or a new one introduced after this deletion) will go completely\n'
  printf '    undetected until a new analyzer is created and has run its own\n'
  printf '    baseline scan -- there is a real detection gap, not just a\n'
  printf '    configuration change.\n'
  printf '  - If any compliance/audit process depends on this analyzer existing\n'
  printf '    (SOC2, internal security review, etc.), removing it may itself be a\n'
  printf '    reportable control gap independent of anything it would have caught.\n'
}

cat <<EOF

═══════════════════════════════════════════════════════════════════════════
BREAK-GLASS DESTROY: ${scope} (environment: ${environment}, account: ${EXPECTED_AWS_ACCOUNT_ID})
═══════════════════════════════════════════════════════════════════════════

This is NOT the normal destroy.sh path. ${scope} is permanently excluded
from routine destroy tooling because:
$(if [[ "$scope" == "backend" ]]; then
  printf '  it is the S3 bucket (%s) holding every OTHER scope'"'"'s Terraform\n  state in this account. Destroying it while any other scope still has\n  live state pointed at it will strand real AWS resources with nothing\n  left to track or destroy them.\n' "$TF_STATE_BUCKET"
else
  printf '  it is the account'"'"'s AWS Access Analyzer -- a security/governance\n  control, not application infrastructure, meant to outlive any single\n  environment'"'"'s app-layer teardown.\n'
fi)

$(if [[ "$scope" == "backend" ]]; then
  _break_glass_enumerate_backend_components
else
  _break_glass_enumerate_access_governance_components
fi)

Before continuing, confirm every other scope in this environment has
already been destroyed and re-verified empty. This script does not check
that for you.

To proceed, type exactly the following phrase and press enter:

    ${expected_phrase}

Anything else aborts with no changes made.

EOF

printf 'Type the confirmation phrase: '
IFS= read -r typed_phrase || typed_phrase=""

if [[ "$typed_phrase" != "$expected_phrase" ]]; then
  _break_glass_error "confirmation phrase did not match; aborting with no changes made"
  _break_glass_log "$log_path" "aborted:phrase-mismatch" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "typed phrase did not match"
  exit 1
fi

_break_glass_log "$log_path" "confirmed" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "confirmation phrase matched; proceeding to destroy"

case "$scope" in
  backend)
    printf '\nDestroying S3 backend bucket %s (region %s)...\n' "$TF_STATE_BUCKET" "$TF_STATE_REGION"

    # A tfstate object continuing to exist as a KEY is expected even after
    # its scope is fully destroyed -- Terraform writes an empty state
    # document, it does not delete the object. Object-version count is
    # therefore the wrong signal (versioning means old versions/delete
    # markers accumulate forever and would permanently block this check).
    # What actually matters: does any CURRENT tfstate object still
    # describe live resources? access-governance.tfstate is excluded from
    # this check -- it is expected to still hold its own resource unless
    # the operator already ran this same script with --scope
    # access-governance first (order between the two scopes is the
    # operator's call; this script does not assume one).
    current_keys="$(aws s3api list-objects-v2 \
      --bucket "$TF_STATE_BUCKET" \
      --region "$TF_STATE_REGION" \
      --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" \
      --query 'Contents[].Key' \
      --output text 2>/dev/null)" || {
      _break_glass_error "unable to list objects in bucket ${TF_STATE_BUCKET}; refusing to proceed"
      _break_glass_log "$log_path" "aborted:bucket-list-failed" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "list-objects-v2 failed"
      exit 1
    }

    non_empty_state_keys=()
    state_check_tmpfile="$(mktemp)"
    for key in $current_keys; do
      case "$key" in
        *"access-governance.tfstate") continue ;;
        *.tfstate) ;;
        *) continue ;;
      esac
      resource_count="unknown"
      if aws s3api get-object \
        --bucket "$TF_STATE_BUCKET" \
        --region "$TF_STATE_REGION" \
        --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID" \
        --key "$key" "$state_check_tmpfile" >/dev/null 2>&1; then
        resource_count="$(python3 -c 'import json; print(len(json.load(open("'"$state_check_tmpfile"'")).get("resources", [])))' 2>/dev/null)" || resource_count="unknown"
      fi
      if [[ "$resource_count" != "0" ]]; then
        non_empty_state_keys+=("${key} (resources: ${resource_count})")
      fi
    done
    rm -f "$state_check_tmpfile"

    if [[ "${#non_empty_state_keys[@]}" -gt 0 ]]; then
      _break_glass_error "refusing to destroy the state bucket while these state files still describe live resources:"
      for key in "${non_empty_state_keys[@]}"; do
        _break_glass_error "  - ${key}"
      done
      _break_glass_log "$log_path" "aborted:bucket-not-empty" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "non-empty state files: ${non_empty_state_keys[*]}"
      exit 1
    fi

    aws s3 rm "s3://${TF_STATE_BUCKET}" --recursive --region "$TF_STATE_REGION"
    aws s3api delete-bucket \
      --bucket "$TF_STATE_BUCKET" \
      --region "$TF_STATE_REGION" \
      --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID"
    _break_glass_log "$log_path" "destroyed" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "bucket ${TF_STATE_BUCKET} deleted"
    printf 'Bucket %s deleted.\n' "$TF_STATE_BUCKET"
    ;;
  access-governance)
    tf_dir="${ROOT_DIR}/platform-prerequisites/terraform/access-governance"
    var_file="${tf_dir}/${environment}.tfvars"
    backend_bootstrap="${ROOT_DIR}/scripts/bootstrap-terraform-s3-backend.sh"
    [[ -d "$tf_dir" ]] || {
      _break_glass_error "access-governance Terraform root not found: ${tf_dir}"
      _break_glass_log "$log_path" "aborted:tf-dir-missing" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "missing ${tf_dir}"
      exit 1
    }
    [[ -r "$var_file" ]] || {
      _break_glass_error "no ${environment}.tfvars found for access-governance at ${var_file}; access-governance may never have been provisioned for this environment"
      _break_glass_log "$log_path" "aborted:tfvars-missing" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "missing ${var_file}"
      exit 1
    }
    [[ -x "$backend_bootstrap" ]] || {
      _break_glass_error "backend bootstrap script is not executable: ${backend_bootstrap}"
      _break_glass_log "$log_path" "aborted:bootstrap-script-missing" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "missing ${backend_bootstrap}"
      exit 1
    }
    printf '\nDestroying access-governance Terraform scope at %s...\n' "$tf_dir"
    "$backend_bootstrap" \
      --tf-dir "$tf_dir" \
      --bucket "$TF_STATE_BUCKET" \
      --region "$TF_STATE_REGION" \
      --key "${ACCESS_GOVERNANCE_STATE_KEY:-oms/${environment}/access-governance.tfstate}" \
      --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID"
    terraform -chdir="$tf_dir" destroy -input=false -auto-approve -var-file="$var_file"
    destroy_rc=$?
    if [[ "$destroy_rc" -ne 0 ]]; then
      _break_glass_log "$log_path" "failed" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "terraform destroy exited ${destroy_rc}"
      exit "$destroy_rc"
    fi
    _break_glass_log "$log_path" "destroyed" "$scope" "$environment" "${EXPECTED_AWS_ACCOUNT_ID}" "terraform destroy completed"
    printf 'access-governance destroyed.\n'
    ;;
esac

printf '\nDone. Audit entry recorded at %s\n' "$log_path"
