#!/usr/bin/env bash
#
# SigNoz scope handler fragment — canonical wrappers only.
#
# Sources lifecycle-handlers.sh exclusively via the foundation-validated
# package-source helper. No verifier or guard files are sourced here.
#
# Defines exactly the four canonical handler wrapper symbols assigned by
# the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_signoz_provision
#   scope_registry_deferred_signoz_destroy
#   scope_registry_deferred_signoz_observability_provision
#   scope_registry_deferred_signoz_observability_destroy

source_package_internal_library "50-signoz/internal/lifecycle-handlers.sh" || return 1

scope_registry_deferred_signoz_provision() { signoz_internal_provision_signoz "$@"; }
scope_registry_deferred_signoz_destroy() { signoz_internal_destroy_signoz "$@"; }
scope_registry_deferred_signoz_observability_provision() { signoz_internal_provision_signoz_observability "$@"; }
scope_registry_deferred_signoz_observability_destroy() { signoz_internal_destroy_signoz_observability "$@"; }
