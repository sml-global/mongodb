#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--" ]]; then
  echo "Usage: $0 -- <command ...>"
  exit 1
fi

shift

if [[ "$#" -eq 0 ]]; then
  echo "No command provided."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$ROOT_DIR/docs/operations/command-log.md"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CMD="$*"

mkdir -p "$(dirname "$LOG_FILE")"

if [[ -f "$LOG_FILE" ]]; then
  last_char="$(tail -c 1 "$LOG_FILE" || true)"
  if [[ "$last_char" != "" ]]; then
    printf "\n" >> "$LOG_FILE"
  fi
fi

printf -- "- %s | cwd=%s | cmd: %s\n" "$TS" "$PWD" "$CMD" >> "$LOG_FILE"

"$@"