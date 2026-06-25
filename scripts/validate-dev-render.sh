#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="/tmp/mongodb-dev.yaml"

cd "$ROOT_DIR"
./scripts/inject-dev-db-values.sh
kustomize build k8s/overlays/dev > "$OUT_FILE"
echo "Rendered dev overlay to $OUT_FILE"

rg -n "kind: PerconaServerMongoDB|size: 3|backup:" "$OUT_FILE" | head -n 20