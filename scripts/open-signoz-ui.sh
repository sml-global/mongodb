#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-signoz}"
SERVICE="${2:-signoz-frontend}"
LOCAL_PORT="${3:-3301}"
REMOTE_PORT="${4:-3301}"

echo "Opening SigNoz UI tunnel from ${NAMESPACE}/${SERVICE} ${LOCAL_PORT}->${REMOTE_PORT}"
kubectl -n "$NAMESPACE" port-forward "svc/$SERVICE" "$LOCAL_PORT:$REMOTE_PORT"
