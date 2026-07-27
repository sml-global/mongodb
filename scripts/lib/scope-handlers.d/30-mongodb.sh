#!/usr/bin/env bash
#
# MongoDB scope handler fragment — canonical wrappers only.
#
# Sources lifecycle-handlers.sh exclusively via the foundation-validated
# package-source helper. No verifier or guard files are sourced here.
#
# Defines exactly the four canonical handler wrapper symbols assigned by
# the fixed registry (scripts/lib/scope-registry.sh):
#   scope_registry_deferred_mongodb_provision
#   scope_registry_deferred_mongodb_access_provision
#   scope_registry_deferred_mongodb_destroy
#   scope_registry_deferred_mongodb_access_destroy

source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh" || return 1

scope_registry_deferred_mongodb_provision() { mongodb_internal_provision_mongodb "$@"; }
scope_registry_deferred_mongodb_access_provision() { mongodb_internal_provision_mongodb_access "$@"; }
scope_registry_deferred_mongodb_destroy() { mongodb_internal_destroy_mongodb "$@"; }
scope_registry_deferred_mongodb_access_destroy() { mongodb_internal_destroy_mongodb_access "$@"; }
