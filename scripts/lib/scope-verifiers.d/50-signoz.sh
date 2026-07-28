#!/usr/bin/env bash
#
# SigNoz scope verifier fragment.
#
# Uses the foundation-validated package-source helper to source both
# SigNoz-owned mode-safe internal files, then defines the exact
# pre-mapped canonical verifier wrapper symbols assigned by the fixed
# registry (scripts/lib/scope-registry.sh's verification_handler_for_slot):
#   scope_registry_verify_signoz
#   scope_registry_verify_signoz_observability
#
# Also defines the foundation-pre-mapped guard wrapper symbols:
#   verify_signoz_pre_destroy
#   verify_signoz_observability_pre_destroy
#
# No registry mutation; catalog, graph, and guard mappings remain unchanged
# after this fragment is loaded. No lifecycle or handler symbols defined here.

source_package_internal_library "50-signoz/internal/verifiers.sh" || return 1
source_package_internal_library "50-signoz/internal/pre-destroy-guards.sh" || return 1

scope_registry_verify_signoz() { signoz_internal_signoz_verifier "$@"; }
scope_registry_verify_signoz_observability() { signoz_internal_signoz_observability_verifier "$@"; }

verify_signoz_pre_destroy() { signoz_internal_signoz_pre_destroy_guard "$@"; }
verify_signoz_observability_pre_destroy() { signoz_internal_signoz_observability_pre_destroy_guard "$@"; }
