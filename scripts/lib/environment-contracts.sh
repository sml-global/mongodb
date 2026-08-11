#!/usr/bin/env bash
#
# Immutable environment constants for the closed dev/uat contract.
#
# These values are compiled into this file, not read from process
# environment variables or from any dotenv file. `scripts/lib/platform-env.sh`
# uses `immutable_environment_value` to fail closed whenever a configurable
# dotenv value (config/environments/<env>.env) disagrees with the constant
# recorded here for that environment.
#
# Only this file's `case` statement may be edited to add or change an
# immutable binding; the parser in platform-env.sh contains no environment-
# specific values of its own.

immutable_environment_value() {
  local environment_name="${1:-}"
  local key_name="${2:-}"

  case "${environment_name}:${key_name}" in
    dev:EXPECTED_AWS_ACCOUNT_ID) printf '%s\n' '815402439714' ;;
    dev:AWS_REGION|dev:TF_STATE_REGION) printf '%s\n' 'ap-east-1' ;;
    dev:TF_STATE_PREFIX) printf '%s\n' 'oms/dev' ;;
    dev:PROMOTION_MODE) printf '%s\n' 'modeled' ;;
    uat:EXPECTED_AWS_ACCOUNT_ID) printf '%s\n' '672172129937' ;;
    uat:AWS_REGION|uat:TF_STATE_REGION) printf '%s\n' 'ap-east-1' ;;
    uat:TF_STATE_PREFIX) printf '%s\n' 'oms/uat' ;;
    uat:PROMOTION_MODE) printf '%s\n' 'uat-build' ;;
    uat:INFRA_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATInfraAdminEA_' ;;
    uat:APPLICATION_DEVELOPER_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATApplicationDeveloper_' ;;
    uat:BOOMI_ADMIN_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATBoomiAdmin_' ;;
    uat:PROCESS_OWNER_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATBoomiProcessOwner_' ;;
    prod:EXPECTED_AWS_ACCOUNT_ID) printf '%s\n' '632674123947' ;;
    prod:AWS_REGION|prod:TF_STATE_REGION) printf '%s\n' 'ap-east-1' ;;
    prod:TF_STATE_PREFIX) printf '%s\n' 'oms/prod' ;;
    prod:PROMOTION_MODE) printf '%s\n' 'uat-build' ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Destroy-handler forbidden-account guard (issue #95)
# ---------------------------------------------------------------------------
#
# mongodb/postgresql-core/postgresql-brand/signoz/signoz-observability's
# real destroy handlers (scripts/lib/packages/*/internal/lifecycle-handlers.sh)
# shell out to the frozen legacy dev-only destroy script, which always
# targets the DEV account/cluster/state -- it has no per-environment
# awareness of its own. Until each handler is rewritten to target its
# requested environment directly (mirroring eks-platform/workload-identity's
# per-environment tfvars + $ENVIRONMENT-aware handler pattern), those five
# handlers must refuse to run for any AWS account other than DEV's, or they
# would silently destroy DEV resources while the caller believes UAT/Prod is
# being targeted.
#
# This is expressed as a forbidden-account-ID list, not an environment-name
# comparison: the actual hazard is which AWS account gets mutated, and
# EXPECTED_AWS_ACCOUNT_ID (already resolved and validated by
# load_platform_env before any handler runs) is the direct, load-bearing
# signal for that -- not a derived $ENVIRONMENT string one step removed from
# it. Compiled in here (not config/environments/<env>.env) on purpose: this
# file is the one tier of configuration no dotenv edit can override, exactly
# like EXPECTED_AWS_ACCOUNT_ID itself above.
#
# `destroy_account_id_forbidden_for_legacy_shellout <account_id>` is the
# single source of truth callers use to decide this. Once a scope's
# legacy-shellout destroy handler is replaced by a real environment-aware
# rewrite, remove that scope's callsite entirely rather than adding an
# account to any allow-list here -- this list only ever names accounts the
# legacy shellout must never touch.
#
# The declare -p guard below (not a plain re-declaration) is required
# because this file is sourced more than once per process -- orchestrator.sh
# sources it directly, and platform-env.sh/platform-guards.sh each source it
# again -- and a bare `readonly` on a second source would abort the shell
# with "readonly variable" rather than silently redefining, unlike an
# ordinary function definition.

if ! declare -p _LEGACY_DESTROY_FORBIDDEN_ACCOUNT_IDS >/dev/null 2>&1; then
  readonly _LEGACY_DESTROY_FORBIDDEN_ACCOUNT_IDS=(
    "672172129937"  # UAT
    "632674123947"  # Production
  )
fi

destroy_account_id_forbidden_for_legacy_shellout() {
  local account_id="${1:-}"
  local forbidden_id

  for forbidden_id in "${_LEGACY_DESTROY_FORBIDDEN_ACCOUNT_IDS[@]}"; do
    if [[ "${account_id}" == "${forbidden_id}" ]]; then
      return 0
    fi
  done
  return 1
}
