#!/usr/bin/env bash
#
# SigNoz scope handler fragment — canonical wrappers only.
#
# Sources live-observations.sh, destroy-k8s.sh, destroy-observability.sh,
# lifecycle-handlers.sh, and pre-destroy-guards.sh via the
# foundation-validated package-source helper. No verifier file is sourced
# here.
#
# Defines exactly the six canonical handler/guard wrapper symbols assigned
# by the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_signoz_provision
#   scope_registry_deferred_signoz_destroy
#   scope_registry_deferred_signoz_observability_provision
#   scope_registry_deferred_signoz_observability_destroy
#   scope_registry_pre_destroy_guard_signoz
#   scope_registry_pre_destroy_guard_signoz_observability

source_package_internal_library "50-signoz/internal/live-observations.sh" || return 1
source_package_internal_library "50-signoz/internal/destroy-k8s.sh" || return 1
source_package_internal_library "50-signoz/internal/destroy-observability.sh" || return 1
source_package_internal_library "50-signoz/internal/lifecycle-handlers.sh" || return 1
source_package_internal_library "50-signoz/internal/pre-destroy-guards.sh" || return 1

scope_registry_deferred_signoz_provision() { signoz_internal_provision_signoz "$@"; }
scope_registry_deferred_signoz_destroy() { signoz_internal_destroy_signoz "$@"; }
scope_registry_deferred_signoz_observability_provision() { signoz_internal_provision_signoz_observability "$@"; }
scope_registry_deferred_signoz_observability_destroy() { signoz_internal_destroy_signoz_observability "$@"; }

scope_registry_pre_destroy_guard_signoz() { signoz_internal_signoz_pre_destroy_guard "$@"; }
scope_registry_pre_destroy_guard_signoz_observability() { signoz_internal_signoz_observability_pre_destroy_guard "$@"; }
