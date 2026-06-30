#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision.sh <scope> [--auto-approve]

Scopes:
  all       Provision MongoDB + PostgreSQL prerequisites (separate states), then MongoDB k8s stack.
  mongodb   Provision MongoDB prerequisites only, then MongoDB k8s stack.
  mongo     Alias of mongodb.
  pg        Provision PostgreSQL prerequisites only.
  signoz    Provision SigNoz application telemetry stack.

Examples:
  bash scripts/provision.sh all
  bash scripts/provision.sh mongodb
  bash scripts/provision.sh mongo
  bash scripts/provision.sh pg --auto-approve
  bash scripts/provision.sh signoz
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCOPE="${1:-}"
AUTO_APPROVE="false"

if [[ "$SCOPE" == "-h" || "$SCOPE" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$SCOPE" ]]; then
  usage
  exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve)
      AUTO_APPROVE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

run_platform() {
  local scope="$1"
  local -a args=("$scope")
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    args+=("--auto-approve")
  fi
  bash "$ROOT_DIR/scripts/provision-platform-prereq.sh" "${args[@]}"
}

case "$SCOPE" in
  all)
    run_platform mongodb
    run_platform pg
    bash "$ROOT_DIR/scripts/provision-k8s-components.sh" mongodb
    ;;
  mongodb|mongo)
    run_platform mongodb
    bash "$ROOT_DIR/scripts/provision-k8s-components.sh" mongodb
    ;;
  pg)
    run_platform pg
    ;;
  signoz)
    bash "$ROOT_DIR/scripts/provision-k8s-components.sh" signoz
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: all, mongodb, mongo, pg, signoz" >&2
    usage
    exit 1
    ;;
esac

echo "Completed provisioning scope: $SCOPE"
