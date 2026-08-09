#!/usr/bin/env bash
#
# Pure, parameterized Terraform destroy helper shared across environment-
# aware destroy handlers (scripts/lib/packages/*/internal/lifecycle-handlers.sh).
#
# Every function here takes its environment's values as explicit arguments
# and returns/acts on exactly those -- no module-level or global variables
# carry state between calls. This is a hard requirement (see issue #111):
# a shared cache/global "current environment" value would reintroduce the
# same class of cross-environment hazard #95 found once already (a
# DEV-hardcoded shellout silently acting on the wrong account), just
# through a different mechanism. Never add a global here; if a caller
# needs a value twice, it passes it twice.
#
# This file does NOT modify or replace scripts/legacy/dev/destroy.sh, which
# stays frozen as the current DEV production path per CLAUDE.md. This is a
# net-new, independently callable library for the environment-aware
# handlers only.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_terraform_destroy_scope_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# terraform_destroy_scope_resolve_tfvars_file <tf_dir> <environment>
#
# Mirrors scripts/provision-platform-prereq.sh's own per-environment tfvars
# selection (terraform.<environment>.tfvars if present, else the plain
# terraform.tfvars) -- the destroy path must resolve tfvars identically to
# how that scope was provisioned, or a destroy could target the wrong
# variable set entirely.
terraform_destroy_scope_resolve_tfvars_file() {
  local tf_dir="$1"
  local environment="$2"

  if [[ -n "$environment" && -f "${tf_dir}/terraform.${environment}.tfvars" ]]; then
    printf 'terraform.%s.tfvars' "$environment"
  else
    printf 'terraform.tfvars'
  fi
}

# terraform_destroy_scope_ensure_tfvars <tf_dir> <tfvars_file>
#
# tfvars_file is a bare filename (e.g. "terraform.uat.tfvars"), resolved
# relative to tf_dir -- callers get it from
# terraform_destroy_scope_resolve_tfvars_file above.
terraform_destroy_scope_ensure_tfvars() {
  local tf_dir="$1"
  local tfvars_file="$2"
  local tfvars_path="${tf_dir}/${tfvars_file}"
  local sample_path="${tf_dir}/terraform.tfvars.sample"

  if [[ -f "$tfvars_path" ]]; then
    return 0
  fi

  _terraform_destroy_scope_error "missing required tfvars file: ${tfvars_path}"
  if [[ -f "$sample_path" ]]; then
    _terraform_destroy_scope_error "create it from sample and set required values: cp ${sample_path} ${tfvars_path}"
  fi
  return 1
}

# terraform_destroy_scope <tf_dir> <tf_state_key> <tf_state_bucket> <tf_state_region> <environment> <auto_approve> <bootstrap_backend_script>
#
# All seven arguments are required and explicit -- no fallback to any
# global/environment variable of the same name. Callers (the environment-
# aware lifecycle handlers) are responsible for reading their own already-
# exported orchestrator values (MONGODB_STATE_KEY, TF_STATE_BUCKET,
# TF_STATE_REGION, ENVIRONMENT, etc.) and passing them in explicitly.
terraform_destroy_scope() {
  local tf_dir="$1"
  local tf_state_key="$2"
  local tf_state_bucket="$3"
  local tf_state_region="$4"
  local environment="$5"
  local auto_approve="$6"
  local bootstrap_backend_script="$7"

  if [[ -z "$tf_dir" || -z "$tf_state_key" || -z "$tf_state_bucket" || -z "$tf_state_region" || -z "$bootstrap_backend_script" ]]; then
    _terraform_destroy_scope_error "terraform_destroy_scope requires tf_dir, tf_state_key, tf_state_bucket, tf_state_region, environment, auto_approve, and bootstrap_backend_script"
    return 1
  fi

  local tfvars_file
  tfvars_file="$(terraform_destroy_scope_resolve_tfvars_file "$tf_dir" "$environment")"

  terraform_destroy_scope_ensure_tfvars "$tf_dir" "$tfvars_file" || return 1

  "$bootstrap_backend_script" \
    --tf-dir "$tf_dir" \
    --bucket "$tf_state_bucket" \
    --region "$tf_state_region" \
    --key "$tf_state_key" \
    || return 1

  printf 'Destroying Terraform scope at %s (state key: %s)\n' "$tf_dir" "$tf_state_key"
  if [[ "$auto_approve" == "true" ]]; then
    terraform -chdir="$tf_dir" destroy -input=false -var-file="$tfvars_file" -auto-approve
  else
    terraform -chdir="$tf_dir" destroy -input=false -var-file="$tfvars_file"
  fi
}
