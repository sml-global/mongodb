#!/usr/bin/env bash
set -euo pipefail

# Create ClickHouse root user secret in signoz namespace
# This script is idempotent: safe to run multiple times

# Ensure namespace exists (idempotent, no field-manager drift)
kubectl get namespace signoz >/dev/null 2>&1 || kubectl create namespace signoz

# Check if secret already exists (idempotent)
if kubectl -n signoz get secret signoz-clickhouse >/dev/null 2>&1; then
  echo "Secret signoz-clickhouse already exists; skipping creation"
  exit 0
fi

# Accept password from environment variable or generate secure password
PASSWORD="${CLICKHOUSE_ROOT_PASSWORD:-}"
if [[ -z "$PASSWORD" ]]; then
  # Generate secure 16-character password (alphanumeric only)
  PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-16)"
fi

# Create Kubernetes secret in signoz namespace
kubectl -n signoz create secret generic signoz-clickhouse \
  --from-literal=password="$PASSWORD"

echo "Created secret: signoz/signoz-clickhouse"
echo "Password: $PASSWORD"
