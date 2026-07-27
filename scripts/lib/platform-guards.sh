#!/usr/bin/env bash
#
# Shared execution-environment, identity, Kubernetes context, and backend-
# contract guards used by every dev/uat environment orchestration entry
# point.
#
# Every function below assumes scripts/lib/platform-env.sh's
# `load_platform_env <dev|uat>` has already loaded and validated ENVIRONMENT,
# EXPECTED_AWS_ACCOUNT_ID, AWS_REGION, EKS_CLUSTER_NAME, TF_STATE_BUCKET,
# TF_STATE_REGION, TF_STATE_PREFIX, and the per-scope `*_STATE_KEY` variables
# into the process environment -- except `reject_execution_environment_overrides`,
# which is deliberately safe to call before any config is loaded (and must
# be called first, before `.local/` is created or any child command runs).
#
# This file contains no top-level execution.

_PLATFORM_GUARDS_LIBRARY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PLATFORM_GUARDS_SCRIPTS_DIR="$(cd "${_PLATFORM_GUARDS_LIBRARY_DIR}/.." && pwd)"

if [[ ! -r "${_PLATFORM_GUARDS_LIBRARY_DIR}/environment-contracts.sh" ]]; then
  printf 'ERROR: %s\n' "environment contracts library is not readable: ${_PLATFORM_GUARDS_LIBRARY_DIR}/environment-contracts.sh" >&2
  return 1 2>/dev/null || exit 1
fi
# shellcheck disable=SC1091
source "${_PLATFORM_GUARDS_LIBRARY_DIR}/environment-contracts.sh"

_platform_guards_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_platform_guards_require_environment_loaded() {
  local variable_name
  local required_variables=(
    ENVIRONMENT
    EXPECTED_AWS_ACCOUNT_ID
    AWS_REGION
    EKS_CLUSTER_NAME
    TF_STATE_BUCKET
    TF_STATE_REGION
    TF_STATE_PREFIX
  )

  for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
      _platform_guards_error "required platform environment variable is missing: ${variable_name}"
      return 1
    fi
  done

  case "$ENVIRONMENT" in
    dev|uat) ;;
    *)
      _platform_guards_error "ENVIRONMENT must be dev or uat, got: ${ENVIRONMENT}"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Execution-environment override guard
# ---------------------------------------------------------------------------
#
# Rejects every process-inherited variable that could redirect AWS account,
# profile, endpoint, Region, Kubernetes, or Terraform behavior. Ordinary AWS
# credential-process/session variables (AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, ...), PATH, terminal, and locale
# variables are deliberately left untouched.

reject_execution_environment_overrides() {
  local variable_name=""

  while IFS= read -r variable_name; do
    case "$variable_name" in
      AWS_ENDPOINT_URL|\
      AWS_ENDPOINT_URL_*|\
      AWS_S3_ENDPOINT|\
      AWS_STS_ENDPOINT|\
      AWS_CA_BUNDLE|\
      AWS_CONFIG_FILE|\
      AWS_SHARED_CREDENTIALS_FILE|\
      AWS_PROFILE|\
      AWS_DEFAULT_PROFILE|\
      AWS_REGION|\
      AWS_DEFAULT_REGION|\
      KUBECONFIG|\
      TF_CLI_CONFIG_FILE|\
      TF_PLUGIN_CACHE_DIR|\
      TF_REATTACH_PROVIDERS|\
      TF_CLI_ARGS*|\
      TF_VAR*|\
      TF_WORKSPACE|\
      TF_DATA_DIR)
        _platform_guards_error "execution environment override is not allowed: ${variable_name}"
        return 1
        ;;
    esac
  done < <(compgen -e)

  # Ignore endpoint_url and services settings from otherwise authorized
  # shared AWS profiles for every allowed child command.
  export AWS_IGNORE_CONFIGURED_ENDPOINT_URLS=true
}

# ---------------------------------------------------------------------------
# Identity and Region guard
# ---------------------------------------------------------------------------

verify_aws_identity_and_region() {
  local expected_account_id
  local expected_region
  local actual_account_id
  local configured_region

  _platform_guards_require_environment_loaded || return 1

  expected_account_id="$(immutable_environment_value "$ENVIRONMENT" EXPECTED_AWS_ACCOUNT_ID)" || {
    _platform_guards_error "unable to resolve the immutable account id contract for ${ENVIRONMENT}"
    return 1
  }
  expected_region="$(immutable_environment_value "$ENVIRONMENT" AWS_REGION)" || {
    _platform_guards_error "unable to resolve the immutable Region contract for ${ENVIRONMENT}"
    return 1
  }

  if [[ "$EXPECTED_AWS_ACCOUNT_ID" != "$expected_account_id" ]]; then
    _platform_guards_error "loaded ${ENVIRONMENT} config account is ${EXPECTED_AWS_ACCOUNT_ID}; expected ${expected_account_id}"
    return 1
  fi
  if [[ "$AWS_REGION" != "$expected_region" ]]; then
    _platform_guards_error "loaded ${ENVIRONMENT} config Region is ${AWS_REGION}; expected ${expected_region}"
    return 1
  fi

  if ! actual_account_id="$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)"; then
    _platform_guards_error "unable to read the active AWS account with sts get-caller-identity"
    return 1
  fi

  if [[ "$actual_account_id" != "$expected_account_id" ]]; then
    _platform_guards_error "active AWS account is ${actual_account_id}; expected ${expected_account_id} for ${ENVIRONMENT}"
    return 1
  fi

  # `aws configure get region` is used only as a consistency check when it
  # returns a non-empty value; STS is never called a second time.
  configured_region="$(aws configure get region 2>/dev/null || true)"
  if [[ -n "$configured_region" && "$configured_region" != "$expected_region" ]]; then
    _platform_guards_error "aws configure region is ${configured_region}; expected ${expected_region} for ${ENVIRONMENT}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Kubernetes context guard
# ---------------------------------------------------------------------------

verify_kubernetes_context() {
  local current_context
  local active_cluster_reference
  local expected_cluster_reference

  _platform_guards_require_environment_loaded || return 1

  if ! current_context="$(kubectl config current-context)"; then
    _platform_guards_error "unable to read the current Kubernetes context"
    return 1
  fi

  if ! active_cluster_reference="$(kubectl config view --minify -o 'jsonpath={.contexts[0].context.cluster}')"; then
    _platform_guards_error "unable to resolve the active cluster reference for Kubernetes context '${current_context}'"
    return 1
  fi

  # The canonical cluster reference -- not the context label -- controls
  # acceptance, so a relabeled context pointing at the right cluster is
  # accepted and a correctly labeled context pointing at the wrong cluster
  # is rejected.
  expected_cluster_reference="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
  if [[ "$active_cluster_reference" != "$expected_cluster_reference" ]]; then
    _platform_guards_error "current Kubernetes context '${current_context}' does not target ${ENVIRONMENT}; resolves to '${active_cluster_reference}'; expected '${expected_cluster_reference}'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# EKS authentication mode guard
# ---------------------------------------------------------------------------

verify_eks_authentication_mode() {
  local authentication_mode

  _platform_guards_require_environment_loaded || return 1

  if ! authentication_mode="$(aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"; then
    _platform_guards_error "unable to read EKS authentication mode for cluster '${EKS_CLUSTER_NAME}'"
    return 1
  fi

  case "$authentication_mode" in
    API|API_AND_CONFIG_MAP) ;;
    *)
      _platform_guards_error "EKS cluster '${EKS_CLUSTER_NAME}' authentication mode is '${authentication_mode:-empty}'; expected API or API_AND_CONFIG_MAP"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Backend contract guard
# ---------------------------------------------------------------------------
#
# Minimal scope -> state-key-variable mapping for the scopes that already
# have a `*_STATE_KEY` entry in config/environment-schema/base.manifest.
# "Task 3: Define The Permanent Unified Scope Registry And Fail-Closed
# Graph" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
# owns the permanent, exhaustive scope catalog and dependency graph
# (scripts/lib/scope-registry.sh); this mapping is intentionally limited to
# what this task needs and must be reconciled with that registry once it
# exists.

_platform_guards_state_key_variable_for_scope() {
  case "$1" in
    access-governance) printf '%s' "ACCESS_GOVERNANCE_STATE_KEY" ;;
    eks-platform) printf '%s' "EKS_PLATFORM_STATE_KEY" ;;
    eks-access) printf '%s' "EKS_ACCESS_STATE_KEY" ;;
    workload-identity) printf '%s' "WORKLOAD_IDENTITY_STATE_KEY" ;;
    mongodb) printf '%s' "MONGODB_STATE_KEY" ;;
    postgresql-core) printf '%s' "POSTGRESQL_CORE_STATE_KEY" ;;
    postgresql-brand) printf '%s' "POSTGRESQL_BRAND_STATE_KEY" ;;
    signoz-observability) printf '%s' "SIGNOZ_OBSERVABILITY_STATE_KEY" ;;
    *)
      return 1
      ;;
  esac
}

_platform_guards_bootstrap_backend() {
  local tf_dir="$1"
  local state_key="$2"
  local backend_bootstrap="${_PLATFORM_GUARDS_SCRIPTS_DIR}/bootstrap-terraform-s3-backend.sh"

  if [[ ! -x "$backend_bootstrap" ]]; then
    _platform_guards_error "backend bootstrap script is not executable: ${backend_bootstrap}"
    return 1
  fi

  "$backend_bootstrap" \
    --tf-dir "$tf_dir" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$state_key" \
    --expected-bucket-owner "$EXPECTED_AWS_ACCOUNT_ID"
}

validate_backend_contract_for_scope() {
  local scope_name="$1"
  local tf_dir="$2"
  local state_key_variable
  local state_key_value

  _platform_guards_require_environment_loaded || return 1

  state_key_variable="$(_platform_guards_state_key_variable_for_scope "$scope_name")" || {
    _platform_guards_error "unknown provisioning scope for backend contract validation: ${scope_name}"
    return 1
  }

  state_key_value="${!state_key_variable:-}"
  if [[ -z "$state_key_value" ]]; then
    _platform_guards_error "state key variable ${state_key_variable} is not set for scope ${scope_name}"
    return 1
  fi

  case "$state_key_value" in
    "${TF_STATE_PREFIX}/"*) ;;
    *)
      _platform_guards_error "state key ${state_key_value} for scope ${scope_name} is outside prefix ${TF_STATE_PREFIX}/"
      return 1
      ;;
  esac

  case "$state_key_value" in
    *..*)
      _platform_guards_error "state key ${state_key_value} for scope ${scope_name} must not contain .."
      return 1
      ;;
  esac

  # Bucket, Region, and expected owner come only from the loaded contract;
  # only the state key varies per scope, and only via the mapping above.
  _platform_guards_bootstrap_backend "$tf_dir" "$state_key_value"
}
