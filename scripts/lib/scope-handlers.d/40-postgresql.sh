#!/usr/bin/env bash
#
# PostgreSQL scope handler fragment — canonical wrappers only.
#
# Sources live-observations.sh, lifecycle-handlers.sh, and
# pre-destroy-guards.sh via the foundation-validated package-source helper.
# No verifier file is sourced here.
#
# Defines exactly the six canonical handler/guard wrapper symbols assigned
# by the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_postgresql_core_provision
#   scope_registry_deferred_postgresql_brand_provision
#   scope_registry_deferred_postgresql_core_destroy
#   scope_registry_deferred_postgresql_brand_destroy
#   scope_registry_pre_destroy_guard_postgresql_core
#   scope_registry_pre_destroy_guard_postgresql_brand
#
# database-access-core/database-access-brand remain deferred (work package
# 4) -- their own pre-destroy guard implementations also live in
# pre-destroy-guards.sh but are not registered here, since no
# database-access-core/brand provision/destroy handler exists yet.

source_package_internal_library "40-postgresql/internal/live-observations.sh" || return 1
source_package_internal_library "40-postgresql/internal/lifecycle-handlers.sh" || return 1
source_package_internal_library "40-postgresql/internal/pre-destroy-guards.sh" || return 1

scope_registry_deferred_postgresql_core_provision() { postgresql_internal_provision_postgresql_core "$@"; }
scope_registry_deferred_postgresql_brand_provision() { postgresql_internal_provision_postgresql_brand "$@"; }
scope_registry_deferred_postgresql_core_destroy() { postgresql_internal_destroy_postgresql_core "$@"; }
scope_registry_deferred_postgresql_brand_destroy() { postgresql_internal_destroy_postgresql_brand "$@"; }

scope_registry_pre_destroy_guard_postgresql_core() { postgresql_internal_postgresql_core_pre_destroy_guard "$@"; }
scope_registry_pre_destroy_guard_postgresql_brand() { postgresql_internal_postgresql_brand_pre_destroy_guard "$@"; }
