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
# reaches this file at all and execs the frozen legacy-dev wrapper bodies
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
#   - The single-pass interactive destroy gate: enumerate the real
#     resources, run the read-only pre-destroy guards, write the durable
#     guard-evidence record via scripts/lib/destroy-evidence.py (standard-
#     library-only Python, invoked only through its small CLI -- never
#     imported as a package), then drain the terminal input buffer and
#     require the operator to type `yes` on /dev/tty. It replaced the
#     former two-pass copy-paste confirmation-artifact protocol.
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
  scope-registry.sh \
  terraform-destroy-scope.sh
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
# dev's PROMOTION_MODE is always exactly "modeled", uat's is always exactly
# "uat-build", and prod's is also "uat-build" -- prod deliberately reuses
# uat's gate value rather than getting its own distinct literal; see #130),
# so this single rule produces the exact required dev message with no
# environment-name special-casing:
#   "ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled"

require_environment_mutation_authorized() {
  local environment_name="${1:-}"

  case "$environment_name" in
    dev|uat|prod) ;;
    *)
      _orchestrator_error "require_environment_mutation_authorized accepts only dev, uat, or prod"
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

  # Package fragments are loaded before graph pre-resolution: they define
  # the real handler functions that the checks below (and dispatch later)
  # must be able to name and call. Mirrors the identical call in the
  # provision/destroy dispatch paths (see _orchestrator_load_package_fragments
  # usage above) -- without it, every component-scope verifier symbol
  # resolves to scope-registry.sh's raw placeholder, even for scopes whose
  # real verifier a package fragment has already overridden.
  _orchestrator_load_package_fragments verify "${slots[@]}" || return 1

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
        printf 'PASS: foundation-contract — environment config loaded and validated (AWS account, region, state prefix)\n'
        ;;
      aws-identity-region)
        if verify_aws_identity_and_region; then
          printf 'PASS: aws-identity-region — AWS credentials match expected account and region\n'
        else
          printf 'FAIL: aws-identity-region — AWS credentials do not match expected account/region (check: aws sso login)\n' >&2
          failures=$((failures + 1))
        fi
        ;;
      kubernetes-context)
        if verify_kubernetes_context; then
          printf 'PASS: kubernetes-context — kubectl is configured for the correct EKS cluster\n'
        else
          printf 'FAIL: kubernetes-context — kubectl context does not match expected cluster (check: kubectl config current-context)\n' >&2
          failures=$((failures + 1))
        fi
        ;;
      eks-authentication-mode)
        if verify_eks_authentication_mode; then
          printf 'PASS: eks-authentication-mode — EKS cluster authentication method verified\n'
        else
          printf 'FAIL: eks-authentication-mode — EKS cluster authentication method incorrect or unreachable\n' >&2
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
# The immutable, foundation-owned closed map of the destructive acts a
# destroy of each persistent scope performs. Populates
# REQUIRED_CONFIRMATION_SCOPES and REQUIRED_CONFIRMATIONS (globals; Bash 3.2
# has no namerefs) in the exact given order.
#
# These are no longer values an operator has to retype: since the gate
# became a single interactive pass, they are the human-readable "this is
# what will actually happen" lines printed immediately above the typed-yes
# prompt (and, for PostgreSQL, they name the exact final-snapshot
# identifier the destroy will create). The identifier is still derived from
# the operation's own created_at rather than the wall clock, so what is
# displayed is what is recorded in the evidence record.

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
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:postgresql-core:db/oms-${environment_name}-coredb:final-snapshot=oms-${environment_name}-coredb-final-${snapshot_timestamp}")
        ;;
      postgresql-brand)
        REQUIRED_CONFIRMATION_SCOPES+=("$step")
        REQUIRED_CONFIRMATIONS+=("destroy:${environment_name}:${account_id}:postgresql-brand:db/oms-${environment_name}-branddb:final-snapshot=oms-${environment_name}-branddb-final-${snapshot_timestamp}")
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-approve)
        auto_approve="true"
        shift
        ;;
      # ----------------------------------------------------------------
      # Retired two-pass flags.
      #
      # These are rejected loudly rather than ignored: a stale runbook,
      # shell-history entry, or allow-list entry that still carries them
      # must fail visibly, never "succeed" with a silently different
      # meaning than the operator expects.
      # ----------------------------------------------------------------
      --confirmation-artifact|--confirmation-artifact=*|--confirm|--confirm=*)
        _orchestrator_error "${1%%=*} has been removed: destroy is now a single interactive pass that enumerates the real resources and asks you to type yes at the terminal. Re-run without it."
        return 1
        ;;
      --confirm-remove-protected|--confirm-remove-protected=*)
        _orchestrator_error "--confirm-remove-protected has been removed: Terraform lifecycle.prevent_destroy is now lifted automatically, and only for resources that are actually present and actually protected, after you type yes. Re-run without it."
        return 1
        ;;
      --confirm-disable-deletion-protection|--confirm-disable-deletion-protection=*)
        _orchestrator_error "--confirm-disable-deletion-protection has been removed: live EKS deletion protection is now disabled automatically, and only when the cluster still exists and still has it enabled, after you type yes. Re-run without it."
        return 1
        ;;
      *)
        _orchestrator_error "unknown unified destroy argument: $1"
        return 1
        ;;
    esac
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
  # exactly that case there is nothing for the gate to gate -- the handler
  # always refuses -- and the evidence schema requires a non-empty
  # guard_results array, so this narrow case dispatches its (always-
  # failing) handler directly.
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

  _orchestrator_destroy_single_pass \
    "$environment_name" "$scope" "$expected_account_id" "$auto_approve" "${order[@]}"
}

# ---------------------------------------------------------------------------
# Interactive typed-yes gate
# ---------------------------------------------------------------------------
#
# Reads the operator's answer from the controlling terminal (/dev/tty on a
# dedicated file descriptor), never from stdin.
#
# Two properties this exists for, both learned the hard way:
#
#   1. DRAIN BEFORE READ. Operators paste multi-line blocks. Pasting
#
#          scripts/destroy.sh --env prod eks-platform
#          yes
#
#      leaves "yes" sitting in the terminal's input buffer while line 1
#      runs. A naive `read` consumes it the instant it is reached -- the
#      prompt is answered before the resource list has even finished
#      drawing, and the human never sees what they just agreed to. So
#      everything already buffered is discarded first, and only then does
#      the read begin. The drain uses a short-timeout `read` loop; the
#      timeout is chosen per Bash version because Bash 3.2 (macOS
#      /bin/bash) REJECTS a fractional `-t` outright ("invalid timeout
#      specification") and its integer minimum is 1 second. Verified on
#      3.2.57 -- swallowing that error instead would silently turn the
#      drain into a no-op, which is the exact bug this gate exists to
#      prevent, so the loop below must never hide read's stderr.
#
#   2. READ FROM /dev/tty, NOT STDIN. Piping or redirecting into the
#      script must not be able to answer the prompt either.
#
# Fails closed with an explicit message when there is no controlling
# terminal (CI, nohup, cron, a pipeline). It never hangs on a read and
# never proceeds unconfirmed.
_orchestrator_prompt_typed_yes() {
  local prompt="$1"
  local answer=""

  # Probe in a subshell first: a failed `exec 3</dev/tty` in a script
  # running under `set -e`-less semantics would print a raw redirection
  # error and leave fd 3 unopened, and under some shells abort outright.
  if [[ ! -r /dev/tty ]] || ! ( exec 3</dev/tty ) 2>/dev/null; then
    _orchestrator_error "no controlling terminal is available, so the typed-yes destroy gate cannot be shown"
    _orchestrator_error "destroy refuses to run unattended (CI, nohup, cron, or a redirected/piped invocation); run it from an interactive terminal"
    return 1
  fi

  exec 3</dev/tty || {
    _orchestrator_error "unable to open the controlling terminal for the typed-yes destroy gate"
    return 1
  }

  # Discard anything already buffered (a pasted answer, a stray newline,
  # an impatient keypress) so the read below genuinely waits for an answer
  # given after the resource list was displayed.
  #
  # This MUST flush the terminal driver's input queue, not merely read
  # whole lines off it. `read` consumes COMPLETED LINES ONLY: a trailing
  # partial line with no newline sits in the kernel line discipline,
  # is invisible to `read -t` (which times out and returns 1 without
  # discarding it), and is then prepended to the next read. Verified on
  # bash 3.2.57 against a real pty:
  #
  #   paste "scripts/destroy.sh --env prod eks-platform\nyes"   (no \n)
  #   operator presses Enter
  #   -> a line-based drain yields answer="yes"  == ACCEPTED, list unseen
  #   -> tcflush + read      yields answer=""    == correctly rejected
  #
  # That is the exact multi-line-paste bite this gate exists to prevent,
  # so the flush and the read happen in the SAME process, immediately
  # adjacent, with nothing in between: flushing earlier (or from a
  # separate process) leaves the window open for the paste's tail to
  # arrive after the flush but before the read.
  #
  # Note `read -t 0` is NOT usable here: on bash 3.2.57 it returns 1
  # unconditionally, and fractional timeouts are rejected outright
  # ("read: 0.2: invalid timeout specification"), so a timeout-based
  # drain silently becomes a no-op on macOS.
  printf '%s' "$prompt" >&2
  answer="$("${_ORCHESTRATOR_PYTHON}" -c '
import os, sys, termios

fd = 3
try:
    termios.tcflush(fd, termios.TCIFLUSH)
except Exception as exc:            # noqa: BLE001 - must fail closed
    sys.stderr.write("unable to flush the terminal input queue: %s\n" % exc)
    raise SystemExit(2)

data = os.read(fd, 256)
sys.stdout.write(data.decode("utf-8", "replace").strip())
' 3<&3)" || {
    exec 3<&-
    _orchestrator_error "unable to read a confirmation from the controlling terminal; destroy aborted"
    return 1
  }
  exec 3<&-

  printf '\n' >&2
  [[ "$answer" == "yes" ]]
}

# ---------------------------------------------------------------------------
# Single-pass destroy
# ---------------------------------------------------------------------------
#
# Replaces the former two-pass copy-paste confirmation-artifact protocol
# (see docs/guides/operator-runbook.md). The sequence is:
#
#   1. Enumerate the real resources from real Terraform/cluster state and
#      print them. Enumeration failure aborts -- it never degrades to a
#      plausible-looking static list, which is what #163 removed.
#   2. Run every mapped read-only pre-destroy guard and write the durable
#      all-pass (or guard-failure) evidence record under
#      .local/<env>/evidence/, exactly as before.
#   3. Drain the terminal input buffer, then require the operator to type
#      the exact word `yes`.
#   4. Only then dispatch the destroy handlers, recording the consumed and
#      terminal evidence statuses.
#
# --auto-approve does NOT skip step 3, in ANY environment. It retains its
# other meaning only (UNIFIED_AUTO_APPROVE: don't prompt again inside the
# handlers/Terraform). The typed-yes gate exists so a human sees the real
# resource list before it disappears; that reason is identical in dev, uat
# and prod, and dev/uat teardowns have produced the same "I didn't know
# that was still there" incidents as prod. A per-environment exemption
# would also mean the one code path behaves differently per environment,
# which is exactly what this repository's environment-awareness rule
# forbids.
_orchestrator_destroy_single_pass() {
  local environment_name="$1"
  local scope="$2"
  local expected_account_id="$3"
  local auto_approve="$4"
  shift 4
  local -a order=("$@")

  local created_epoch created_at expires_at snapshot_timestamp
  created_epoch="$(_orchestrator_now_epoch)"
  created_at="$(_orchestrator_format_timestamp "$created_epoch")"
  expires_at="$(_orchestrator_format_timestamp "$((created_epoch + 900))")"
  snapshot_timestamp="$(printf '%s' "$created_at" | tr -d ':-')"

  _orchestrator_compute_required_confirmations \
    "$environment_name" "$expected_account_id" "$snapshot_timestamp" "${order[@]}"

  local operation_id
  operation_id="$(_orchestrator_generate_operation_id)"

  initialize_orchestration_paths "$environment_name" || return 1
  acquire_orchestration_lock || return 1

  # A Ctrl-C at the prompt (or any SIGTERM while the gate is open) must
  # release the orchestration lock rather than leave a stale lock behind.
  # Source-patching of Terraform's lifecycle.prevent_destroy happens later,
  # inside the destroy handlers, and each patching site installs its own
  # EXIT/INT/TERM restore trap (see
  # scripts/lib/packages/10-foundation-access/internal/access-scopes.sh) --
  # so an interrupt at any point restores the patched source and then
  # unwinds through this trap.
  trap '_orchestrator_error "interrupted; releasing the orchestration lock"; cleanup_orchestration_artifacts 1; exit 130' INT TERM

  # ------------------------------------------------------------------
  # Step 1: enumerate the real resources and show them.
  # ------------------------------------------------------------------

  local enumeration_text=""
  if ! enumeration_text="$(_orchestrator_render_destroy_enumeration "$environment_name" "${order[@]}")"; then
    _orchestrator_error "unable to enumerate the resources this destroy would remove; destroy aborted before any prompt or dispatch"
    _orchestrator_error "a destroy is never offered against an unverified resource list"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  fi
  printf '%s\n' "$enumeration_text"

  # ------------------------------------------------------------------
  # Gate digest: binds the durable evidence record to the exact bytes
  # that were shown to the operator. It occupies the evidence schema's
  # `confirmation_artifact_sha256` slot, which previously bound evidence
  # to the (now removed) confirmation artifact file.
  # ------------------------------------------------------------------

  local gate_digest
  gate_digest="$(printf 'gate\nenvironment=%s\naccount=%s\nrequested_scope=%s\noperation_id=%s\ncreated_at=%s\nresolved_scopes=%s\n%s' \
    "$environment_name" "$expected_account_id" "$scope" "$operation_id" "$created_at" \
    "$(printf '%s,' "${order[@]}")" "$enumeration_text" | _orchestrator_sha256_hex)" || {
    _orchestrator_error "unable to compute the destroy gate digest"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  }

  # ------------------------------------------------------------------
  # Step 2: dispatch every mapped read-only pre-destroy guard in exact
  # reverse destroy order, then write the durable evidence record.
  # ------------------------------------------------------------------

  _orchestrator_reset_guard_state

  local step
  local guard_index=0
  for step in "${order[@]}"; do
    if _scope_registry_scope_requires_pre_destroy_guard "$step"; then
      _orchestrator_dispatch_guard "$step" "$guard_index" || break
      guard_index=$((guard_index + 1))
    fi
  done

  if [[ "$_ORCHESTRATOR_GUARD_ABORTED" == "true" ]]; then
    local received_results_json failure_json
    received_results_json="$(_orchestrator_build_guard_results_json)"
    failure_json="$(_orchestrator_build_failure_json \
      "$_ORCHESTRATOR_GUARD_FAILURE_CODE" \
      "$_ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE" \
      "$_ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX" \
      "$_ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX" \
      "$_ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS")"

    local -a failure_args=(
      write-guard-failure
      --path "${EVIDENCE_DIR}/destroy-guard-failure.${operation_id}.json"
      --operation-id "$operation_id"
      --environment "$environment_name"
      --account-id "$expected_account_id"
      --requested-scope "$scope"
      --received-results-json "$received_results_json"
      --failure-json "$failure_json"
      --created-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")"
      --confirmation-artifact-sha256 "$gate_digest"
    )
    for step in "${order[@]}"; do
      failure_args+=(--resolved-scope "$step")
    done

    "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${failure_args[@]}" \
      || _orchestrator_error "unable to write guard-failure record (additional foundation failure)"

    _orchestrator_error "pre-destroy guard failure (${_ORCHESTRATOR_GUARD_FAILURE_CODE}); destroy aborted before approval or dispatch"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local guard_results_json
  guard_results_json="$(_orchestrator_build_guard_results_json)"

  local evidence_path="${EVIDENCE_DIR}/pre-destroy-guards.${operation_id}.json"
  local -a evidence_args=(
    write-evidence
    --path "$evidence_path"
    --operation-id "$operation_id"
    --environment "$environment_name"
    --account-id "$expected_account_id"
    --requested-scope "$scope"
    --guard-results-json "$guard_results_json"
    --created-at "$created_at"
    --expires-at "$expires_at"
    --confirmation-artifact-sha256 "$gate_digest"
  )
  for step in "${order[@]}"; do
    evidence_args+=(--resolved-scope "$step")
  done

  if ! "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${evidence_args[@]}"; then
    _orchestrator_error "unable to write all-pass guard evidence; destroy aborted before approval or dispatch"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  fi

  local evidence_sha256
  evidence_sha256="$("$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" digest --path "$evidence_path")" || {
    _orchestrator_error "unable to compute all-pass guard evidence digest"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  }
  evidence_sha256="${evidence_sha256#sha256:}"

  # ------------------------------------------------------------------
  # Step 3: the typed-yes gate.
  # ------------------------------------------------------------------

  printf '\n'
  printf 'Destroy request : %s (resolved order: %s)\n' "$scope" "$(printf '%s ' "${order[@]}")"
  printf 'Environment     : %s (account %s)\n' "$environment_name" "$expected_account_id"
  printf 'Evidence record : %s\n' "$evidence_path"
  local requirement_index
  for ((requirement_index = 0; requirement_index < ${#REQUIRED_CONFIRMATIONS[@]}; requirement_index++)); do
    printf 'Destructive act : %s\n' "${REQUIRED_CONFIRMATIONS[$requirement_index]}"
  done
  printf '\n'
  printf 'Terraform lifecycle.prevent_destroy and live EKS deletion protection will be\n'
  printf 'lifted automatically for the resources above that still have them, and only\n'
  printf 'for those. This is irreversible.\n'
  printf '\n'

  if ! _orchestrator_prompt_typed_yes \
    "Type the exact word yes to destroy ${scope} in ${environment_name}: "; then
    _orchestrator_error "destroy approval was not given; destroy aborted before dispatch"
    trap - INT TERM
    cleanup_orchestration_artifacts 1
    return 1
  fi

  "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" write-status \
    --evidence-dir "$EVIDENCE_DIR" \
    --operation-id "$operation_id" \
    --status consumed \
    --evidence-sha256 "$evidence_sha256" \
    --recorded-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")" \
    || _orchestrator_error "unable to record consumed evidence status (continuing to dispatch; this is itself a foundation concern)"

  # ------------------------------------------------------------------
  # Step 4: dispatch destroy handlers in the same reverse destroy order.
  # ------------------------------------------------------------------

  export UNIFIED_AUTO_APPROVE="$auto_approve"

  # UNIFIED_DESTROY_CONFIRMED is the single signal a destroy handler may
  # use to decide that lifting a protection (Terraform prevent_destroy
  # source patching, live EKS deletionProtection) is authorized. It is set
  # only here, only after a human typed yes against a real enumerated
  # resource list. Handlers must still apply each lift conditionally, on
  # the resource actually being present and actually protected -- an
  # unconditional lift reintroduces the #159 deadlock the moment a
  # resource is already gone.
  export UNIFIED_DESTROY_CONFIRMED="yes"

  local dispatch_status=0
  for step in "${order[@]}"; do
    local handler_symbol
    handler_symbol="$(destroy_handler_for_scope "$step")"
    if ! "$handler_symbol"; then
      dispatch_status=1
      break
    fi
  done

  local terminal_status="success"
  [[ "$dispatch_status" -ne 0 ]] && terminal_status="failure"

  local -a status_args=(
    write-status
    --evidence-dir "$EVIDENCE_DIR"
    --operation-id "$operation_id"
    --status "$terminal_status"
    --evidence-sha256 "$evidence_sha256"
    --recorded-at "$(_orchestrator_format_timestamp "$(_orchestrator_now_epoch)")"
  )
  if [[ "$terminal_status" == "failure" ]]; then
    status_args+=(--failure-code DESTROY_HANDLER_FAILED)
  fi
  "$_ORCHESTRATOR_PYTHON" "${_ORCHESTRATOR_LIB_DIR}/destroy-evidence.py" "${status_args[@]}" \
    || _orchestrator_error "unable to record terminal evidence status ${terminal_status} (original destroy status is preserved)"

  trap - INT TERM
  cleanup_orchestration_artifacts "$dispatch_status"
}

# ---------------------------------------------------------------------------
# _orchestrator_render_destroy_enumeration <environment> <step>...
# ---------------------------------------------------------------------------
#
# Renders the real per-scope resource list to stdout, or fails.
#
# Fail-closed contract, distinguishing three cases that must not be
# conflated:
#
#   * enumeration FAILED unexpectedly for a scope that has an enumerator
#     (state unreadable for a reason we cannot explain) -> return 1.
#     The destroy is abandoned. Never a static or "plausible" fallback
#     list: showing a confident fiction at the exact moment a human is
#     deciding whether to destroy production is the failure #163 removed.
#
#   * the backing state is legitimately UNAVAILABLE (status 3): the
#     Terraform backend is not initialized in this working copy, or the
#     cluster kubectl would query is already gone. Report it plainly and
#     CONTINUE. These are normal conditions, not defects:
#       - `.terraform/` is gitignored, so a fresh clone has never inited;
#       - a half-finished teardown deletes the cluster before its
#         Terraform scope, so kubectl necessarily fails afterwards.
#     Treating either as fatal strands the teardown with no supported
#     recovery -- which is the #159 deadlock rebuilt on a different
#     observation, and is explicitly forbidden here.
#
#   * NO enumerator is mapped for a scope (status 2) -> say so
#     explicitly, in those words, and continue. That is an honest absence
#     rather than an invented list, and the typed-yes gate still stands
#     between the operator and the destroy.
#
# In every non-fatal case the operator still sees exactly what is and is
# not known before typing `yes`.
_orchestrator_render_destroy_enumeration() {
  local environment_name="$1"
  shift
  local -a steps=("$@")

  local enumerator="${_ORCHESTRATOR_LIB_DIR}/enumerate-destroy-resources.sh"
  if [[ ! -f "$enumerator" ]]; then
    _orchestrator_error "resource enumeration library is missing: ${enumerator}"
    return 1
  fi
  # shellcheck disable=SC1091
  source "$enumerator" || return 1
  if ! type -t enumerate_destroy_resources_for_scope >/dev/null 2>&1; then
    _orchestrator_error "enumerate_destroy_resources_for_scope is not defined by ${enumerator}"
    return 1
  fi

  local step scope_output enumerate_status
  for step in "${steps[@]}"; do
    format_destroy_preview_header "$step" "$environment_name"
    scope_output="$(enumerate_destroy_resources_for_scope "$step" "$environment_name")"
    enumerate_status=$?
    case "$enumerate_status" in
      0)
        printf '%s\n' "$scope_output"
        ;;
      2)
        printf '  No resource enumerator is mapped for scope %s.\n' "$step"
        printf '  Nothing is being guessed or substituted here; this scope simply has no\n'
        printf '  enumerator yet. Review the scope by hand before answering the prompt.\n'
        ;;
      3)
        # Backing state legitimately unavailable (backend not initialized
        # here, or the cluster is already gone). Report and continue --
        # see the contract note above on why this must not be fatal.
        printf '%s\n' "$scope_output"
        printf '  The resource list for %s could not be read (see the reason above).\n' "$step"
        printf '  Nothing is being guessed or substituted. This is expected on a fresh\n'
        printf '  clone that has never initialized this backend, or after a partial\n'
        printf '  teardown that already removed the cluster. Terraform still re-checks\n'
        printf '  every resource against AWS in the plan shown before it applies.\n'
        printf '  Review this scope by hand before answering the prompt.\n'
        ;;
      *)
        _orchestrator_error "resource enumeration failed for scope: ${step}"
        return 1
        ;;
    esac
    format_destroy_preview_footer
  done
}

_orchestrator_sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-64
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-64
  else
    openssl dgst -sha256 -r | cut -d' ' -f1
  fi
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
    _orchestrator_error "unified commands require a leading --env <dev|uat|prod> argument"
    return 1
  fi
  shift || true

  local environment_name="${1:-}"
  case "$environment_name" in
    dev|uat|prod) ;;
    *)
      _orchestrator_error "unified commands require --env dev, --env uat, or --env prod, got: ${environment_name:-<empty>}"
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
