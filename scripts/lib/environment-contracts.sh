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
    *) return 1 ;;
  esac
}
