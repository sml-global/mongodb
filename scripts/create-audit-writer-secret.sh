#!/usr/bin/env bash
set -euo pipefail

# Creates a Kubernetes Secret containing the MongoDB connection URI for the
# audit log writer (Boomi library). This is the recommended secret source
# for the BoomiAuditLogLibrary — free, no AWS Secrets Manager needed.
#
# The URI uses the database-admin credentials from psmdb-secrets and the
# internal MongoDB service endpoint.
#
# Usage:
#   scripts/create-audit-writer-secret.sh [--namespace <ns>] [--db <name>]

NAMESPACE="mongodb"
DB_NAME="oms_audit"
SECRET_NAME="oms-audit-writer"
SERVICE_HOST="psmdb-rs0.mongodb.svc.cluster.local"

usage() {
  cat <<'EOF'
Usage:
  create-audit-writer-secret.sh [--namespace <ns>] [--db <name>] [--secret-name <name>]

Creates the Kubernetes Secret 'oms-audit-writer' with a mongoUri key containing
the full MongoDB connection string for audit log writes.

Options:
  --namespace     Kubernetes namespace (default: mongodb)
  --db            Target database (default: oms_audit)
  --secret-name   Secret name to create (default: oms-audit-writer)
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --db) DB_NAME="${2:-}"; shift 2 ;;
    --secret-name) SECRET_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown arg '$1'" >&2; usage; exit 1 ;;
  esac
done

# Check if secret already exists
if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'. Skipping."
  echo "To recreate, delete it first: kubectl -n $NAMESPACE delete secret $SECRET_NAME"
  exit 0
fi

# Read database-admin credentials from existing psmdb-secrets
echo "Reading database-admin credentials from psmdb-secrets..."
ADMIN_USER="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_DATABASE_ADMIN_USER}' | base64 -d)"
ADMIN_PASS="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_DATABASE_ADMIN_PASSWORD}' | base64 -d)"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
  echo "Error: cannot read database-admin credentials from psmdb-secrets" >&2
  exit 1
fi

# URL-encode password (handle special chars)
ENCODED_PASS="$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ADMIN_PASS', safe=''))")"

# Build MongoDB URI
# Uses the replica set service endpoint for internal cluster access
MONGO_URI="mongodb://${ADMIN_USER}:${ENCODED_PASS}@${SERVICE_HOST}:27017/${DB_NAME}?authSource=admin&replicaSet=rs0"

# Create the secret
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal="mongoUri=$MONGO_URI"

echo ""
echo "Created secret: $NAMESPACE/$SECRET_NAME"
echo "  Key: mongoUri"
echo "  Database: $DB_NAME"
echo "  Service: $SERVICE_HOST"
echo ""
echo "The Boomi library reads this secret automatically -- no code needed."
echo "Boomi processes just call BoomiAuditLogLibrary.writeAuditLog(event)."
echo ""
echo "For local testing via port-forward, override with an env var instead:"
echo "  export BOOMI_AUDIT_MONGO_URI='mongodb://${ADMIN_USER}:<password>@127.0.0.1:27017/${DB_NAME}?authSource=admin&directConnection=true'"
