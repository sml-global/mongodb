#!/usr/bin/env bash
#
# PostgreSQL scope verifier fragment.
#
# Uses the foundation-validated package-source helper to source both
# PostgreSQL-owned mode-safe internal files, then defines the exact
# pre-mapped canonical verifier wrapper symbols assigned by the fixed
# registry (scripts/lib/scope-registry.sh's verification_handler_for_slot):
#   scope_registry_verify_postgresql_core
#   scope_registry_verify_postgresql_brand
#
# Also defines the foundation-pre-mapped guard wrapper symbols:
#   verify_postgresql_core_pre_destroy
#   verify_postgresql_brand_pre_destroy
#
# No registry mutation; catalog, graph, and guard mappings remain unchanged
# after this fragment is loaded. No lifecycle or handler symbols defined here.

source_package_internal_library "40-postgresql/internal/verifiers.sh" || return 1
source_package_internal_library "40-postgresql/internal/pre-destroy-guards.sh" || return 1

scope_registry_verify_postgresql_core() { postgresql_internal_postgresql_core_verifier "$@"; }
scope_registry_verify_postgresql_brand() { postgresql_internal_postgresql_brand_verifier "$@"; }

verify_postgresql_core_pre_destroy() { postgresql_internal_postgresql_core_pre_destroy_guard "$@"; }
verify_postgresql_brand_pre_destroy() { postgresql_internal_postgresql_brand_pre_destroy_guard "$@"; }
