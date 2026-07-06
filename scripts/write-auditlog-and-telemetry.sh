#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROOVY_SCRIPT="$SCRIPT_DIR/write-auditlog-and-telemetry.groovy"
GROOVY_LIB_DIR="$SCRIPT_DIR/groovy"

if ! command -v groovy >/dev/null 2>&1; then
  echo "Error: required command not found: groovy" >&2
  echo "Install Groovy (for example: brew install groovy) and rerun." >&2
  exit 1
fi

exec groovy -cp "$GROOVY_LIB_DIR" "$GROOVY_SCRIPT" "$@"
