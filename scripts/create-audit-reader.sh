#!/usr/bin/env bash
set -euo pipefail

# Creates a read-only MongoDB user for querying audit logs.
# This user can ONLY read from the audit database — no writes, no admin.
#
# Usage:
#   scripts/create-audit-reader.sh [--namespace <ns>] [--db <name>] [--username <name>] [--password <pass>]
#
# Defaults:
#   --namespace  mongodb
#   --db         oms_audit
#   --username   audit_reader
#   --password   (auto-generated if not provided)

NAMESPACE="mongodb"
DB_NAME="oms_audit"
USERNAME="audit_reader"
PASSWORD=""
POD_LABEL="app.kubernetes.io/component=mongod"

usage() {
  cat <<'EOF'
Usage:
  create-audit-reader.sh [--namespace <ns>] [--db <name>] [--username <name>] [--password <pass>]

Creates a read-only MongoDB user for querying audit logs.

Options:
  --namespace   Kubernetes namespace (default: mongodb)
  --db          Database to grant read access on (default: oms_audit)
  --username    Username to create (default: audit_reader)
  --password    Password (auto-generated if omitted)
  -h, --help    Show this help

The script connects to the PRIMARY MongoDB pod using the userAdmin credentials
from the psmdb-secrets Kubernetes Secret.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --db) DB_NAME="${2:-}"; shift 2 ;;
    --username) USERNAME="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown arg '$1'" >&2; usage; exit 1 ;;
  esac
done

# Auto-generate password if not provided
if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(openssl rand -base64 24)"
  echo "Auto-generated password (save this): $PASSWORD"
fi

# Get userAdmin credentials from cluster secret
echo "Reading userAdmin credentials from psmdb-secrets..."
USER_ADMIN_USER="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_USER_ADMIN_USER}' | base64 -d)"
USER_ADMIN_PASS="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_USER_ADMIN_PASSWORD}' | base64 -d)"

if [[ -z "$USER_ADMIN_USER" || -z "$USER_ADMIN_PASS" ]]; then
  echo "Error: cannot read userAdmin credentials from psmdb-secrets in namespace $NAMESPACE" >&2
  exit 1
fi

# Find a running mongod pod
POD="$(kubectl -n "$NAMESPACE" get pods -l "$POD_LABEL" --no-headers \
  -o custom-columns=':metadata.name' | head -1)"

if [[ -z "$POD" ]]; then
  echo "Error: no running mongod pod found in namespace $NAMESPACE" >&2
  exit 1
fi

echo "Using pod: $POD"
echo "Creating user '$USERNAME' with read access on database '$DB_NAME'..."

# Create the read-only user via mongosh
kubectl -n "$NAMESPACE" exec "$POD" -c mongod -- mongosh --quiet \
  -u "$USER_ADMIN_USER" -p "$USER_ADMIN_PASS" --authenticationDatabase admin \
  --eval "
    const targetDb = db.getSiblingDB('$DB_NAME');
    const existing = targetDb.getUser('$USERNAME');
    if (existing) {
      print('User already exists: $USERNAME — updating password and roles.');
      targetDb.updateUser('$USERNAME', {
        pwd: '$PASSWORD',
        roles: [{ role: 'read', db: '$DB_NAME' }]
      });
    } else {
      targetDb.createUser({
        user: '$USERNAME',
        pwd: '$PASSWORD',
        roles: [{ role: 'read', db: '$DB_NAME' }]
      });
      print('Created user: $USERNAME');
    }
  "

echo ""
echo "Done. Connection details:"
echo "  Database: $DB_NAME"
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo "  Auth DB:  $DB_NAME"
echo ""
echo "Connection string (via port-forward to psmdb-rs0 service):"
echo "  mongodb://${USERNAME}:<password>@127.0.0.1:27017/${DB_NAME}?authSource=${DB_NAME}&directConnection=true"
echo ""
echo "Example query:"
echo "  mongosh 'mongodb://${USERNAME}:${PASSWORD}@127.0.0.1:27017/${DB_NAME}?authSource=${DB_NAME}&directConnection=true' \\"
echo "    --eval \"db.auditlogs.find().sort({time:-1}).limit(5)\""
