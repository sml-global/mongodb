#!/usr/bin/env bash
set -euo pipefail

# Automates the one-time SigNoz Service Account + API key bootstrap that
# `scripts/provision-signoz-observability.sh` requires. This used to be a
# manual "click through the SigNoz UI" step -- it is now driven end-to-end by
# scripts/bootstrap_signoz_service_account.py (Playwright, headless Chromium),
# so no human (or AI agent) needs to open a browser by hand.
#
# Idempotent: if the 'signoz-api-key' Secret already exists, this script does
# nothing and exits 0 -- re-run it freely, including from provision.sh.
#
# Usage:
#   scripts/bootstrap-signoz-service-account.sh [--account-name NAME] [--role ROLE]

NAMESPACE="signoz"
ACCOUNT_NAME="terraform-automation"
ROLE="signoz-admin"
KEY_NAME="terraform-automation-key-$(date +%s)"
PORT="${SIGNOZ_BOOTSTRAP_PORT:-13301}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY_SCRIPT="$ROOT_DIR/scripts/bootstrap_signoz_service_account.py"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-signoz-service-account.sh [--account-name NAME] [--role ROLE] [--key-name NAME]

Creates (or reuses) a SigNoz Service Account, assigns it a role, generates an
API key via a headless-browser (Playwright) flow, and stores it as the
'signoz-api-key' Secret in the 'signoz' namespace -- fully unattended.

No-op (exit 0) if the 'signoz-api-key' Secret already exists.

Options:
  --account-name   Service Account name (default: terraform-automation)
  --role           Role to assign (default: signoz-admin)
  --key-name       API key name (default: terraform-automation-key-<unix-timestamp>,
                    unique per run since SigNoz rejects duplicate key names
                    on the same service account)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-name) ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --key-name) KEY_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if kubectl -n "$NAMESPACE" get secret signoz-api-key >/dev/null 2>&1; then
  echo "Secret 'signoz-api-key' already exists in namespace '$NAMESPACE'; nothing to do."
  exit 0
fi

if ! kubectl -n "$NAMESPACE" get secret signoz-root-user >/dev/null 2>&1; then
  echo "Error: Secret 'signoz-root-user' not found in namespace '$NAMESPACE'." >&2
  echo "Run scripts/create-signoz-root-user-secret.sh (and scripts/provision.sh signoz) first." >&2
  exit 1
fi

if ! python3 -c "import playwright" >/dev/null 2>&1; then
  echo "Error: the 'playwright' Python package is not installed." >&2
  echo "Install it once with:" >&2
  echo "  python3 -m pip install playwright && python3 -m playwright install chromium" >&2
  exit 1
fi

ROOT_EMAIL="$(kubectl -n "$NAMESPACE" get secret signoz-root-user -o jsonpath='{.data.email}' | base64 -d)"
ROOT_PASSWORD="$(kubectl -n "$NAMESPACE" get secret signoz-root-user -o jsonpath='{.data.password}' | base64 -d)"

# Start a port-forward only if nothing is already listening on $PORT (lets
# this script compose cleanly with an operator's own long-lived
# open-signoz-ui.sh session on the default 3301 port).
STARTED_PORT_FORWARD="false"
if ! curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/api/v1/health"; then
  echo "Starting temporary port-forward to signoz:8080 on 127.0.0.1:${PORT} ..."
  kubectl -n "$NAMESPACE" port-forward svc/signoz "${PORT}:8080" >/tmp/signoz-bootstrap-pf.log 2>&1 &
  PF_PID=$!
  STARTED_PORT_FORWARD="true"

  for _ in $(seq 1 30); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/api/v1/health"; then
      break
    fi
    sleep 1
  done
fi

cleanup() {
  if [[ "$STARTED_PORT_FORWARD" == "true" && -n "${PF_PID:-}" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/api/v1/health"; then
  echo "Error: SigNoz is not reachable at http://127.0.0.1:${PORT} after waiting 30s." >&2
  exit 1
fi

echo "Bootstrapping Service Account '$ACCOUNT_NAME' (role: $ROLE) via headless browser ..."
API_KEY="$(python3 "$PY_SCRIPT" \
  --url "http://127.0.0.1:${PORT}" \
  --email "$ROOT_EMAIL" \
  --password "$ROOT_PASSWORD" \
  --account-name "$ACCOUNT_NAME" \
  --role "$ROLE" \
  --key-name "$KEY_NAME")"

if [[ -z "$API_KEY" ]]; then
  echo "Error: bootstrap script did not return an API key." >&2
  exit 1
fi

kubectl -n "$NAMESPACE" create secret generic signoz-api-key --from-literal=token="$API_KEY"

PASSWORDS_FILE="$ROOT_DIR/.local-dev-user-passwords.txt"
{
  echo ""
  echo "# SigNoz Terraform automation service-account API key (generated $(date -u +%Y-%m-%d), scripted bootstrap)"
  echo "SIGNOZ_ACCESS_TOKEN=$API_KEY"
} >> "$PASSWORDS_FILE"

echo "Created secret: $NAMESPACE/signoz-api-key"
echo "Next: bash scripts/provision.sh signoz-observability --auto-approve"
