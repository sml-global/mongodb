#!/usr/bin/env bash
#
# Environment-qualified local operator state: paths, locking, and artifact
# cleanup shared by every dev/uat environment orchestration entry point.
#
# `initialize_orchestration_paths <dev|uat>` computes every `.local/<env>/...`
# path from this file's own location (the repository root two directories
# up from scripts/lib/) and the requested environment name; it accepts no
# path override from the calling process environment. This file contains
# no top-level execution.
#
# Canonical layout:
#   .local/<env>/locks/orchestration.lock
#   .local/<env>/plans/<scope>.<pid>.tfplan
#   .local/<env>/generated/eks-access.<pid>.auto.tfvars.json
#   .local/<env>/logs/
#   .local/<env>/evidence/

_ORCHESTRATION_PATHS_LIBRARY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCAL_ROOT=""
LOCK_DIR=""
PLAN_DIR=""
GENERATED_DIR=""
LOG_DIR=""
EVIDENCE_DIR=""

_ORCHESTRATION_LOCK_HELD="false"
_ORCHESTRATION_ACTIVE_PATHS=()

_orchestration_paths_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_orchestration_paths_require_real_directory() {
  local candidate="$1"

  if [[ -L "$candidate" ]]; then
    _orchestration_paths_error "path must not be a symlink: ${candidate}"
    return 1
  fi

  if [[ -e "$candidate" && ! -d "$candidate" ]]; then
    _orchestration_paths_error "path exists and is not a directory: ${candidate}"
    return 1
  fi
}

_orchestration_paths_make_directory() {
  local candidate="$1"

  _orchestration_paths_require_real_directory "$candidate" || return 1
  if [[ ! -d "$candidate" ]]; then
    if ! mkdir "$candidate"; then
      _orchestration_paths_error "unable to create directory: ${candidate}"
      return 1
    fi
  fi
  _orchestration_paths_require_real_directory "$candidate" || return 1
}

# ---------------------------------------------------------------------------
# Path initialization
# ---------------------------------------------------------------------------

initialize_orchestration_paths() {
  local environment_name="$1"
  local repository_root
  local previous_umask
  local component

  case "$environment_name" in
    dev|uat) ;;
    *)
      _orchestration_paths_error "initialize_orchestration_paths accepts only dev or uat"
      return 1
      ;;
  esac

  repository_root="$(cd "${_ORCHESTRATION_PATHS_LIBRARY_DIR}/../.." && pwd)" || {
    _orchestration_paths_error "unable to resolve the repository root"
    return 1
  }
  _orchestration_paths_require_real_directory "$repository_root" || return 1

  LOCAL_ROOT="${repository_root}/.local/${environment_name}"
  LOCK_DIR="${LOCAL_ROOT}/locks/orchestration.lock"
  PLAN_DIR="${LOCAL_ROOT}/plans"
  GENERATED_DIR="${LOCAL_ROOT}/generated"
  LOG_DIR="${LOCAL_ROOT}/logs"
  EVIDENCE_DIR="${LOCAL_ROOT}/evidence"

  previous_umask="$(umask)"
  umask 077

  for component in \
    "${repository_root}/.local" \
    "$LOCAL_ROOT" \
    "${LOCAL_ROOT}/locks" \
    "$PLAN_DIR" \
    "$GENERATED_DIR" \
    "$LOG_DIR" \
    "$EVIDENCE_DIR"
  do
    if ! _orchestration_paths_make_directory "$component"; then
      umask "$previous_umask"
      return 1
    fi
  done

  umask "$previous_umask"
  _ORCHESTRATION_ACTIVE_PATHS=()
}

# ---------------------------------------------------------------------------
# Atomic lock
# ---------------------------------------------------------------------------

acquire_orchestration_lock() {
  if [[ -z "$LOCK_DIR" ]]; then
    _orchestration_paths_error "initialize_orchestration_paths must run before acquire_orchestration_lock"
    return 1
  fi

  if [[ -L "$LOCK_DIR" ]]; then
    _orchestration_paths_error "lock path must not be a symlink: ${LOCK_DIR}"
    return 1
  fi

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    _orchestration_paths_error "another orchestration run holds the lock: ${LOCK_DIR}"
    return 1
  fi

  _ORCHESTRATION_LOCK_HELD="true"
}

release_orchestration_lock() {
  if [[ "$_ORCHESTRATION_LOCK_HELD" != "true" ]]; then
    return 0
  fi

  if rmdir "$LOCK_DIR" 2>/dev/null; then
    _ORCHESTRATION_LOCK_HELD="false"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Artifact tracking and cleanup
# ---------------------------------------------------------------------------

register_orchestration_artifact() {
  local candidate="$1"

  if [[ -z "$LOCAL_ROOT" ]]; then
    _orchestration_paths_error "initialize_orchestration_paths must run before register_orchestration_artifact"
    return 1
  fi

  case "$candidate" in
    "${LOCAL_ROOT}/"*) ;;
    *)
      _orchestration_paths_error "artifact path is outside ${LOCAL_ROOT}/: ${candidate}"
      return 1
      ;;
  esac

  _ORCHESTRATION_ACTIVE_PATHS+=("$candidate")
}

# cleanup_orchestration_artifacts [original_status]
#
# Attempts every cleanup action regardless of earlier failures within this
# call, then returns the original non-zero command status in preference to
# any cleanup error. On an otherwise successful run (original_status is 0
# or omitted), a cleanup failure makes this call -- and therefore the
# caller's exit status -- fail.
cleanup_orchestration_artifacts() {
  local original_status="${1:-0}"
  local cleanup_status=0
  local artifact_path

  for artifact_path in "${_ORCHESTRATION_ACTIVE_PATHS[@]}"; do
    [[ -n "$artifact_path" ]] || continue
    if [[ -e "$artifact_path" || -L "$artifact_path" ]]; then
      if ! rm -f "$artifact_path"; then
        cleanup_status=1
      fi
    fi
  done
  _ORCHESTRATION_ACTIVE_PATHS=()

  if ! release_orchestration_lock; then
    cleanup_status=1
  fi

  if [[ "$original_status" -ne 0 ]]; then
    return "$original_status"
  fi
  return "$cleanup_status"
}
