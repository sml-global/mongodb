#!/usr/bin/env bash
set -euo pipefail

# Public compatibility entrypoint. This wrapper makes exactly one routing
# decision: a leading `--env` routes to unified orchestration; anything else
# (including no arguments, `-h`/`--help`, or any legacy scope) execs the
# frozen legacy dev implementation unchanged. See "Task 4: Add Explicit
# Unified Entrypoints Without Changing Legacy Dev Behavior" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md.
# Later arguments are never inspected for `--env`; a non-leading flag
# belongs to the unchanged legacy grammar and is rejected there as it is
# today.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" != "--env" ]]; then
  exec bash "$ROOT_DIR/scripts/legacy/dev/provision.sh" "$@"
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/orchestrator.sh"
run_unified_command provision "$@"
