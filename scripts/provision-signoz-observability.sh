#!/usr/bin/env bash
set -euo pipefail

# Applies the signoz-observability Terraform root: dashboards + alert rules
# for MongoDB, PostgreSQL/Aurora, K8s nodes, the OTel Collector pipelines, and
# Boomi app telemetry, all managed as code via the official SigNoz Terraform
# provider (SigNoz/signoz).
#
# Prerequisites (one-time, fully automated -- see
# docs/references/signoz-dashboard-import-pack.md):
#   1. SigNoz root user bootstrapped (scripts/create-signoz-root-user-secret.sh
#      + scripts/provision.sh signoz) -- removes the manual UI signup step.
#   2. A Service Account + API key, auto-created via
#      scripts/bootstrap-signoz-service-account.sh (headless Playwright flow)
#      the first time this script runs and the 'signoz-api-key' Secret is
#      missing -- no manual UI interaction required.
#
# Usage:
#   scripts/provision-signoz-observability.sh [--auto-approve] [--endpoint <url>]

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/signoz-observability"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-sml-oms-dev-tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-ap-east-1}"
TF_STATE_KEY="${TF_STATE_KEY:-oms/dev/signoz-observability.tfstate}"

AUTO_APPROVE="false"
ENDPOINT="${SIGNOZ_ENDPOINT:-http://127.0.0.1:3301}"

usage() {
  cat <<'EOF'
Usage:
  provision-signoz-observability.sh [--auto-approve] [--endpoint <url>]

Options:
  --auto-approve   Skip the interactive terraform apply confirmation.
  --endpoint       SigNoz endpoint URL (default: http://127.0.0.1:3301, i.e. a
                    local port-forward -- see scripts/open-signoz-ui.sh).
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve) AUTO_APPROVE="true"; shift ;;
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if ! kubectl -n signoz get secret signoz-api-key >/dev/null 2>&1; then
  echo "Secret 'signoz-api-key' not found in namespace 'signoz'; bootstrapping it now (headless browser, one time only) ..."
  bash "$ROOT_DIR/scripts/bootstrap-signoz-service-account.sh"
fi

export SIGNOZ_ACCESS_TOKEN
SIGNOZ_ACCESS_TOKEN="$(kubectl -n signoz get secret signoz-api-key -o jsonpath='{.data.token}' | base64 -d)"
export SIGNOZ_ENDPOINT="$ENDPOINT"

echo "Using SigNoz endpoint: $SIGNOZ_ENDPOINT"

# If the endpoint is a local address and nothing is listening there yet,
# start a temporary port-forward automatically so this script is fully
# self-sufficient (no separately-running `open-signoz-ui.sh` session
# required). Only ever done for 127.0.0.1/localhost endpoints -- a custom
# --endpoint (e.g. a real ingress URL) is assumed to already be reachable.
PF_PID=""
cleanup_port_forward() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_port_forward EXIT

if [[ "$ENDPOINT" =~ ^https?://(127\.0\.0\.1|localhost):([0-9]+)$ ]]; then
  endpoint_local_port="${BASH_REMATCH[2]}"
  if ! curl -s -o /dev/null --max-time 2 "$ENDPOINT/api/v1/health"; then
    echo "Starting temporary port-forward to signoz:8080 on 127.0.0.1:${endpoint_local_port} ..."
    kubectl -n signoz port-forward svc/signoz "${endpoint_local_port}:8080" >/tmp/signoz-observability-pf.log 2>&1 &
    PF_PID=$!
    for _ in $(seq 1 30); do
      curl -s -o /dev/null --max-time 2 "$ENDPOINT/api/v1/health" && break
      sleep 1
    done
  fi
fi

if ! curl -s -o /dev/null --max-time 2 "$ENDPOINT/api/v1/health"; then
  echo "Error: SigNoz is not reachable at $ENDPOINT." >&2
  exit 1
fi

init_backend() {
  if [[ ! -x "$BOOTSTRAP_BACKEND_SCRIPT" ]]; then
    echo "Error: backend bootstrap script is not executable: $BOOTSTRAP_BACKEND_SCRIPT" >&2
    exit 1
  fi

  "$BOOTSTRAP_BACKEND_SCRIPT" \
    --tf-dir "$TF_DIR" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$TF_STATE_KEY"
}

run_apply() {
  local -a args=("$@")
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform -chdir="$TF_DIR" apply -input=false -auto-approve "${args[@]}"
  else
    terraform -chdir="$TF_DIR" apply -input=false "${args[@]}"
  fi
}

# Known SigNoz Terraform provider bug (v0.0.14): on apply, the provider can
# return an unknown value for the computed `preferred_channels` field on
# signoz_alert resources, causing Terraform to report "Provider returned
# invalid result object after apply" and mark the resource tainted -- even
# though the alert was actually created/updated successfully in SigNoz.
# `terraform untaint` does NOT reliably fix this: an untainted resource is
# replaced (destroy + recreate) on the next apply, and that fresh creation
# hits the exact same bug again -- observed to loop indefinitely rather than
# eventually settling, even with backoff between retries. The only
# deterministic fix is to directly patch the state: clear the tainted
# status and set `preferred_channels` to `[]` (the correct value, since
# this repo never sets a non-empty value for it -- see alerts.tf) without
# going through the provider again at all. This function detects the known
# error signature and performs that state surgery automatically.
# See platform-prerequisites/terraform/signoz-observability/README.md
# "Known Provider Limitation" for full details.
retry_on_known_taint_bug() {
  local apply_output apply_status state_file

  set +e
  apply_output="$(run_apply tfplan 2>&1)"
  apply_status=$?
  set -e
  echo "$apply_output"

  if [[ "$apply_status" -eq 0 ]]; then
    return 0
  fi

  if ! echo "$apply_output" | grep -q "Provider returned invalid result object after apply"; then
    echo "Error: terraform apply failed for a reason other than the known provider taint bug." >&2
    return "$apply_status"
  fi

  echo ""
  echo "Detected the known SigNoz provider computed-field bug (preferred_channels)."
  echo "Patching Terraform state directly (clearing taint, setting preferred_channels=[]) instead of untaint+replace ..."

  state_file="$(mktemp)"
  terraform -chdir="$TF_DIR" state pull > "$state_file"

  python3 - "$state_file" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    state = json.load(f)

patched = 0
for resource in state.get("resources", []):
    if resource.get("type") != "signoz_alert":
        continue
    for instance in resource.get("instances", []):
        if instance.get("status") == "tainted":
            del instance["status"]
            patched += 1
        if instance.get("attributes", {}).get("preferred_channels") is None:
            instance["attributes"]["preferred_channels"] = []

if patched:
    state["serial"] = state.get("serial", 0) + 1

with open(path, "w") as f:
    json.dump(state, f)

print(f"Patched {patched} tainted signoz_alert instance(s).")
PYEOF

  terraform -chdir="$TF_DIR" state push "$state_file"
  rm -f "$state_file"

  terraform -chdir="$TF_DIR" plan -out=tfplan
  run_apply tfplan
}

init_backend
terraform -chdir="$TF_DIR" fmt -recursive
terraform -chdir="$TF_DIR" validate

terraform -chdir="$TF_DIR" plan -out=tfplan
retry_on_known_taint_bug

echo "Completed: signoz-observability (dashboards + alerts)"
echo "Terraform root: $TF_DIR"
echo "State key: $TF_STATE_KEY"

