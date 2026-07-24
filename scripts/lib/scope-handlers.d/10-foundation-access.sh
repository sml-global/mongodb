#!/usr/bin/env bash
#
# Foundation access provision-handler fragment.
#
# Owned by "Task 5: Supply Reviewed UAT Access Symbols To Unified
# Provisioning" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md.
#
# Loads the foundation-owned implementation library through the same
# validated package-library mechanism used by every numbered fragment, then
# defines only the exact canonical wrappers assigned by the immutable
# registry. This fragment performs no registration and changes no dispatch
# grammar of its own.

source_package_internal_library "10-foundation-access/internal/access-scopes.sh" || return 1

foundation_provision_backend() { provision_backend_scope "$@"; }
foundation_provision_access_governance() { provision_access_governance_scope "$@"; }
foundation_provision_eks_access() { provision_eks_access_scope "$@"; }
