#!/usr/bin/env bash

_platform_env_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_validate_required_platform_env() {
  local variable_name
  local required_variables=(
    ENVIRONMENT
    EXPECTED_AWS_ACCOUNT_ID
    AWS_REGION
    EKS_CLUSTER_NAME
    BOOMI_NAMESPACE
    TF_STATE_BUCKET
    TF_STATE_REGION
    ACCESS_GOVERNANCE_STATE_KEY
    EKS_ACCESS_STATE_KEY
  )

  for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
      _platform_env_error "required platform environment variable is missing: ${variable_name}"
      return 1
    fi
  done
}

_validate_uat_contract() {
  if [[ "$ENVIRONMENT" != "uat" ]]; then
    _platform_env_error "environment config must declare ENVIRONMENT=uat"
    return 1
  fi

  if [[ "$EXPECTED_AWS_ACCOUNT_ID" != "672172129937" ]]; then
    _platform_env_error "UAT config account is ${EXPECTED_AWS_ACCOUNT_ID}; expected 672172129937"
    return 1
  fi
}

load_platform_env() {
  local requested_environment="${1:-}"
  local library_dir
  local repository_root
  local environment_file
  local restore_allexport="false"

  if [[ "$requested_environment" != "uat" ]]; then
    _platform_env_error "load_platform_env accepts only uat"
    return 1
  fi

  library_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  repository_root="$(cd "$library_dir/../.." && pwd)" || return 1
  environment_file="$repository_root/config/environments/uat.env"

  if [[ ! -r "$environment_file" ]]; then
    _platform_env_error "UAT environment config is not readable: ${environment_file}"
    return 1
  fi

  if [[ $- == *a* ]]; then
    restore_allexport="true"
  else
    set -a
  fi

  # shellcheck disable=SC1090
  if ! source "$environment_file"; then
    if [[ "$restore_allexport" == "false" ]]; then
      set +a
    fi
    _platform_env_error "failed to load UAT environment config: ${environment_file}"
    return 1
  fi

  if [[ "$restore_allexport" == "false" ]]; then
    set +a
  fi

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1
}

verify_aws_identity() {
  local actual_account_id

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1

  if ! actual_account_id="$(aws sts get-caller-identity --query Account --output text)"; then
    _platform_env_error "unable to read the active AWS account with sts get-caller-identity"
    return 1
  fi

  if [[ "$actual_account_id" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
    _platform_env_error "active AWS account is ${actual_account_id}; expected 672172129937 for UAT"
    return 1
  fi
}

verify_kubernetes_context() {
  local current_context

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1

  if ! current_context="$(kubectl config current-context)"; then
    _platform_env_error "unable to read the current Kubernetes context"
    return 1
  fi

  if [[ "$current_context" != *"$EXPECTED_AWS_ACCOUNT_ID"* || "$current_context" != *"$EKS_CLUSTER_NAME"* ]]; then
    _platform_env_error "current Kubernetes context '${current_context}' does not target UAT account ${EXPECTED_AWS_ACCOUNT_ID} cluster ${EKS_CLUSTER_NAME}"
    return 1
  fi
}