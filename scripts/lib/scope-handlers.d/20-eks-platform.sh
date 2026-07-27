#!/usr/bin/env bash

source_package_internal_library "20-eks-platform/internal/lifecycle-handlers.sh" || return 1

scope_registry_deferred_eks_platform_provision() { eks_internal_eks_platform_provision_handler "$@"; }
scope_registry_deferred_workload_identity_provision() { eks_internal_workload_identity_provision_handler "$@"; }
scope_registry_deferred_platform_controllers_provision() { eks_internal_platform_controllers_provision_handler "$@"; }

scope_registry_deferred_eks_platform_destroy() { eks_internal_eks_platform_destroy_handler "$@"; }
scope_registry_deferred_workload_identity_destroy() { eks_internal_workload_identity_destroy_handler "$@"; }
scope_registry_deferred_platform_controllers_destroy() { eks_internal_platform_controllers_destroy_handler "$@"; }
