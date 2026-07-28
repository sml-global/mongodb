#!/usr/bin/env bash
#
# PostgreSQL scope handler fragment — canonical wrappers only.
#
# Sources lifecycle-handlers.sh exclusively via the foundation-validated
# package-source helper. No verifier or guard files are sourced here.
#
# Defines exactly the four canonical handler wrapper symbols assigned by
# the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_postgresql_core_provision
#   scope_registry_deferred_postgresql_brand_provision
#   scope_registry_deferred_postgresql_core_destroy
#   scope_registry_deferred_postgresql_brand_destroy

source_package_internal_library "40-postgresql/internal/lifecycle-handlers.sh" || return 1

scope_registry_deferred_postgresql_core_provision() { postgresql_internal_provision_postgresql_core "$@"; }
scope_registry_deferred_postgresql_brand_provision() { postgresql_internal_provision_postgresql_brand "$@"; }
scope_registry_deferred_postgresql_core_destroy() { postgresql_internal_destroy_postgresql_core "$@"; }
scope_registry_deferred_postgresql_brand_destroy() { postgresql_internal_destroy_postgresql_brand "$@"; }
