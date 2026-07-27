#!/usr/bin/env bash
#
# EKS platform verifier fragment.
#
# Owned by "Task 7: Define Canonical Component-Verifier Wrappers" in
# docs/superpowers/plans/2026-07-22-phase2-eks-platform.md.
#
# After foundation validation, uses the foundation-validated package-source
# helper to source both EKS-owned mode-safe internal files, then alone
# defines the exact pre-mapped canonical verifier wrapper symbols assigned by
# the fixed registry (scripts/lib/scope-registry.sh's
# `verification_handler_for_slot`):
#   scope_registry_verify_eks_platform
#   scope_registry_verify_workload_identity
#   scope_registry_verify_platform_controllers
#
# Also defines the foundation-pre-mapped guard wrapper symbols:
#   verify_eks_platform_pre_destroy
#   verify_workload_identity_pre_destroy
#   verify_platform_controllers_pre_destroy
#
# No registry mutation; catalog, graph, and guard mappings remain unchanged
# after this fragment is loaded. No lifecycle or handler symbols defined here.

source_package_internal_library "20-eks-platform/internal/verifiers.sh" || return 1
source_package_internal_library "20-eks-platform/internal/pre-destroy-guards.sh" || return 1

scope_registry_verify_eks_platform() { eks_internal_eks_platform_verifier "$@"; }
scope_registry_verify_workload_identity() { eks_internal_workload_identity_verifier "$@"; }
scope_registry_verify_platform_controllers() { eks_internal_platform_controllers_verifier "$@"; }

verify_eks_platform_pre_destroy() { eks_internal_eks_platform_pre_destroy_guard "$@"; }
verify_workload_identity_pre_destroy() { eks_internal_workload_identity_pre_destroy_guard "$@"; }
verify_platform_controllers_pre_destroy() { eks_internal_platform_controllers_pre_destroy_guard "$@"; }
