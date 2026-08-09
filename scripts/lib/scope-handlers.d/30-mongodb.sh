#!/usr/bin/env bash
#
# MongoDB scope handler fragment — canonical wrappers only.
#
# Sources live-observations.sh, destroy-k8s.sh, lifecycle-handlers.sh, and
# pre-destroy-guards.sh via the foundation-validated package-source helper.
# No verifier file is sourced here.
#
# Defines exactly the six canonical handler/guard wrapper symbols assigned
# by the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_mongodb_provision
#   scope_registry_deferred_mongodb_access_provision
#   scope_registry_deferred_mongodb_destroy
#   scope_registry_deferred_mongodb_access_destroy
#   scope_registry_pre_destroy_guard_mongodb
#   scope_registry_pre_destroy_guard_mongodb_access

source_package_internal_library "30-mongodb/internal/live-observations.sh" || return 1
source_package_internal_library "30-mongodb/internal/destroy-k8s.sh" || return 1
source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh" || return 1
source_package_internal_library "30-mongodb/internal/pre-destroy-guards.sh" || return 1

scope_registry_deferred_mongodb_provision() { mongodb_internal_provision_mongodb "$@"; }
scope_registry_deferred_mongodb_access_provision() { mongodb_internal_provision_mongodb_access "$@"; }
scope_registry_deferred_mongodb_destroy() { mongodb_internal_destroy_mongodb "$@"; }
scope_registry_deferred_mongodb_access_destroy() { mongodb_internal_destroy_mongodb_access "$@"; }

scope_registry_pre_destroy_guard_mongodb() { mongodb_internal_mongodb_pre_destroy_guard "$@"; }
scope_registry_pre_destroy_guard_mongodb_access() { mongodb_internal_mongodb_access_pre_destroy_guard "$@"; }
