#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACK_DIR="$ROOT_DIR/dashboards/signoz-import-pack"

if [[ ! -d "$PACK_DIR" ]]; then
  echo "ERROR: Dashboard pack folder not found: $PACK_DIR" >&2
  exit 1
fi

echo "SigNoz dashboard import pack is ready."
echo
echo "Folder: $PACK_DIR"
echo
echo "Dashboards to import (recommended order):"
echo "1) k8s-hostmetrics-overview.json"
echo "2) mongodb-overview.json"
echo "3) aws-rds-postgresql-overview.json"
echo "4) aws-rds-postgresql-db-metrics-overview.json"
echo "5) opentelemetry-collector-pipeline-health.json"
echo
echo "Open SigNoz UI with:"
echo "  scripts/open-signoz-ui.sh"
echo
echo "Then in UI: Dashboards -> + New dashboard -> Import JSON (upload each file)."
echo
echo "Quick check (files present):"
ls -1 "$PACK_DIR"/*.json
