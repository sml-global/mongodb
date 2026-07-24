#!/usr/bin/env bash
#
# Foundation access verification fragment.
#
# Owned by "Task 5: Supply Reviewed UAT Access Symbols To Unified
# Provisioning" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md.
#
# Loads the same foundation-owned implementation library used by the
# handler fragment, then defines only the canonical access-readiness
# verifier symbols assigned by the fixed registry
# (scripts/lib/scope-registry.sh's `verification_handler_for_slot`):
# scope_registry_verify_backend, scope_registry_verify_access_governance,
# and scope_registry_verify_eks_access. No pre-destroy guard is assigned to
# this package by the registry (backend and access-governance have no
# pre-destroy guard slot at all, and eks-access's pre-destroy guard is
# mapped to a deferred external work package), so this fragment defines no
# guard symbol.

source_package_internal_library "10-foundation-access/internal/access-scopes.sh" || return 1

scope_registry_verify_backend() { verify_backend_scope_readiness "$@"; }
scope_registry_verify_access_governance() { verify_access_governance_scope_readiness "$@"; }
scope_registry_verify_eks_access() { verify_eks_access_scope_readiness "$@"; }
