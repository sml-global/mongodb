#!/usr/bin/env bash
#
# Permanent unified provisioning-scope registry and fail-closed dependency
# graph.
#
# "Task 3: Define The Permanent Unified Scope Registry And Fail-Closed
# Graph" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
# owns this file. Every catalog scope, its provision dependency list, the
# immutable full provision/destroy orders, state-key variable name, provision/
# destroy/pre-destroy-guard/internal-verifier symbol mapping, and deferred
# work-package status are stored here as readonly indexed arrays and `case`
# lookups only -- no associative arrays (`declare -A`), no `declare -g`, no
# executable external config, and no top-level execution. Bash 3.2
# compatible.
#
# Every provision/destroy/pre-destroy-guard/internal-verifier symbol below is
# initialized to a canonical fail-unavailable placeholder function defined
# directly in this file. Two different reasons a placeholder can fail are
# distinguished by message wording, on purpose:
#
#   - "requires work package <N>": the scope's real implementation is owned
#     by a later, separately dated plan (an external work package) and does
#     not exist in this repository yet.
#   - "requires the foundation access fragment (Task 5)": `backend`,
#     `access-governance`, and `eks-access` are NOT deferred to an external
#     work package -- their real `foundation_provision_*` implementations are
#     supplied later in THIS SAME plan by "Task 5: Supply Reviewed UAT Access
#     Symbols To Unified Provisioning". Task 5's fragment defines ordinary
#     functions with these exact canonical names; Bash's normal function-
#     redefinition semantics let that later definition replace the
#     placeholder below with no override mechanism required here.
#
# Numbered fragments (including Task 5's) may define only the mapped
# canonical symbols owned by their domain. They do not register new slots,
# modify this file, add a second registry, or special-case a scope or
# verification mode in orchestrator.sh.
#
# This file contains no top-level execution.

# ---------------------------------------------------------------------------
# Immutable registry data
# ---------------------------------------------------------------------------

readonly _SCOPE_REGISTRY_CATALOG=(
  "backend"
  "eks-platform"
  "access-governance"
  "eks-access"
  "platform-controllers"
  "boomi-runtime"
  "mongodb"
  "postgresql-core"
  "postgresql-brand"
  "mongodb-access"
  "database-access-core"
  "database-access-brand"
  "workload-identity"
  "signoz"
  "signoz-observability"
  "all"
)

# Immutable, approved-design final orders for the `all` pseudo-scope. These
# are stored as literal data (not derived at run time) because the approved
# ordering encodes design choices -- e.g. workload-identity before
# platform-controllers -- that are not implied by dependency order alone;
# any valid topological order would satisfy the dependency graph, but only
# this exact order is approved. Keep these two arrays and
# `dependencies_for_scope` manually consistent: every scope must appear after
# everything it depends on.
readonly _SCOPE_REGISTRY_ALL_PROVISION_ORDER=(
  "backend"
  "access-governance"
  "eks-platform"
  "eks-access"
  "workload-identity"
  "platform-controllers"
  "boomi-runtime"
  "mongodb"
  "postgresql-core"
  "postgresql-brand"
  "mongodb-access"
  "database-access-core"
  "database-access-brand"
  "signoz"
  "signoz-observability"
)

# Ordinary reverse destroy excludes backend and access-governance.
readonly _SCOPE_REGISTRY_ALL_DESTROY_ORDER=(
  "signoz-observability"
  "signoz"
  "boomi-runtime"
  "mongodb-access"
  "database-access-brand"
  "database-access-core"
  "mongodb"
  "postgresql-brand"
  "postgresql-core"
  "workload-identity"
  "platform-controllers"
  "eks-access"
  "eks-platform"
)

readonly _SCOPE_REGISTRY_PREFLIGHT_SLOTS=(
  "foundation-contract"
  "aws-identity-region"
  "kubernetes-context"
  "eks-authentication-mode"
)

readonly _SCOPE_REGISTRY_SMOKE_ONLY_SLOTS=(
  "mongodb-audit-write-smoke"
  "signoz-otlp-roundtrip-smoke"
)

# ---------------------------------------------------------------------------
# Small internal helpers (not part of the exported public interface)
# ---------------------------------------------------------------------------

_scope_registry_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_scope_registry_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Every canonical scope admitted to ordinary destroy (exactly the 13 scopes
# in `_SCOPE_REGISTRY_ALL_DESTROY_ORDER`) has one required pre-destroy-guard
# mapping, even when its downstream implementation is absent. `backend` and
# `access-governance` are excluded on purpose: their destroy handlers are
# themselves hard, always-blocked functions, not a guarded, conditionally
# allowed destroy.
_scope_registry_scope_requires_pre_destroy_guard() {
  _scope_registry_in_list "$1" "${_SCOPE_REGISTRY_ALL_DESTROY_ORDER[@]}"
}

# Shared bodies for the many canonical fail-unavailable placeholder
# functions below, so every placeholder is a trivially reviewable one-line
# wrapper instead of a hand-copied error message.

_scope_registry_fail_work_package() {
  _scope_registry_error "${1} requires work package ${2}"
  return 1
}

_scope_registry_fail_fragment_pending() {
  _scope_registry_error "${1} requires the foundation access fragment (Task 5)"
  return 1
}

_scope_registry_fail_verifier_wiring_pending() {
  _scope_registry_error "${1} verification requires orchestrator verifier wiring (later task)"
  return 1
}

# ---------------------------------------------------------------------------
# Canonical fail-unavailable placeholder functions
# ---------------------------------------------------------------------------
#
# Provision placeholders --------------------------------------------------

foundation_provision_backend() { _scope_registry_fail_fragment_pending "backend"; }
foundation_provision_access_governance() { _scope_registry_fail_fragment_pending "access-governance"; }
foundation_provision_eks_access() { _scope_registry_fail_fragment_pending "eks-access"; }

scope_registry_deferred_eks_platform_provision() { _scope_registry_fail_work_package "eks-platform" 3; }
scope_registry_deferred_platform_controllers_provision() { _scope_registry_fail_work_package "platform-controllers" 3; }
scope_registry_deferred_workload_identity_provision() { _scope_registry_fail_work_package "workload-identity" 3; }
scope_registry_deferred_boomi_runtime_provision() { _scope_registry_fail_work_package "boomi-runtime" 5; }
scope_registry_deferred_mongodb_provision() { _scope_registry_fail_work_package "mongodb" 4; }
scope_registry_deferred_postgresql_core_provision() { _scope_registry_fail_work_package "postgresql-core" 4; }
scope_registry_deferred_postgresql_brand_provision() { _scope_registry_fail_work_package "postgresql-brand" 4; }
scope_registry_deferred_mongodb_access_provision() { _scope_registry_fail_work_package "mongodb-access" 4; }
scope_registry_deferred_database_access_core_provision() { _scope_registry_fail_work_package "database-access-core" 4; }
scope_registry_deferred_database_access_brand_provision() { _scope_registry_fail_work_package "database-access-brand" 4; }
scope_registry_deferred_signoz_provision() { _scope_registry_fail_work_package "signoz" 4; }
scope_registry_deferred_signoz_observability_provision() { _scope_registry_fail_work_package "signoz-observability" 4; }

# Destroy placeholders -----------------------------------------------------

foundation_destroy_backend_blocked() {
  _scope_registry_error "backend destroy is blocked; break-glass procedure required"
  return 1
}

foundation_destroy_access_governance_blocked() {
  _scope_registry_error "access-governance destroy is blocked; retained-control procedure required"
  return 1
}

# eks-access's destroy handler is deferred to work package 3 (not the
# foundation access fragment): safely tearing down access entries requires
# the same canonical cluster-identity/authentication-mode awareness that
# work package 3 owns, unlike granting access, which the foundation fragment
# owns directly.
scope_registry_deferred_eks_access_destroy() { _scope_registry_fail_work_package "eks-access" 3; }
scope_registry_deferred_eks_platform_destroy() { _scope_registry_fail_work_package "eks-platform" 3; }
scope_registry_deferred_platform_controllers_destroy() { _scope_registry_fail_work_package "platform-controllers" 3; }
scope_registry_deferred_workload_identity_destroy() { _scope_registry_fail_work_package "workload-identity" 3; }
scope_registry_deferred_boomi_runtime_destroy() { _scope_registry_fail_work_package "boomi-runtime" 5; }
scope_registry_deferred_mongodb_destroy() { _scope_registry_fail_work_package "mongodb" 4; }
scope_registry_deferred_postgresql_core_destroy() { _scope_registry_fail_work_package "postgresql-core" 4; }
scope_registry_deferred_postgresql_brand_destroy() { _scope_registry_fail_work_package "postgresql-brand" 4; }
scope_registry_deferred_mongodb_access_destroy() { _scope_registry_fail_work_package "mongodb-access" 4; }
scope_registry_deferred_database_access_core_destroy() { _scope_registry_fail_work_package "database-access-core" 4; }
scope_registry_deferred_database_access_brand_destroy() { _scope_registry_fail_work_package "database-access-brand" 4; }
scope_registry_deferred_signoz_destroy() { _scope_registry_fail_work_package "signoz" 4; }
scope_registry_deferred_signoz_observability_destroy() { _scope_registry_fail_work_package "signoz-observability" 4; }

# Pre-destroy guard placeholders (exactly the 13 ordinary-destroy scopes) --

scope_registry_pre_destroy_guard_eks_platform() { _scope_registry_fail_work_package "eks-platform" 3; }
scope_registry_pre_destroy_guard_eks_access() { _scope_registry_fail_work_package "eks-access" 3; }
scope_registry_pre_destroy_guard_platform_controllers() { _scope_registry_fail_work_package "platform-controllers" 3; }
scope_registry_pre_destroy_guard_workload_identity() { _scope_registry_fail_work_package "workload-identity" 3; }
scope_registry_pre_destroy_guard_boomi_runtime() { _scope_registry_fail_work_package "boomi-runtime" 5; }
scope_registry_pre_destroy_guard_mongodb() { _scope_registry_fail_work_package "mongodb" 4; }
scope_registry_pre_destroy_guard_postgresql_core() { _scope_registry_fail_work_package "postgresql-core" 4; }
scope_registry_pre_destroy_guard_postgresql_brand() { _scope_registry_fail_work_package "postgresql-brand" 4; }
scope_registry_pre_destroy_guard_mongodb_access() { _scope_registry_fail_work_package "mongodb-access" 4; }
scope_registry_pre_destroy_guard_database_access_core() { _scope_registry_fail_work_package "database-access-core" 4; }
scope_registry_pre_destroy_guard_database_access_brand() { _scope_registry_fail_work_package "database-access-brand" 4; }
scope_registry_pre_destroy_guard_signoz() { _scope_registry_fail_work_package "signoz" 4; }
scope_registry_pre_destroy_guard_signoz_observability() { _scope_registry_fail_work_package "signoz-observability" 4; }

# Internal verifier placeholders --------------------------------------------

scope_registry_verify_foundation_contract() { _scope_registry_fail_verifier_wiring_pending "foundation-contract"; }
scope_registry_verify_aws_identity_region() { _scope_registry_fail_verifier_wiring_pending "aws-identity-region"; }
scope_registry_verify_kubernetes_context() { _scope_registry_fail_verifier_wiring_pending "kubernetes-context"; }
scope_registry_verify_eks_authentication_mode() { _scope_registry_fail_verifier_wiring_pending "eks-authentication-mode"; }

scope_registry_verify_backend() { _scope_registry_fail_fragment_pending "backend"; }
scope_registry_verify_access_governance() { _scope_registry_fail_fragment_pending "access-governance"; }
# Component verifier for eks-access is tied to the foundation-fragment
# category (not work package 3): readiness of the access grant itself is
# blocked by the same not-yet-wired fragment as its provision handler.
scope_registry_verify_eks_access() { _scope_registry_fail_fragment_pending "eks-access"; }

scope_registry_verify_eks_platform() { _scope_registry_fail_work_package "eks-platform" 3; }
scope_registry_verify_platform_controllers() { _scope_registry_fail_work_package "platform-controllers" 3; }
scope_registry_verify_workload_identity() { _scope_registry_fail_work_package "workload-identity" 3; }
scope_registry_verify_boomi_runtime() { _scope_registry_fail_work_package "boomi-runtime" 5; }
scope_registry_verify_mongodb() { _scope_registry_fail_work_package "mongodb" 4; }
scope_registry_verify_postgresql_core() { _scope_registry_fail_work_package "postgresql-core" 4; }
scope_registry_verify_postgresql_brand() { _scope_registry_fail_work_package "postgresql-brand" 4; }
scope_registry_verify_mongodb_access() { _scope_registry_fail_work_package "mongodb-access" 4; }
scope_registry_verify_database_access_core() { _scope_registry_fail_work_package "database-access-core" 4; }
scope_registry_verify_database_access_brand() { _scope_registry_fail_work_package "database-access-brand" 4; }
scope_registry_verify_signoz() { _scope_registry_fail_work_package "signoz" 4; }
scope_registry_verify_signoz_observability() { _scope_registry_fail_work_package "signoz-observability" 4; }

scope_registry_verify_mongodb_audit_write_smoke() { _scope_registry_fail_verifier_wiring_pending "mongodb-audit-write-smoke"; }
scope_registry_verify_signoz_otlp_roundtrip_smoke() { _scope_registry_fail_verifier_wiring_pending "signoz-otlp-roundtrip-smoke"; }

# ---------------------------------------------------------------------------
# Public pure lookup functions
# ---------------------------------------------------------------------------

list_provision_scopes() {
  printf '%s\n' "${_SCOPE_REGISTRY_CATALOG[@]}"
}

dependencies_for_scope() {
  case "${1:-}" in
    backend) printf '%s\n' "" ;;
    access-governance) printf '%s\n' "backend" ;;
    eks-platform) printf '%s\n' "backend" ;;
    eks-access) printf '%s\n' "eks-platform" ;;
    platform-controllers) printf '%s\n' "eks-platform" ;;
    workload-identity) printf '%s\n' "eks-platform" ;;
    boomi-runtime) printf '%s\n' "eks-platform platform-controllers workload-identity" ;;
    mongodb) printf '%s\n' "eks-platform platform-controllers" ;;
    postgresql-core) printf '%s\n' "eks-platform" ;;
    postgresql-brand) printf '%s\n' "eks-platform" ;;
    mongodb-access) printf '%s\n' "mongodb" ;;
    database-access-core) printf '%s\n' "postgresql-core" ;;
    database-access-brand) printf '%s\n' "postgresql-brand" ;;
    signoz) printf '%s\n' "eks-platform platform-controllers" ;;
    signoz-observability) printf '%s\n' "signoz" ;;
    *)
      # Deliberately covers "all", "verification", the empty string, and any
      # unrecognized scope name with a single fail-closed default.
      return 1
      ;;
  esac
}

provision_handler_for_scope() {
  case "${1:-}" in
    backend) printf '%s\n' "foundation_provision_backend" ;;
    access-governance) printf '%s\n' "foundation_provision_access_governance" ;;
    eks-access) printf '%s\n' "foundation_provision_eks_access" ;;
    eks-platform) printf '%s\n' "scope_registry_deferred_eks_platform_provision" ;;
    platform-controllers) printf '%s\n' "scope_registry_deferred_platform_controllers_provision" ;;
    workload-identity) printf '%s\n' "scope_registry_deferred_workload_identity_provision" ;;
    boomi-runtime) printf '%s\n' "scope_registry_deferred_boomi_runtime_provision" ;;
    mongodb) printf '%s\n' "scope_registry_deferred_mongodb_provision" ;;
    postgresql-core) printf '%s\n' "scope_registry_deferred_postgresql_core_provision" ;;
    postgresql-brand) printf '%s\n' "scope_registry_deferred_postgresql_brand_provision" ;;
    mongodb-access) printf '%s\n' "scope_registry_deferred_mongodb_access_provision" ;;
    database-access-core) printf '%s\n' "scope_registry_deferred_database_access_core_provision" ;;
    database-access-brand) printf '%s\n' "scope_registry_deferred_database_access_brand_provision" ;;
    signoz) printf '%s\n' "scope_registry_deferred_signoz_provision" ;;
    signoz-observability) printf '%s\n' "scope_registry_deferred_signoz_observability_provision" ;;
    *)
      # "all" has no single provision symbol: it is graph expansion only,
      # dispatched by `dispatch_scope_handler` one resolved scope at a time.
      _scope_registry_error "no provision handler is mapped for scope: ${1:-<empty>}"
      return 1
      ;;
  esac
}

destroy_handler_for_scope() {
  case "${1:-}" in
    backend) printf '%s\n' "foundation_destroy_backend_blocked" ;;
    access-governance) printf '%s\n' "foundation_destroy_access_governance_blocked" ;;
    eks-access) printf '%s\n' "scope_registry_deferred_eks_access_destroy" ;;
    eks-platform) printf '%s\n' "scope_registry_deferred_eks_platform_destroy" ;;
    platform-controllers) printf '%s\n' "scope_registry_deferred_platform_controllers_destroy" ;;
    workload-identity) printf '%s\n' "scope_registry_deferred_workload_identity_destroy" ;;
    boomi-runtime) printf '%s\n' "scope_registry_deferred_boomi_runtime_destroy" ;;
    mongodb) printf '%s\n' "scope_registry_deferred_mongodb_destroy" ;;
    postgresql-core) printf '%s\n' "scope_registry_deferred_postgresql_core_destroy" ;;
    postgresql-brand) printf '%s\n' "scope_registry_deferred_postgresql_brand_destroy" ;;
    mongodb-access) printf '%s\n' "scope_registry_deferred_mongodb_access_destroy" ;;
    database-access-core) printf '%s\n' "scope_registry_deferred_database_access_core_destroy" ;;
    database-access-brand) printf '%s\n' "scope_registry_deferred_database_access_brand_destroy" ;;
    signoz) printf '%s\n' "scope_registry_deferred_signoz_destroy" ;;
    signoz-observability) printf '%s\n' "scope_registry_deferred_signoz_observability_destroy" ;;
    *)
      # "all" is reverse graph expansion only; see provision_handler_for_scope.
      _scope_registry_error "no destroy handler is mapped for scope: ${1:-<empty>}"
      return 1
      ;;
  esac
}

pre_destroy_guard_for_scope() {
  case "${1:-}" in
    eks-platform) printf '%s\n' "scope_registry_pre_destroy_guard_eks_platform" ;;
    eks-access) printf '%s\n' "scope_registry_pre_destroy_guard_eks_access" ;;
    platform-controllers) printf '%s\n' "scope_registry_pre_destroy_guard_platform_controllers" ;;
    workload-identity) printf '%s\n' "scope_registry_pre_destroy_guard_workload_identity" ;;
    boomi-runtime) printf '%s\n' "scope_registry_pre_destroy_guard_boomi_runtime" ;;
    mongodb) printf '%s\n' "scope_registry_pre_destroy_guard_mongodb" ;;
    postgresql-core) printf '%s\n' "scope_registry_pre_destroy_guard_postgresql_core" ;;
    postgresql-brand) printf '%s\n' "scope_registry_pre_destroy_guard_postgresql_brand" ;;
    mongodb-access) printf '%s\n' "scope_registry_pre_destroy_guard_mongodb_access" ;;
    database-access-core) printf '%s\n' "scope_registry_pre_destroy_guard_database_access_core" ;;
    database-access-brand) printf '%s\n' "scope_registry_pre_destroy_guard_database_access_brand" ;;
    signoz) printf '%s\n' "scope_registry_pre_destroy_guard_signoz" ;;
    signoz-observability) printf '%s\n' "scope_registry_pre_destroy_guard_signoz_observability" ;;
    *)
      # No pseudo-scope ("all"), non-ordinary-destroy scope (backend,
      # access-governance), or unknown name may ever resolve a guard here.
      _scope_registry_error "no pre-destroy guard is mapped for scope: ${1:-<empty>}"
      return 1
      ;;
  esac
}

state_key_variable_for_scope() {
  case "${1:-}" in
    backend) printf '%s\n' "BACKEND_STATE_KEY" ;;
    access-governance) printf '%s\n' "ACCESS_GOVERNANCE_STATE_KEY" ;;
    eks-platform) printf '%s\n' "EKS_PLATFORM_STATE_KEY" ;;
    eks-access) printf '%s\n' "EKS_ACCESS_STATE_KEY" ;;
    platform-controllers) printf '%s\n' "PLATFORM_CONTROLLERS_STATE_KEY" ;;
    workload-identity) printf '%s\n' "WORKLOAD_IDENTITY_STATE_KEY" ;;
    boomi-runtime) printf '%s\n' "BOOMI_RUNTIME_STATE_KEY" ;;
    mongodb) printf '%s\n' "MONGODB_STATE_KEY" ;;
    postgresql-core) printf '%s\n' "POSTGRESQL_CORE_STATE_KEY" ;;
    postgresql-brand) printf '%s\n' "POSTGRESQL_BRAND_STATE_KEY" ;;
    mongodb-access) printf '%s\n' "MONGODB_ACCESS_STATE_KEY" ;;
    database-access-core) printf '%s\n' "DATABASE_ACCESS_CORE_STATE_KEY" ;;
    database-access-brand) printf '%s\n' "DATABASE_ACCESS_BRAND_STATE_KEY" ;;
    signoz) printf '%s\n' "SIGNOZ_STATE_KEY" ;;
    signoz-observability) printf '%s\n' "SIGNOZ_OBSERVABILITY_STATE_KEY" ;;
    *)
      _scope_registry_error "no state-key variable is mapped for scope: ${1:-<empty>}"
      return 1
      ;;
  esac
}

# Distinguishes, for the provision-side fail-closed dispatch gate, a scope
# whose real implementation is owned by an external, later-dated work
# package from one that is only pending this plan's own Task 5 foundation
# access fragment (see the file header). "all" is graph expansion only and
# has no independent implementation status of its own.
implementation_requirement_for_scope() {
  case "${1:-}" in
    backend|access-governance|eks-access)
      printf '%s\n' "foundation-fragment-pending"
      ;;
    eks-platform)
      printf '%s\n' "external-existing-platform"
      ;;
    platform-controllers|workload-identity)
      printf '%s\n' "external-work-package-3"
      ;;
    mongodb|postgresql-core|postgresql-brand|mongodb-access|database-access-core|database-access-brand|signoz|signoz-observability)
      printf '%s\n' "external-work-package-4"
      ;;
    boomi-runtime)
      printf '%s\n' "external-work-package-5"
      ;;
    all)
      printf '%s\n' "graph-expansion-only"
      ;;
    *)
      _scope_registry_error "no implementation-requirement mapping for scope: ${1:-<empty>}"
      return 1
      ;;
  esac
}

verification_handler_for_slot() {
  case "${1:-}" in
    foundation-contract) printf '%s\n' "scope_registry_verify_foundation_contract" ;;
    aws-identity-region) printf '%s\n' "scope_registry_verify_aws_identity_region" ;;
    kubernetes-context) printf '%s\n' "scope_registry_verify_kubernetes_context" ;;
    eks-authentication-mode) printf '%s\n' "scope_registry_verify_eks_authentication_mode" ;;
    backend) printf '%s\n' "scope_registry_verify_backend" ;;
    access-governance) printf '%s\n' "scope_registry_verify_access_governance" ;;
    eks-platform) printf '%s\n' "scope_registry_verify_eks_platform" ;;
    eks-access) printf '%s\n' "scope_registry_verify_eks_access" ;;
    platform-controllers) printf '%s\n' "scope_registry_verify_platform_controllers" ;;
    workload-identity) printf '%s\n' "scope_registry_verify_workload_identity" ;;
    boomi-runtime) printf '%s\n' "scope_registry_verify_boomi_runtime" ;;
    mongodb) printf '%s\n' "scope_registry_verify_mongodb" ;;
    postgresql-core) printf '%s\n' "scope_registry_verify_postgresql_core" ;;
    postgresql-brand) printf '%s\n' "scope_registry_verify_postgresql_brand" ;;
    mongodb-access) printf '%s\n' "scope_registry_verify_mongodb_access" ;;
    database-access-core) printf '%s\n' "scope_registry_verify_database_access_core" ;;
    database-access-brand) printf '%s\n' "scope_registry_verify_database_access_brand" ;;
    signoz) printf '%s\n' "scope_registry_verify_signoz" ;;
    signoz-observability) printf '%s\n' "scope_registry_verify_signoz_observability" ;;
    mongodb-audit-write-smoke) printf '%s\n' "scope_registry_verify_mongodb_audit_write_smoke" ;;
    signoz-otlp-roundtrip-smoke) printf '%s\n' "scope_registry_verify_signoz_otlp_roundtrip_smoke" ;;
    *)
      _scope_registry_error "no verifier handler is mapped for slot: ${1:-<empty>}"
      return 1
      ;;
  esac
}

# `--preflight` selects the foundation contract, AWS identity/Region, and
# canonical Kubernetes readiness slots. `--full` (also the exact no-flag
# default) selects every preflight slot followed by every component verifier
# slot in provision dependency order. `--smoke-test` selects every full slot
# followed by the immutable cross-component smoke slots. Component verifier
# slots (scope names) and smoke slots are internal names only and are never
# accepted here as a mode value -- they simply do not match any accepted
# pattern below and fall through to the fail-closed default.
verification_slots_for_mode() {
  local mode="${1:-}"

  case "$mode" in
    ""|full|--full)
      printf '%s\n' "${_SCOPE_REGISTRY_PREFLIGHT_SLOTS[@]}" "${_SCOPE_REGISTRY_ALL_PROVISION_ORDER[@]}"
      ;;
    preflight|--preflight)
      printf '%s\n' "${_SCOPE_REGISTRY_PREFLIGHT_SLOTS[@]}"
      ;;
    smoke-test|--smoke-test)
      printf '%s\n' "${_SCOPE_REGISTRY_PREFLIGHT_SLOTS[@]}" "${_SCOPE_REGISTRY_ALL_PROVISION_ORDER[@]}" "${_SCOPE_REGISTRY_SMOKE_ONLY_SLOTS[@]}"
      ;;
    *)
      _scope_registry_error "verification_slots_for_mode accepts only (no flag)/--full, --preflight, or --smoke-test; got: ${mode:-<empty>}"
      return 1
      ;;
  esac
}

_scope_registry_dedup_preserving_order() {
  local -a seen=()
  local item

  for item in "$@"; do
    if ! _scope_registry_in_list "$item" "${seen[@]:-}"; then
      seen+=("$item")
      printf '%s\n' "$item"
    fi
  done
}

resolve_verification_order() {
  local raw

  raw="$(verification_slots_for_mode "${1:-}")" || return 1

  local -a slots=()
  local slot
  while IFS= read -r slot; do
    [[ -n "$slot" ]] && slots+=("$slot")
  done <<< "$raw"

  if [[ "${#slots[@]}" -eq 0 ]]; then
    return 1
  fi

  _scope_registry_dedup_preserving_order "${slots[@]}"
}

# ---------------------------------------------------------------------------
# Generic dependency-order resolution engine
# ---------------------------------------------------------------------------
#
# `_scope_registry_resolve_dependency_order <deps-function-name>
# <root-scope>...` performs DFS-based dependency (topological) resolution
# over the transitive closure of the given roots, using `deps-function-name`
# as an indirect callback (Bash 3.2 has no namerefs, so the callback is
# invoked by name). It detects cycles, rejects unknown dependencies (any
# name for which the callback itself fails), and deduplicates repeated or
# transitively shared scopes while preserving first-resolved order. Nothing
# is printed unless the entire requested closure resolves successfully --
# this is what gives "all"/multi-scope requests full graph pre-resolution
# before any output, and before any handler is ever invoked.
#
# This engine is intentionally reusable and is exercised directly by tests
# with small synthetic callback functions to prove cycle detection, unknown-
# dependency rejection, and duplicate resolution independently of this
# registry's own (acyclic, by construction) real data.

_SCOPE_REGISTRY_RESOLVE_DEPS_FN=""
_SCOPE_REGISTRY_RESOLVE_VISITING=()
_SCOPE_REGISTRY_RESOLVE_RESOLVED=()
_SCOPE_REGISTRY_RESOLVE_RESULT=()

_scope_registry_visit_node() {
  local node="$1"
  local raw_deps=""
  local dep=""

  if _scope_registry_in_list "$node" "${_SCOPE_REGISTRY_RESOLVE_RESOLVED[@]:-}"; then
    return 0
  fi
  if _scope_registry_in_list "$node" "${_SCOPE_REGISTRY_RESOLVE_VISITING[@]:-}"; then
    _scope_registry_error "cycle detected involving scope: ${node}"
    return 1
  fi

  _SCOPE_REGISTRY_RESOLVE_VISITING+=("$node")

  if ! raw_deps="$("$_SCOPE_REGISTRY_RESOLVE_DEPS_FN" "$node" 2>/dev/null)"; then
    _scope_registry_error "unknown dependency referenced while resolving scope: ${node}"
    return 1
  fi

  for dep in $raw_deps; do
    _scope_registry_visit_node "$dep" || return 1
  done

  _SCOPE_REGISTRY_RESOLVE_RESOLVED+=("$node")
  _SCOPE_REGISTRY_RESOLVE_RESULT+=("$node")
  return 0
}

_scope_registry_resolve_dependency_order() {
  local deps_fn="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    _scope_registry_error "_scope_registry_resolve_dependency_order requires at least one root scope"
    return 1
  fi

  _SCOPE_REGISTRY_RESOLVE_DEPS_FN="$deps_fn"
  _SCOPE_REGISTRY_RESOLVE_VISITING=()
  _SCOPE_REGISTRY_RESOLVE_RESOLVED=()
  _SCOPE_REGISTRY_RESOLVE_RESULT=()

  local root
  for root in "$@"; do
    _scope_registry_visit_node "$root" || return 1
  done

  printf '%s\n' "${_SCOPE_REGISTRY_RESOLVE_RESULT[@]}"
}

# ---------------------------------------------------------------------------
# Provision / destroy order resolution
# ---------------------------------------------------------------------------

resolve_provision_order() {
  local scope="${1:-}"

  if [[ "$scope" == "all" ]]; then
    printf '%s\n' "${_SCOPE_REGISTRY_ALL_PROVISION_ORDER[@]}"
    return 0
  fi

  if ! dependencies_for_scope "$scope" >/dev/null 2>&1; then
    _scope_registry_error "unknown provisioning scope: ${scope:-<empty>}"
    return 1
  fi

  _scope_registry_resolve_dependency_order dependencies_for_scope "$scope"
}

# Ordinary destroy of a single narrow scope destroys exactly that scope
# (backend and access-governance are legitimate explicit narrow destroy
# targets -- their destroy handlers are hard-blocked functions, not an
# absent mapping). Only the "all" pseudo-scope cascades to the full,
# immutable, approved reverse order above.
resolve_destroy_order() {
  local scope="${1:-}"

  if [[ "$scope" == "all" ]]; then
    printf '%s\n' "${_SCOPE_REGISTRY_ALL_DESTROY_ORDER[@]}"
    return 0
  fi

  if ! dependencies_for_scope "$scope" >/dev/null 2>&1; then
    _scope_registry_error "unknown destroy scope: ${scope:-<empty>}"
    return 1
  fi

  printf '%s\n' "$scope"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
#
# `dispatch_scope_handler <provision|destroy> <scope>` fully pre-resolves
# and validates the requested order before invoking anything:
#
#   provision: first walks the whole resolved order checking
#     `implementation_requirement_for_scope`; the first scope whose
#     requirement is an external work package stops dispatch immediately
#     with "<scope> requires work package <N>" and calls no handler at all
#     (an empty handler command log). Foundation-fragment-pending scopes
#     (backend, access-governance, eks-access) do not block this pre-check,
#     so once Task 5 supplies their real symbols, dispatch proceeds past
#     them unchanged; only a genuinely external work package blocks the
#     whole graph. If nothing blocks, every handler is then invoked in
#     order, stopping at the first failure.
#
#   destroy: first walks the whole resolved order validating that every
#     scope which requires a pre-destroy guard has one mapped, and that
#     every scope has a destroy handler mapped -- entirely before invoking
#     anything. It then invokes, in order, each scope's guard (when
#     required) followed by its destroy handler, stopping at the first
#     failure.
dispatch_scope_handler() {
  local operation="${1:-}"
  local scope="${2:-}"

  case "$operation" in
    provision|destroy) ;;
    *)
      _scope_registry_error "dispatch_scope_handler accepts only provision or destroy, got: ${operation:-<empty>}"
      return 1
      ;;
  esac

  if [[ -z "$scope" ]]; then
    _scope_registry_error "dispatch_scope_handler requires a scope"
    return 1
  fi

  local raw_order
  if [[ "$operation" == "provision" ]]; then
    raw_order="$(resolve_provision_order "$scope")" || {
      _scope_registry_error "unable to resolve a provision order for scope: ${scope}"
      return 1
    }
  else
    raw_order="$(resolve_destroy_order "$scope")" || {
      _scope_registry_error "unable to resolve a destroy order for scope: ${scope}"
      return 1
    }
  fi

  local -a order=()
  local step
  while IFS= read -r step; do
    [[ -n "$step" ]] && order+=("$step")
  done <<< "$raw_order"

  if [[ "${#order[@]}" -eq 0 ]]; then
    _scope_registry_error "resolved an empty ${operation} order for scope: ${scope}"
    return 1
  fi

  if [[ "$operation" == "provision" ]]; then
    local requirement
    for step in "${order[@]}"; do
      requirement="$(implementation_requirement_for_scope "$step")" || {
        _scope_registry_error "no implementation-requirement mapping for scope: ${step}"
        return 1
      }
      case "$requirement" in
        external-work-package-*)
          _scope_registry_error "${step} requires work package ${requirement##*-}"
          return 1
          ;;
      esac
    done

    local symbol
    local requirement
    for step in "${order[@]}"; do
      requirement="$(implementation_requirement_for_scope "$step")" || {
        _scope_registry_error "no implementation-requirement mapping for scope: ${step}"
        return 1
      }
      if [[ "$requirement" == "external-existing-platform" ]]; then
        continue
      fi
      symbol="$(provision_handler_for_scope "$step")" || {
        _scope_registry_error "no provision handler is mapped for scope: ${step}"
        return 1
      }
      "$symbol" || return 1
    done
    return 0
  fi

  # destroy: validate every guard/handler mapping across the whole order
  # before invoking anything.
  local symbol
  for step in "${order[@]}"; do
    if _scope_registry_scope_requires_pre_destroy_guard "$step"; then
      pre_destroy_guard_for_scope "$step" >/dev/null || {
        _scope_registry_error "no pre-destroy guard is mapped for scope: ${step}"
        return 1
      }
    fi
    destroy_handler_for_scope "$step" >/dev/null || {
      _scope_registry_error "no destroy handler is mapped for scope: ${step}"
      return 1
    }
  done

  for step in "${order[@]}"; do
    if _scope_registry_scope_requires_pre_destroy_guard "$step"; then
      symbol="$(pre_destroy_guard_for_scope "$step")"
      "$symbol" || return 1
    fi
    symbol="$(destroy_handler_for_scope "$step")"
    "$symbol" || return 1
  done
}
