#!/usr/bin/env bash
#
# Unified provision/destroy/verify orchestrator.
#
# "Task 4: Add Explicit Unified Entrypoints Without Changing Legacy Dev
# Behavior" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
# owns this file. It is sourced only by the thin public wrappers
# (scripts/provision.sh, scripts/destroy.sh, scripts/verify-platform-health.sh)
# on their explicit `--env <dev|uat> ...` branch; the non-`--env` branch never
# reaches this file at all and execs the frozen `scripts/legacy/dev/*.sh`
# bodies unchanged. This file contains no top-level execution beyond sourcing
# its own foundation dependencies and defining functions; `run_unified_command`
# is the single public entry point.
#
# Foundation dependencies (all owned by earlier tasks in this same plan):
#   scripts/lib/environment-contracts.sh  immutable dev/uat constants
#   scripts/lib/platform-env.sh           load_platform_env <dev|uat>
#   scripts/lib/platform-guards.sh        identity/context/backend guards
#   scripts/lib/orchestration-paths.sh    .local/<env>/ paths, lock, cleanup
#   scripts/lib/scope-registry.sh         scope graph, dependency resolution,
#                                         handler/guard/verifier symbol lookup
#
# This file additionally owns:
#   - The strict `--env <dev|uat>` leading-argument parser.
#   - `require_environment_mutation_authorized`, the sole environment-
#     mutation gate (reads PROMOTION_MODE from the loaded contract).
#   - Unified provision/destroy/verify option parsing and dispatch.
#   - The full two-pass destroy confirmation-artifact + guard-evidence
#     protocol, implemented via scripts/lib/confirmation-artifact.py and
#     scripts/lib/destroy-evidence.py (both standard-library-only Python,
#     invoked only through their small CLIs -- never imported as a package).
#   - `record_pre_destroy_guard_result`, the five-argument foundation
#     callback that is the only channel through which a pre-destroy guard
#     wrapper may report a result.
#   - The package-fragment loader for `scripts/lib/scope-handlers.d/` and
#     `scripts/lib/scope-verifiers.d/`, and `source_package_internal_library`
#     for a fragment's own internal libraries. Neither directory exists yet
#     in this repository (Task 5 and later work packages introduce
#     fragments); an absent or empty directory is valid and contributes
#     nothing.
#
# Bash 3.2 compatible: no associative arrays, no `declare -g`, no namerefs.

if [[ -n "${_ORCHESTRATOR_SOURCED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_ORCHESTRATOR_SOURCED="true"

_ORCHESTRATOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ORCHESTRATOR_SCRIPTS_DIR="$(cd "${_ORCHESTRATOR_LIB_DIR}/.." && pwd)"
_ORCHESTRATOR_ROOT_DIR="$(cd "${_ORCHESTRATOR_SCRIPTS_DIR}/.." && pwd)"
_ORCHESTRATOR_PYTHON="${_ORCHESTRATOR_PYTHON:-python3}"

for _orchestrator_dep in \
  environment-contracts.sh \
  platform-env.sh \
  platform-guards.sh \
  orchestration-paths.sh \
  scope-registry.sh
do
  if [[ ! -r "${_ORCHESTRATOR_LIB_DIR}/${_orchestrator_dep}" ]]; then
    printf 'ERROR: %s\n' "orchestrator foundation dependency is not readable: ${_ORCHESTRATOR_LIB_DIR}/${_orchestrator_dep}" >&2
    return 1 2>/dev/null || exit 1
  fi
  # shellcheck disable=SC1090
  source "${_ORCHESTRATOR_LIB_DIR}/${_orchestrator_dep}"
done
unset _orchestrator_dep

_orchestrator_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_orchestrator_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Clock / operation-ID (test-seamed, standard-library-only in production)
# ---------------------------------------------------------------------------
#
# ORCHESTRATOR_TEST_CLOCK_EPOCH and ORCHESTRATOR_TEST_OPERATION_ID are test-
# only seams: when unset (the production default), the real wall clock and a
# CSPRNG-sourced operation ID are used. Tests set these to obtain the exact
# canonical artifact path and timestamps deterministically.

_orchestrator_now_epoch() {
  if [[ -n "${ORCHESTRATOR_TEST_CLOCK_EPOCH:-}" ]]; then
    printf '%s' "${ORCHESTRATOR_TEST_CLOCK_EPOCH}"
    return 0
  fi
  date -u +%s
}

_orchestrator_generate_operation_id() {
  if [[ -n "${ORCHESTRATOR_TEST_OPERATION_ID:-}" ]]; then
    printf '%s' "${ORCHESTRATOR_TEST_OPERATION_ID}"
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
  fi
}

_orchestrator_format_timestamp() {
  local epoch_seconds="$1"
  if date -u -d "@${epoch_seconds}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then
    return 0
  fi
  date -u -r "${epoch_seconds}" +%Y-%m-%dT%H:%M:%SZ
}

_orchestrator_parse_timestamp_to_epoch() {
  local value="$1"
  local result
  if result="$(date -u -d "${value}" +%s 2>/dev/null)"; then
    printf '%s' "${result}"
    return 0
  fi
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${value}" +%s
}

# ---------------------------------------------------------------------------
# Environment mutation authorization
# ---------------------------------------------------------------------------
#
# The sole environment-mutation gate for every unified provision/destroy
# operation. It reads PROMOTION_MODE from the already-loaded, already-
# immutable-contract-validated environment (`load_platform_env` guarantees
# dev's PROMOTION_MODE is always exactly "modeled" and uat's is always
# exactly "uat-build"), so this single rule produces the exact required dev
# message with no environment-name special-casing:
#   "ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled"

require_environment_mutation_authorized() {
  local environment_name="${1:-}"

  case "$environment_name" in
    dev|uat) ;;
    *)
      _orchestrator_error "require_environment_mutation_authorized accepts only dev or uat"
      return 1
      ;;
  esac

  if [[ "${PROMOTION_MODE:-}" != "uat-build" ]]; then
    _orchestrator_error "unified ${environment_name} mutation is blocked while PROMOTION_MODE=${PROMOTION_MODE:-<unset>}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Package-fragment loading
# ---------------------------------------------------------------------------
#
# Loads every scripts/lib/scope-handlers.d/NN-domain.sh and
# scripts/lib/scope-verifiers.d/NN-domain.sh file, in bytewise lexical order,
# performing symlink/regular-file/group-or-world-writable/naming checks
# before sourcing. Neither directory exists yet in this repository; an
# absent directory contributes nothing and is not an error. Deep static
# validation of fragment content (rejecting arbitrary top-level commands,
# enforcing a per-package canonical-symbol allowlist) is intentionally out
# of scope here: no fragment exists yet to validate against, and that
# content-level enforcement is deferred to the task that first introduces a
# fragment file.

_orchestrator_load_package_fragment_directory() {
  local dir_path="$1"
  local fragment_file

  [[ -d "$dir_path" ]] || return 0

  if [[ -L "$dir_path" ]]; then
    _orchestrator_error "package fragment directory must not be a symlink: ${dir_path}"
    return 1
  fi

  for fragment_file in "$dir_path"/*.sh; do
    [[ -e "$fragment_file" ]] || continue

    case "$(basename "$fragment_file")" in
      [0-9][0-9]-*.sh) ;;
      *)
        _orchestrator_error "malformed package fragment file name: ${fragment_file}"
        return 1
        ;;
    esac

    if [[ -L "$fragment_file" ]]; then
      _orchestrator_error "package fragment must not be a symlink: ${fragment_file}"
      return 1
    fi
    if [[ ! -f "$fragment_file" ]]; then
      _orchestrator_error "package fragment must be a regular file: ${fragment_file}"
      return 1
    fi
    if [[ -n "$(find "$fragment_file" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]]; then
      _orchestrator_error "package fragment must not be group- or world-writable: ${fragment_file}"
      return 1
    fi

    # `_ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE` names the exact NN-domain
    # package this fragment file belongs to while it is sourced, so that
    # `source_package_internal_library` can restrict a fragment to loading
    # implementation libraries only beneath its own package directory.
    _ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE="$(basename "$fragment_file" .sh)"
    # shellcheck disable=SC1090
    if ! source "$fragment_file"; then
      _ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE=""
      _orchestrator_error "failed to source package fragment: ${fragment_file}"
      return 1
    fi
    _ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE=""
  done
}

_orchestrator_load_package_fragments() {
  # Arguments (operation, resolved order) are accepted for interface
  # symmetry with dispatch and possible future fragment-selection logic;
  # today every matching fragment file is loaded unconditionally.
  _orchestrator_load_package_fragment_directory "${_ORCHESTRATOR_LIB_DIR}/scope-handlers.d" || return 1
  _orchestrator_load_package_fragment_directory "${_ORCHESTRATOR_LIB_DIR}/scope-verifiers.d" || return 1
}

# `_ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE` is set only while
# `_orchestrator_load_package_fragment_directory` is sourcing a given
# `NN-domain.sh` fragment; empty otherwise. It is what lets
# `source_package_internal_library` restrict a fragment to its own package.
_ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE=""

# `source_package_internal_library <relative-path-beneath-scripts/lib/packages/>`
# accepts only while a package fragment is actively loading, and only a path
# beneath that exact fragment's own `scripts/lib/packages/<pkg>/internal/`
# directory -- never another package's internal directory. The path is
# resolved and containment-checked against that specific package directory,
# and must be non-symlink, regular, and not group/world-writable, before
# sourcing. A fragment must call this instead of a direct `source`/`.`
# statement to load its own internal library.

source_package_internal_library() {
  local relative_path="${1:-}"
  local active_package="${_ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE:-}"
  local packages_root="${_ORCHESTRATOR_LIB_DIR}/packages"
  local candidate
  local resolved_candidate
  local resolved_active_package_dir

  if [[ -z "$active_package" ]]; then
    _orchestrator_error "source_package_internal_library may only be called while a package fragment is loading"
    return 1
  fi

  case "$relative_path" in
    "${active_package}/internal/"*) ;;
    *)
      _orchestrator_error "source_package_internal_library requires a path beneath ${active_package}/internal/: ${relative_path}"
      return 1
      ;;
  esac

  candidate="${packages_root}/${relative_path}"

  if [[ -L "$candidate" ]]; then
    _orchestrator_error "package internal library must not be a symlink: ${candidate}"
    return 1
  fi
  if [[ ! -f "$candidate" ]]; then
    _orchestrator_error "package internal library must be a regular file: ${candidate}"
    return 1
  fi
  if [[ -n "$(find "$candidate" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]]; then
    _orchestrator_error "package internal library must not be group- or world-writable: ${candidate}"
    return 1
  fi

  resolved_active_package_dir="$(cd "${packages_root}/${active_package}" 2>/dev/null && pwd)" || {
    _orchestrator_error "active package directory does not exist: ${packages_root}/${active_package}"
    return 1
  }
  resolved_candidate="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd)/$(basename "$candidate")" || {
    _orchestrator_error "unable to resolve package internal library path: ${candidate}"
    return 1
  }
  case "$resolved_candidate" in
    "${resolved_active_package_dir}/"*) ;;
    *)
      _orchestrator_error "package internal library escapes its own package directory: ${candidate}"
      return 1
      ;;
  esac

  # shellcheck disable=SC1090
  source "$candidate"
}

# ---------------------------------------------------------------------------
# Unified provision
# ---------------------------------------------------------------------------

_orchestrator_run_provision() {
  local environment_name="$1"
  shift || true

  if [[ $# -eq 0 ]]; then
    _orchestrator_error "unified provision requires a scope"
    return 1
  fi

  local scope="$1"
  shift || true

  local auto_approve="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-approve)
        auto_approve="true"
        shift
        ;;
      *)
        _orchestrator_error "unknown unified provision argument: $1"
        return 1
        ;;
    esac
  done

  require_environment_mutation_authorized "$environment_name" || return 1

  verify_aws_identity_and_region || return 1

  local raw
  raw="$(resolve_provision_order "$scope")" || {
    _orchestrator_error "unable to resolve a provision order for scope: ${scope}"
    return 1
  }

  local -a order=()
  local step
  while IFS= read -r step; do
    [[ -n "$step" ]] && order+=("$step")
  done <<< "$raw"

  if [[ "${#order[@]}" -eq 0 ]]; then
    _orchestrator_error "resolved an empty provision order for scope: ${scope}"
    return 1
  fi

  # Package fragments are loaded before graph pre-resolution: they define
  # the real handler functions that the checks below (and dispatch later)
  # must be able to name and call.
  _orchestrator_load_package_fragments provision "${order[@]}" || return 1

  # Fail-closed graph pre-resolution across the whole order, entirely
  # before any local path/lock is created.
  local requirement
  for step in "${order[@]}"; do
    requirement="$(implementation_requirement_for_scope "$step")" || {
      _orchestrator_error "no implementation-requirement mapping for scope: ${step}"
      return 1
    }
    case "$requirement" in
      external-work-package-*)
        _orchestrator_error "${step} requires work package ${requirement##*-}"
        return 1
        ;;
    esac
  done

  local symbol
  for step in "${order[@]}"; do
    requirement="$(implementation_requirement_for_scope "$step")" || {
      _orchestrator_error "no implementation-requirement mapping for scope: ${step}"
      return 1
    }
    if [[ "$requirement" == "external-existing-platform" ]]; then
      continue
    fi
    symbol="$(provision_handler_for_scope "$step")" || {
      _orchestrator_error "no provision handler is mapped for scope: ${step}"
      return 1
    }
  done

  initialize_orchestration_paths "$environment_name" || return 1
  acquire_orchestration_lock || return 1

  export UNIFIED_AUTO_APPROVE="$auto_approve"

  local status=0
  dispatch_scope_handler provision "$scope" || status=1

  cleanup_orchestration_artifacts "$status"
}

# ---------------------------------------------------------------------------
# Unified verify
# ---------------------------------------------------------------------------
#
# Preflight slots (foundation-contract, aws-identity-region,
# kubernetes-context, eks-authentication-mode) are dispatched directly to
# this foundation's own already-implemented guard functions, not through
# scope-registry.sh's placeholder preflight-verifier symbols: the registry's
# own comments state those symbols "require orchestrator verifier wiring
# (later task)". Component-scope and smoke slots are dispatched generically
# through `verification_handler_for_slot`, so they naturally fail closed
# today (their real implementations are external work packages) with no
# future orchestrator.sh change required once those symbols are wired.

_orchestrator_run_verify() {
  local environment_name="$1"
  shift || true

  local mode="full"
  local mode_given="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --preflight|--full|--smoke-test)
        if [[ "$mode_given" == "true" ]]; then
          _orchestrator_error "unified verification accepts only one mode flag"
          return 1
        fi
        mode="${1#--}"
        mode_given="true"
        shift
        ;;
      --bootstrap-platform-controllers|--keep-signoz-namespace)
        _orchestrator_error "unified verification does not accept legacy-only option: $1"
        return 1
        ;;
      *)
        _orchestrator_error "unknown unified verification argument: $1"
        return 1
        ;;
    esac
  done

  local raw
  raw="$(verification_slots_for_mode "$mode")" || {
    _orchestrator_error "unable to resolve a verification order for mode: ${mode}"
    return 1
  }

  local -a slots=()
  local slot
  while IFS= read -r slot; do
    [[ -n "$slot" ]] && slots+=("$slot")
  done <<< "$raw"

  if [[ "${#slots[@]}" -eq 0 ]]; then
    _orchestrator_error "resolved an empty verification order for mode: ${mode}"
    return 1
  fi

  # Fail-closed graph pre-resolution: every slot must have a mapped handler
  # symbol before anything runs.
  for slot in "${slots[@]}"; do
    verification_handler_for_slot "$slot" >/dev/null || {
      _orchestrator_error "no verifier handler is mapped for slot: ${slot}"
      return 1
    }
  done

  initialize_orchestration_paths "$environment_name" || return 1

  local failures=0
  local symbol
  for slot in "${slots[@]}"; do
    case "$slot" in
      foundation-contract)
        printf 'PASS: foundation-contract (environment loaded and validated)\n'
        ;;
      aws-identity-region)
        if verify_aws_identity_and_region; then
          printf 'PASS: aws-identity-region\n'
        else
          printf 'FAIL: aws-identity-region\n' >&2
          failures=$((failures + 1))
        fi
        ;;
      kubernetes-context)
        if verify_kubernetes_context; then
          printf 'PASS: kubernetes-context\n'
        else
          printf 'FAIL: kubernetes-context\n' >&2
          failures=$((failures + 1))
        fi
        ;;
      eks-authentication-mode)
        if verify_eks_authentication_mode; then
          printf 'PASS: eks-authentication-mode\n'
        else
          printf 'FAIL: eks-authentication-mode\n' >&2
          failures=$((failures + 1))
        fi
        ;;
      *)
        symbol="$(verification_handler_for_slot "$slot")"
        if "$symbol"; then
          printf 'PASS: %s\n' "$slot"
        else
          printf 'FAIL: %s\n' "$slot" >&2
          failures=$((failures + 1))
        fi
        ;;
    esac
  done

  local status=0
  [[ "$failures" -gt 0 ]] && status=1
  cleanup_orchestration_artifacts "$status"
}

# ---------------------------------------------------------------------------
# Unified destroy: confirmation-requirement map
# ---------------------------------------------------------------------------
#
# The immutable, foundation-owned closed confirmation-requirement map.
# Populates REQUIRED_CONFIRMATION_SCOPES and REQUIRED_CONFIRMATIONS (globals,
# Bash 3.2 has no namerefs) in the exact given order for exactly the
# persistent scopes this map covers that are present in that order. The
# PostgreSQL final-snapshot identifier is derived from the given timestamp
# (the confirmation artifact's own immutable created_at on every
# recomputation, so the value is byte-identical on the preparation pass and
# every later validation of the same artifact) rather than the wall clock at
# validation time.

REQUIRED_CONFIRMATION_SCOPES=()
REQUIRED_CONFIRMATIONS=()

_orchestrator_compute_required_confirmations() {
  local environment_name="$1"
  local account_id="$2"
  local snapshot_timestamp="$3"
  shift 3

  REQUIRED_CONFIRMATION_SCOPES=()
  REQUIRED_CONFIRMATIONS=()

  local step
  for step in "$@"; do
    case "$step" in
      eks-platform)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:eks-platform:${EKS_CLUSTER_NAME}:delete-cluster")
        ;;
      boomi-runtime)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:boomi-runtime:runtime/${BOOMI_NAMESPACE}:retain-efs")
        ;;
      mongodb)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:mongodb:psmdb/${MONGODB_NAMESPACE}/oms:delete-cluster-and-pvcs")
        ;;
      postgresql-core)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:postgresql-core:db/oms-${environment_name}-core:final-snapshot=oms-${environment_name}-core-final-${snapshot_timestamp}")
        ;;
      postgresql-brand)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:postgresql-brand:db/oms-${environment_name}-brand:final-snapshot=oms-${environment_name}-brand-final-${snapshot_timestamp}")
        ;;
      *) ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Unified destroy: pre-destroy guard callback protocol
# ---------------------------------------------------------------------------

_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=""
_ORCHESTRATOR_GUARD_RESULT_SCOPES=()
_ORCHESTRATOR_GUARD_RESULT_STATUSES=()
_ORCHESTRATOR_GUARD_RESULT_IDENTITIES=()
_ORCHESTRATOR_GUARD_RESULT_DIGESTS=()
_ORCHESTRATOR_GUARD_RESULT_SUMMARIES=()
_ORCHESTRATOR_GUARD_ABORTED="false"
_ORCHESTRATOR_GUARD_FAILURE_CODE=""
_ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE=""
_ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX=""
_ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX=""
_ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS=""

_orchestrator_reset_guard_state() {
  _ORCHESTRATOR_GUARD_ACTIVE_SCOPE=""
  _ORCHESTRATOR_GUARD_RESULT_SCOPES=()
  _ORCHESTRATOR_GUARD_RESULT_STATUSES=()
  _ORCHESTRATOR_GUARD_RESULT_IDENTITIES=()
  _ORCHESTRATOR_GUARD_RESULT_DIGESTS=()
  _ORCHESTRATOR_GUARD_RESULT_SUMMARIES=()
  _ORCHESTRATOR_GUARD_ABORTED="false"
  _ORCHESTRATOR_GUARD_FAILURE_CODE=""
  _ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE=""
  _ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX=""
  _ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX=""
  _ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS=""
}

_orchestrator_guard_abort() {
  if [[ "$_ORCHESTRATOR_GUARD_ABORTED" == "true" ]]; then
    return 0
  fi
  _ORCHESTRATOR_GUARD_ABORTED="true"
  _ORCHESTRATOR_GUARD_FAILURE_CODE="$1"
  _ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE="$2"
  _ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX="$3"
  _ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS="$4"
  case "$1" in
    GUARD_MISSING_RESULT|GUARD_OUT_OF_PHASE)
      _ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX=""
      ;;
    *)
      _ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX="$(( ${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]} - 1 ))"
      ;;
  esac
}

# `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity>
# <sha256-digest> <summary-code>` -- the exact five-argument foundation
# callback. Only accepted while the exact given scope's guard phase is
# active; every other case (no active phase, wrong scope, a second result
# for an already-recorded scope, or a malformed field) aborts guard
# execution with a closed foundation failure code and records the
# already-received results (including the offending one) in arrival order.

record_pre_destroy_guard_result() {
  local scope="${1:-}"
  local guard_status="${2:-}"
  local resource_identity="${3:-}"
  local evidence_digest="${4:-}"
  local summary_code="${5:-}"

  if [[ "$_ORCHESTRATOR_GUARD_ABORTED" == "true" ]]; then
    return 1
  fi

  if [[ -z "$_ORCHESTRATOR_GUARD_ACTIVE_SCOPE" ]]; then
    _orchestrator_guard_abort "GUARD_OUT_OF_PHASE" "$scope" "" ""
    return 1
  fi

  if [[ "$scope" != "$_ORCHESTRATOR_GUARD_ACTIVE_SCOPE" ]]; then
    # A scope that already completed its own guard turn earlier in this
    # same operation reporting again is out-of-order (the scope is real
    # for this operation, just reported out of turn); every other scope
    # value -- including one never part of this operation's resolved
    # destroy order at all -- is simply the wrong scope.
    local already_reported_scope
    for already_reported_scope in "${_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]:-}"; do
      if [[ -n "$already_reported_scope" && "$already_reported_scope" == "$scope" ]]; then
        _orchestrator_guard_abort "GUARD_OUT_OF_ORDER" "$_ORCHESTRATOR_GUARD_ACTIVE_SCOPE" "" ""
        return 1
      fi
    done
    _orchestrator_guard_abort "GUARD_WRONG_SCOPE" "$_ORCHESTRATOR_GUARD_ACTIVE_SCOPE" "" ""
    return 1
  fi

  local existing
  for existing in "${_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]:-}"; do
    if [[ -n "$existing" && "$existing" == "$scope" ]]; then
      _ORCHESTRATOR_GUARD_RESULT_SCOPES+=("$scope")
      _ORCHESTRATOR_GUARD_RESULT_STATUSES+=("$guard_status")
      _ORCHESTRATOR_GUARD_RESULT_IDENTITIES+=("$resource_identity")
      _ORCHESTRATOR_GUARD_RESULT_DIGESTS+=("$evidence_digest")
      _ORCHESTRATOR_GUARD_RESULT_SUMMARIES+=("$summary_code")
      _orchestrator_guard_abort "GUARD_DUPLICATE_RESULT" "$scope" "" ""
      return 1
    fi
  done

  case "$guard_status" in
    PASS|FAIL) ;;
    *)
      _ORCHESTRATOR_GUARD_RESULT_SCOPES+=("$scope")
      _ORCHESTRATOR_GUARD_RESULT_STATUSES+=("$guard_status")
      _ORCHESTRATOR_GUARD_RESULT_IDENTITIES+=("$resource_identity")
      _ORCHESTRATOR_GUARD_RESULT_DIGESTS+=("$evidence_digest")
      _ORCHESTRATOR_GUARD_RESULT_SUMMARIES+=("$summary_code")
      _orchestrator_guard_abort "GUARD_MALFORMED_RESULT" "$scope" "" ""
      return 1
      ;;
  esac

  if [[ ! "$resource_identity" =~ ^[A-Za-z0-9][A-Za-z0-9._/@+=:-]{0,255}$ ]] \
    || [[ ! "$evidence_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || [[ ! "$summary_code" =~ ^[A-Z][A-Z0-9_]{0,63}$ ]]; then
    _ORCHESTRATOR_GUARD_RESULT_SCOPES+=("$scope")
    _ORCHESTRATOR_GUARD_RESULT_STATUSES+=("$guard_status")
    _ORCHESTRATOR_GUARD_RESULT_IDENTITIES+=("$resource_identity")
    _ORCHESTRATOR_GUARD_RESULT_DIGESTS+=("$evidence_digest")
    _ORCHESTRATOR_GUARD_RESULT_SUMMARIES+=("$summary_code")
    _orchestrator_guard_abort "GUARD_MALFORMED_RESULT" "$scope" "" ""
    return 1
  fi

  _ORCHESTRATOR_GUARD_RESULT_SCOPES+=("$scope")
  _ORCHESTRATOR_GUARD_RESULT_STATUSES+=("$guard_status")
  _ORCHESTRATOR_GUARD_RESULT_IDENTITIES+=("$resource_identity")
  _ORCHESTRATOR_GUARD_RESULT_DIGESTS+=("$evidence_digest")
  _ORCHESTRATOR_GUARD_RESULT_SUMMARIES+=("$summary_code")

  if [[ "$guard_status" == "FAIL" ]]; then
    _orchestrator_guard_abort "GUARD_FAIL" "$scope" "" ""
    return 1
  fi

  return 0
}

_orchestrator_dispatch_guard() {
  local scope="$1"
  local guard_index="$2"
  local symbol
  symbol="$(pre_destroy_guard_for_scope "$scope")" || return 1

  local result_count_before="${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}"
  _ORCHESTRATOR_GUARD_ACTIVE_SCOPE="$scope"

  local wrapper_status=0
  "$symbol" || wrapper_status=$?

  _ORCHESTRATOR_GUARD_ACTIVE_SCOPE=""

  if [[ "$_ORCHESTRATOR_GUARD_ABORTED" == "true" ]]; then
    return 1
  fi

  local result_count_after="${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}"
  if [[ "$result_count_after" -eq "$result_count_before" ]]; then
    _orchestrator_guard_abort "GUARD_MISSING_RESULT" "$scope" "$guard_index" ""
    return 1
  fi

  local last_index=$((result_count_after - 1))
  local recorded_status="${_ORCHESTRATOR_GUARD_RESULT_STATUSES[$last_index]}"

  if [[ "$recorded_status" == "PASS" && "$wrapper_status" -ne 0 ]]; then
    _orchestrator_guard_abort "GUARD_WRAPPER_STATUS_DISAGREEMENT" "$scope" "$guard_index" "$wrapper_status"
    return 1
  fi
  if [[ "$recorded_status" == "FAIL" && "$wrapper_status" -eq 0 ]]; then
    _orchestrator_guard_abort "GUARD_WRAPPER_STATUS_DISAGREEMENT" "$scope" "$guard_index" "$wrapper_status"
    return 1
  fi

  return 0
}

_orchestrator_build_guard_results_json() {
  local json="["
  local first="true"
  local i
  for ((i = 0; i < ${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}; i++)); do
    if [[ "$first" == "true" ]]; then
      first="false"
    else
      json+=","
    fi
    json+="{\"scope\":\"${_ORCHESTRATOR_GUARD_RESULT_SCOPES[$i]}\",\"status\":\"${_ORCHESTRATOR_GUARD_RESULT_STATUSES[$i]}\",\"resource_identity\":\"${_ORCHESTRATOR_GUARD_RESULT_IDENTITIES[$i]}\",\"evidence_digest\":\"${_ORCHESTRATOR_GUARD_RESULT_DIGESTS[$i]}\",\"summary_code\":\"${_ORCHESTRATOR_GUARD_RESULT_SUMMARIES[$i]}\"}"
  done
  json+="]"
  printf '%s' "$json"
}

_orchestrator_build_failure_json() {
  local code="$1"
  local expected_scope="$2"
  local guard_index="$3"
  local result_index="$4"
  local wrapper_status="$5"
  local guard_index_json="null"
  local result_index_json="null"
  local wrapper_status_json="null"

  [[ -n "$guard_index" ]] && guard_index_json="$guard_index"
  [[ -n "$result_index" ]] && result_index_json="$result_index"
  [[ -n "$wrapper_status" ]] && wrapper_status_json="$wrapper_status"

  printf '{"code":"%s","expected_scope":"%s","guard_index":%s,"result_index":%s,"wrapper_status":%s}' \
    "$code" "$expected_scope" "$guard_index_json" "$result_index_json" "$wrapper_status_json"
}

# ---------------------------------------------------------------------------
# Unified destroy
# ---------------------------------------------------------------------------

_orchestrator_run_destroy() {
  local environment_name="$1"
  shift || true

  if [[ $# -eq 0 ]]; then
    _orchestrator_error "unified destroy requires a scope"
    return 1
  fi

  local scope="$1"
  shift || true

  local auto_approve="false"
  local confirmation_artifact_given="false"
  local confirmation_artifact_path=""
  local -a cli_confirmations=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-approve)
        auto_approve="true"
        shift
        ;;
      --confirmation-artifact)
        if [[ "$confirmation_artifact_given" == "true" ]]; then
          _orchestrator_error "--confirmation-artifact may be given at most once"
          return 1
        fi
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          _orchestrator_error "--confirmation-artifact requires a value"
          return 1
        fi
        confirmation_artifact_path="$2"
        confirmation_artifact_given="true"
        shift 2
        ;;
      --confirmation-artifact=*)
        _orchestrator_error "--confirmation-artifact must be given as two separate arguments, not --confirmation-artifact=<path>"
        return 1
        ;;
      --confirm)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          _orchestrator_error "--confirm requires a value"
          return 1
        fi
        cli_confirmations+=("$2")
        shift 2
        ;;
      *)
        _orchestrator_error "unknown unified destroy argument: $1"
        return 1
        ;;
    esac
  done

  local -a seen_confirmations=()
  local candidate_confirmation
  for candidate_confirmation in "${cli_confirmations[@]:-}"; do
    [[ -n "$candidate_confirmation" ]] || continue
    if _orchestrator_in_list "$candidate_confirmation" "${seen_confirmations[@]:-}"; then
      _orchestrator_error "duplicate --confirm value: ${candidate_confirmation}"
      return 1
    fi
    seen_confirmations+=("$candidate_confirmation")
  done

  require_environment_mutation_authorized "$environment_name" || return 1

  verify_aws_identity_and_region || return 1

  local raw
  raw="$(resolve_destroy_order "$scope")" || {
    _orchestrator_error "unable to resolve a destroy order for scope: ${scope}"
    return 1
  }

  local -a order=()
  local step
  while IFS= read -r step; do
    [[ -n "$step" ]] && order+=("$step")
  done <<< "$raw"

  if [[ "${#order[@]}" -eq 0 ]]; then
    _orchestrator_error "resolved an empty destroy order for scope: ${scope}"
    return 1
  fi

  # Package fragments are loaded before graph pre-resolution: they define
  # the real guard/handler functions that the checks below (and dispatch
  # later) must be able to name and call.
  _orchestrator_load_package_fragments destroy "${order[@]}" || return 1

  # Fail-closed graph pre-resolution across the whole order, entirely
  # before any local path/lock is created.
  local -a guardable_steps=()
  for step in "${order[@]}"; do
    if _scope_registry_scope_requires_pre_destroy_guard "$step"; then
      pre_destroy_guard_for_scope "$step" >/dev/null || {
        _orchestrator_error "no pre-destroy guard is mapped for scope: ${step}"
        return 1
      }
      guardable_steps+=("$step")
    fi
    destroy_handler_for_scope "$step" >/dev/null || {
      _orchestrator_error "no destroy handler is mapped for scope: ${step}"
      return 1
    }
  done

  local expected_account_id
  expected_account_id="$(immutable_environment_value "$environment_name" EXPECTED_AWS_ACCOUNT_ID)" || {
    _orchestrator_error "unable to resolve the immutable account id contract for ${environment_name}"
    return 1
  }

  # `backend` and `access-governance` are the only ordinary destroy targets
  # with no pre-destroy guard at all (their destroy handlers are hard-
  # blocked, not a guarded conditional destroy; see scope-registry.sh). For
  # exactly that case there is nothing for the confirmation-artifact/guard-
  # evidence protocol to gate, and the evidence schema requires a non-empty
  # guard_results array, so this narrow case dispatches its (always-failing)
  # handler directly without the two-pass protocol.
  if [[ "${#guardable_steps[@]}" -eq 0 ]]; then
    initialize_orchestration_paths "$environment_name" || return 1
    acquire_orchestration_lock || return 1
    local direct_status=0
    for step in "${order[@]}"; do
      local direct_symbol
      direct_symbol="$(destroy_handler_for_scope "$step")"
      "$direct_symbol" || { direct_status=1; break; }
    done
    cleanup_orchestration_artifacts "$direct_status"
    return $?
  fi

  if [[ "$confirmation_artifact_given" == "false" ]]; then
    _orchestrator_destroy_preparation_pass \
      "$environment_name" "$scope" "$expected_account_id" "${#cli_confirmations[@]}" "${order[@]}"
    return $?
  fi

  _orchestrator_destroy_second_pass \
    "$environment_name" "$scope" "$expected_account_id" "$auto_approve" \
    "$confirmation_artifact_path" "${#cli_confirmations[@]}" "${order[@]}" -- "${cli_confirmations[@]:-}"
}

_orchestrator_destroy_preparation_pass() {
  local environment_name="$1"
  local scope="$2"
  local expected_account_id="$3"
  local cli_confirmation_count="$4"
  shift 4
  local -a order=("$@")

  if [[ "$cli_confirmation_count" -gt 0 ]]; then
    _orchestrator_error "the preparation pass does not accept --confirm without --confirmation-artifact"
    return 1
  fi

  local created_epoch
  created_epoch="$(_orchestrator_now_epoch)"
  local expires_epoch=$((created_epoch + 900))
  local created_at expires_at
  created_at="$(_orchestrator_format_timestamp "$created_epoch")"
  expires_at="$(_orchestrator_format_timestamp "$expires_epoch")"
  local snapshot_timestamp
  snapshot_timestamp="$(printf '%s' "$created_at" | tr -d ':-')"

  _orchestrator_compute_required_confirmations \
    "$environment_name" "$expected_account_id" "$snapshot_timestamp" "${order[@]}"

  local operation_id
  operation_id="$(_orchestrator_generate_operation_id)"

  initialize_orchestration_paths "$environment_name" || return 1
  acquire_orchestration_lock || return 1

  local artifact_path="${GENERATED_DIR}/destroy-confirmation.${operation_id}.json"
  local artifact_relative_path=".local/${environment_name}/generated/destroy-confirmation.${operation_id}.json"

  local -a create_args=(
    create
    --path "$artifact_path"
    --operation-id "$operation_id"
    --created-at "$created_at"
    --expires-at "$expires_at"
    --environment "$environment_name"
    --account-id "$expected_account_id"
    --requested-scope "$scope"
  )
  local step
  for step in "${order[@]}"; do
    create_args+=(--resolved-scope "$step")
  done
  for step in "${REQUIRED_CONFIRMATIONS[@]:-}"; do
    [[ -n "$step" ]] && create_args+=(--confirmation "$step")
  done

  if ! "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/confirmation-artifact.py" "${create_args[@]}"; then
    _orchestrator_error "unable to create confirmation artifact"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  printf 'Confirmation artifact: %s\n' "$artifact_relative_path"
  printf 'Re-run with:\n'
  printf '  --confirmation-artifact %s \\\n' "$artifact_relative_path"
  for step in "${REQUIRED_CONFIRMATIONS[@]:-}"; do
    [[ -n "$step" ]] && printf '  --confirm %s \\\n' "$step"
  done

  # The artifact write is the sole mutation permitted on this pass and must
  # survive this intentional nonzero exit, so it is never registered with
  # `register_orchestration_artifact`; cleanup only releases the lock.
  cleanup_orchestration_artifacts 1
}

_orchestrator_destroy_second_pass() {
  local environment_name="$1"
  local scope="$2"
  local expected_account_id="$3"
  local auto_approve="$4"
  local confirmation_artifact_path="$5"
  local cli_confirmation_count="$6"
  shift 6

  local -a order=()
  local -a cli_confirmations=()
  local collecting_confirmations="false"
  local arg
  for arg in "$@"; do
    if [[ "$collecting_confirmations" == "true" ]]; then
      cli_confirmations+=("$arg")
      continue
    fi
    if [[ "$arg" == "--" ]]; then
      collecting_confirmations="true"
      continue
    fi
    order+=("$arg")
  done

  case "$confirmation_artifact_path" in
    /*|*..*)
      _orchestrator_error "invalid --confirmation-artifact path: ${confirmation_artifact_path}"
      return 1
      ;;
    ".local/${environment_name}/generated/destroy-confirmation."*".json") ;;
    *)
      _orchestrator_error "invalid --confirmation-artifact path: ${confirmation_artifact_path}"
      return 1
      ;;
  esac

  initialize_orchestration_paths "$environment_name" || return 1
  acquire_orchestration_lock || return 1

  local absolute_artifact_path="${_ORCHESTRATOR_ROOT_DIR}/${confirmation_artifact_path}"
  local artifact_dirname
  artifact_dirname="$(dirname "$absolute_artifact_path")"
  local resolved_parent
  resolved_parent="$(cd "$artifact_dirname" 2>/dev/null && pwd)" || {
    _orchestrator_error "confirmation artifact directory does not exist: ${artifact_dirname}"
    cleanup_orchestration_artifacts 1
    return 1
  }
  if [[ "$resolved_parent" != "$GENERATED_DIR" ]]; then
    _orchestrator_error "confirmation artifact must be located directly beneath ${GENERATED_DIR}"
    cleanup_orchestration_artifacts 1
    return 1
  fi
  if [[ -L "$absolute_artifact_path" ]]; then
    _orchestrator_error "confirmation artifact must not be a symlink: ${absolute_artifact_path}"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local artifact_operation_id
  artifact_operation_id="$(basename "$absolute_artifact_path")"
  artifact_operation_id="${artifact_operation_id#destroy-confirmation.}"
  artifact_operation_id="${artifact_operation_id%.json}"

  local artifact_fields
  if ! artifact_fields="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/confirmation-artifact.py" fields --path "$absolute_artifact_path" 2>/dev/null)"; then
    _orchestrator_error "unable to read confirmation artifact: ${confirmation_artifact_path}"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local artifact_created_at="" artifact_resolved_scopes_csv="" artifact_confirmations_csv=""
  local field_key field_value
  while IFS='=' read -r field_key field_value; do
    case "$field_key" in
      created_at) artifact_created_at="$field_value" ;;
      resolved_scopes) artifact_resolved_scopes_csv="$field_value" ;;
      confirmations) artifact_confirmations_csv="$field_value" ;;
    esac
  done <<< "$artifact_fields"

  if [[ -z "$artifact_created_at" ]]; then
    _orchestrator_error "confirmation artifact is missing created_at: ${confirmation_artifact_path}"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local snapshot_timestamp
  snapshot_timestamp="$(printf '%s' "$artifact_created_at" | tr -d ':-')"

  _orchestrator_compute_required_confirmations \
    "$environment_name" "$expected_account_id" "$snapshot_timestamp" "${order[@]}"

  if [[ "${#REQUIRED_CONFIRMATIONS[@]}" -ne "$cli_confirmation_count" ]]; then
    _orchestrator_error "confirmation set is incomplete for this destroy request"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local index
  for ((index = 0; index < ${#REQUIRED_CONFIRMATIONS[@]}; index++)); do
    if [[ "${REQUIRED_CONFIRMATIONS[$index]}" != "${cli_confirmations[$index]:-}" ]]; then
      _orchestrator_error "confirmation value at position $((index + 1)) does not match the required value for this destroy request"
      cleanup_orchestration_artifacts 1
      return 1
    fi
  done

  local step

  # `_orchestrator_build_validate_args <now-timestamp>` builds the fixed
  # request-binding argument vector for confirmation-artifact.py's
  # `validate` subcommand; only the `--now` value changes between the
  # initial validation and the immediately-pre-consumption revalidation
  # below, so both call sites share this builder instead of risking a
  # positional-index mistake from mutating a previously built array.
  _orchestrator_build_validate_args() {
    local now_timestamp="$1"
    _ORCHESTRATOR_VALIDATE_ARGS=(
      validate
      --path "$absolute_artifact_path"
      --now "$now_timestamp"
      --operation-id "$artifact_operation_id"
      --environment "$environment_name"
      --account-id "$expected_account_id"
      --requested-scope "$scope"
    )
    local builder_step
    for builder_step in "${order[@]}"; do
      _ORCHESTRATOR_VALIDATE_ARGS+=(--resolved-scope "$builder_step")
    done
    for builder_step in "${cli_confirmations[@]:-}"; do
      [[ -n "$builder_step" ]] && _ORCHESTRATOR_VALIDATE_ARGS+=(--confirmation "$builder_step")
    done
  }

  local now_epoch
  now_epoch="$(_orchestrator_now_epoch)"
  _orchestrator_build_validate_args "$(_orchestrator_format_timestamp "$now_epoch")"

  local confirmation_sha256
  if ! confirmation_sha256="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/confirmation-artifact.py" "${_ORCHESTRATOR_VALIDATE_ARGS[@]}")"; then
    _orchestrator_error "confirmation artifact failed validation against the current request"
    cleanup_orchestration_artifacts 1
    return 1
  fi
  confirmation_sha256="${confirmation_sha256#sha256:}"

  # ------------------------------------------------------------------
  # Guard-capture phase: dispatch every mapped read-only pre-destroy
  # guard in exact reverse destroy order.
  # ------------------------------------------------------------------

  _orchestrator_reset_guard_state

  local guard_index=0
  for step in "${order[@]}"; do
    if _scope_registry_scope_requires_pre_destroy_guard "$step"; then
      _orchestrator_dispatch_guard "$step" "$guard_index" || break
      guard_index=$((guard_index + 1))
    fi
  done

  if [[ "$_ORCHESTRATOR_GUARD_ABORTED" == "true" ]]; then
    local received_results_json
    received_results_json="$(_orchestrator_build_guard_results_json)"
    local failure_json
    failure_json="$(_orchestrator_build_failure_json \
      "$_ORCHESTRATOR_GUARD_FAILURE_CODE" \
      "$_ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE" \
      "$_ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX" \
      "$_ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX" \
      "$_ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS")"

    local -a failure_args=(
      write-guard-failure
      --path "${EVIDENCE_DIR}/destroy-guard-failure.${artifact_operation_id}.json"
      --operation-id "$artifact_operation_id"
      --environment "$environment_name"
      --account-id "$expected_account_id"
      --requested-scope "$scope"
      --received-results-json "$received_results_json"
      --failure-json "$failure_json"
      --created-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")"
      --confirmation-artifact-sha256 "$confirmation_sha256"
    )
    for step in "${order[@]}"; do
      failure_args+=(--resolved-scope "$step")
    done

    "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${failure_args[@]}" \
      || _orchestrator_error "unable to write guard-failure record (additional foundation failure)"

    _orchestrator_error "pre-destroy guard failure (${_ORCHESTRATOR_GUARD_FAILURE_CODE}); destroy aborted before evidence, approval, or dispatch"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  # ------------------------------------------------------------------
  # All guards passed: write and re-read all-pass evidence.
  # ------------------------------------------------------------------

  local guard_results_json
  guard_results_json="$(_orchestrator_build_guard_results_json)"

  local evidence_path="${EVIDENCE_DIR}/pre-destroy-guards.${artifact_operation_id}.json"
  local -a evidence_args=(
    write-evidence
    --path "$evidence_path"
    --operation-id "$artifact_operation_id"
    --environment "$environment_name"
    --account-id "$expected_account_id"
    --requested-scope "$scope"
    --guard-results-json "$guard_results_json"
    --created-at "$artifact_created_at"
    --expires-at "$(_orchestrator_format_timestamp "$(( $(_orchestrator_parse_timestamp_to_epoch "$artifact_created_at") + 900 ))")"
    --confirmation-artifact-sha256 "$confirmation_sha256"
  )
  for step in "${order[@]}"; do
    evidence_args+=(--resolved-scope "$step")
  done

  if ! "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${evidence_args[@]}"; then
    _orchestrator_error "unable to write all-pass guard evidence; destroy aborted before approval or dispatch"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local evidence_sha256
  evidence_sha256="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" digest --path "$evidence_path")" || {
    _orchestrator_error "unable to compute all-pass guard evidence digest"
    cleanup_orchestration_artifacts 1
    return 1
  }
  evidence_sha256="${evidence_sha256#sha256:}"

  # ------------------------------------------------------------------
  # Interactive approval unless auto-approved.
  # ------------------------------------------------------------------

  if [[ "$auto_approve" != "true" ]]; then
    local reply=""
    printf 'Type the exact word yes to proceed with destroying %s in %s: ' "$scope" "$environment_name"
    read -r reply || reply=""
    if [[ "$reply" != "yes" ]]; then
      _orchestrator_error "destroy approval was not given; destroy aborted before consumption or dispatch"
      cleanup_orchestration_artifacts 1
      return 1
    fi
  fi

  # ------------------------------------------------------------------
  # Revalidate the confirmation artifact and the all-pass evidence
  # (through a fresh no-follow read of each), then atomically consume the
  # confirmation artifact. Approval can take arbitrary human time, so both
  # are re-read here rather than trusting the earlier reads.
  # ------------------------------------------------------------------

  local revalidated_evidence_sha256
  revalidated_evidence_sha256="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" digest --path "$evidence_path")" || {
    _orchestrator_error "unable to revalidate all-pass guard evidence immediately before consumption"
    cleanup_orchestration_artifacts 1
    return 1
  }
  if [[ "$revalidated_evidence_sha256" != "sha256:${evidence_sha256}" ]]; then
    _orchestrator_error "all-pass guard evidence changed since it was written; destroy aborted before consumption"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  now_epoch="$(_orchestrator_now_epoch)"
  _orchestrator_build_validate_args "$(_orchestrator_format_timestamp "$now_epoch")"
  local revalidated_confirmation_sha256
  if ! revalidated_confirmation_sha256="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/confirmation-artifact.py" "${_ORCHESTRATOR_VALIDATE_ARGS[@]}")"; then
    _orchestrator_error "confirmation artifact failed revalidation immediately before consumption"
    cleanup_orchestration_artifacts 1
    return 1
  fi
  if [[ "$revalidated_confirmation_sha256" != "sha256:${confirmation_sha256}" ]]; then
    _orchestrator_error "confirmation artifact changed since guard evidence was bound to it; destroy aborted before consumption"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  if ! "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/confirmation-artifact.py" consume --path "$absolute_artifact_path" >/dev/null; then
    _orchestrator_error "unable to atomically consume confirmation artifact; destroy aborted before dispatch"
    cleanup_orchestration_artifacts 1
    return 1
  fi

  "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" write-status \
    --evidence-dir "$EVIDENCE_DIR" \
    --operation-id "$artifact_operation_id" \
    --status consumed \
    --evidence-sha256 "$evidence_sha256" \
    --recorded-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")" \
    || _orchestrator_error "unable to record consumed evidence status (continuing to dispatch; this is itself a foundation concern)"

  # ------------------------------------------------------------------
  # Dispatch destroy handlers in the same reverse destroy order.
  # ------------------------------------------------------------------

  export UNIFIED_AUTO_APPROVE="$auto_approve"

  # Each handler receives only its own ordered, byte-for-byte-unchanged
  # confirmation subset (the validated CLI values whose REQUIRED_
  # CONFIRMATION_SCOPES entry equals this handler's scope) as positional
  # arguments -- never the artifact path or any other operation metadata.
  # A handler with no confirmation requirement (e.g. eks-access) receives
  # an empty argument list.
  local dispatch_status=0
  for step in "${order[@]}"; do
    local handler_symbol
    handler_symbol="$(destroy_handler_for_scope "$step")"

    local -a handler_confirmations=()
    local confirmation_index
    for ((confirmation_index = 0; confirmation_index < ${#REQUIRED_CONFIRMATION_SCOPES[@]}; confirmation_index++)); do
      if [[ "${REQUIRED_CONFIRMATION_SCOPES[$confirmation_index]}" == "$step" ]]; then
        handler_confirmations+=("${cli_confirmations[$confirmation_index]}")
      fi
    done

    if [[ "${#handler_confirmations[@]}" -gt 0 ]]; then
      if ! "$handler_symbol" "${handler_confirmations[@]}"; then
        dispatch_status=1
        break
      fi
    else
      if ! "$handler_symbol"; then
        dispatch_status=1
        break
      fi
    fi
  done

  local terminal_status="success"
  [[ "$dispatch_status" -ne 0 ]] && terminal_status="failure"

  local -a status_args=(
    write-status
    --evidence-dir "$EVIDENCE_DIR"
    --operation-id "$artifact_operation_id"
    --status "$terminal_status"
    --evidence-sha256 "$evidence_sha256"
    --recorded-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")"
  )
  if [[ "$terminal_status" == "failure" ]]; then
    status_args+=(--failure-code DESTROY_HANDLER_FAILED)
  fi
  "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${status_args[@]}" \
    || _orchestrator_error "unable to record terminal evidence status ${terminal_status} (original destroy status is preserved)"

  cleanup_orchestration_artifacts "$dispatch_status"
}

# ---------------------------------------------------------------------------
# run_unified_command: single public entry point
# ---------------------------------------------------------------------------
#
# `run_unified_command <provision|destroy|verify> --env <dev|uat> ...`
#
# 1. Reject execution overrides.
# 2. Parse the exact leading --env <dev|uat> form (no other spelling: no
#    `--env=uat`, no later-position `--env`, no repeated `--env`).
# 3. Load and validate the closed environment contract.
# 4. Dispatch to the operation-specific implementation, which parses the
#    scope/options, calls `require_environment_mutation_authorized`, and
#    only then verifies the active AWS account/Region -- in that order --
#    for provision/destroy, so that a missing scope, an unknown option, or
#    a blocked mutation is rejected before any external command runs. The
#    verify operation performs this same account/Region check itself as
#    one of its own preflight/full/smoke slots and reports it individually
#    rather than failing the whole command up front.

run_unified_command() {
  local operation="${1:-}"
  shift || true

  case "$operation" in
    provision|destroy|verify) ;;
    *)
      _orchestrator_error "run_unified_command requires operation provision, destroy, or verify"
      return 1
      ;;
  esac

  reject_execution_environment_overrides || return 1

  if [[ "${1:-}" != "--env" ]]; then
    _orchestrator_error "unified commands require a leading --env <dev|uat> argument"
    return 1
  fi
  shift || true

  local environment_name="${1:-}"
  case "$environment_name" in
    dev|uat) ;;
    *)
      _orchestrator_error "unified commands require --env dev or --env uat, got: ${environment_name:-<empty>}"
      return 1
      ;;
  esac
  shift || true

  load_platform_env "$environment_name" || return 1

  case "$operation" in
    provision)
      _orchestrator_run_provision "$environment_name" "$@"
      ;;
    destroy)
      _orchestrator_run_destroy "$environment_name" "$@"
      ;;
    verify)
      _orchestrator_run_verify "$environment_name" "$@"
      ;;
  esac
}
