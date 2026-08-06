#!/usr/bin/env bash
set -euo pipefail

# Create ClickHouse root user secret in SigNoz namespace
# This script is idempotent: safe to run multiple times
#
# Usage:
#   scripts/create-signoz-clickhouse-secret.sh [--namespace <ns>]
#
# Options:
#   --namespace <ns>   Kubernetes namespace (default: signoz)
#
# Environment variables:
#   CLICKHOUSE_ROOT_PASSWORD   Optional password (auto-generated if not set)

NAMESPACE="signoz"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--namespace <ns>]"
      exit 1
      ;;
  esac
done

# Ensure namespace exists (idempotent, no field-manager drift)
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# Check if secret already exists (idempotent)
if kubectl -n "$NAMESPACE" get secret signoz-clickhouse >/dev/null 2>&1; then
  echo "Secret signoz-clickhouse already exists in namespace $NAMESPACE; skipping creation"
  exit 0
fi

# Accept password from environment variable or generate secure password
PASSWORD="${CLICKHOUSE_ROOT_PASSWORD:-}"
if [[ -z "$PASSWORD" ]]; then
  # Generate secure 16-character password (alphanumeric only)
  PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-16)"
fi

# Create Kubernetes secret in SigNoz namespace
kubectl -n "$NAMESPACE" create secret generic signoz-clickhouse \
  --from-literal=password="$PASSWORD"

echo "Created secret: $NAMESPACE/signoz-clickhouse"
echo "Password: $PASSWORD"
