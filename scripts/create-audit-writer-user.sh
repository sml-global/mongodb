#!/usr/bin/env bash
set -euo pipefail

# Creates or updates a restricted-scope MongoDB user ('audit_writer' by
# default) with an insert-only custom role on one collection ONLY
# ('oms_audit.auditlogs' by default) -- no update, no delete, no admin, no
# other databases -- and stores its connection URI as the 'oms-audit-writer'
# Kubernetes Secret that the Boomi audit log library reads.
#
# Replaces scripts/create-audit-writer-secret.sh, which built that same
# Secret from the full database-admin account instead of a scoped user
# (see issue #103). Closes the "Insert-only writer role" gap tracked in
# docs/guides/enterprise-architecture.md's Conformance Status table.
#
# One script, every environment: pass --namespace for the target
# environment's MongoDB namespace (e.g. mongodb-uat) and --secrets-file for
# that environment's password store. There is no per-environment script
# variant.
#
# Usage:
#   scripts/create-audit-writer-user.sh [--namespace <ns>] [--db <name>] \
#     [--collection <name>] [--username <name>] [--password <pass>] [--service-host <host>] \
#     [--secrets-file <path>] [--secret-name <name>]

NAMESPACE="mongodb"
DB_NAME="oms_audit"
COLLECTION_NAME="auditlogs"
USERNAME="audit_writer"
PASSWORD=""
SERVICE_HOST=""
SECRETS_FILE=""
SECRET_NAME="oms-audit-writer"
POD_LABEL="app.kubernetes.io/component=mongod"

usage() {
  cat <<'EOF'
Usage:
  create-audit-writer-user.sh [--namespace <ns>] [--db <name>] \
    [--collection <name>] [--username <name>] [--password <pass>] [--service-host <host>] \
    [--secrets-file <path>] [--secret-name <name>]

Creates or updates a MongoDB user scoped to an insert-only custom role on
one collection only, then creates or updates the 'oms-audit-writer'
Kubernetes Secret with a mongoUri built from that user (not the
database-admin account). The user cannot update, delete, or read back
records, and has no access outside the named collection.

Options:
  --namespace     Kubernetes namespace (default: mongodb)
  --db            Database the role/collection live in (default: oms_audit)
  --collection    Collection to grant insert-only access on (default: auditlogs)
  --username      MongoDB username to create/update (default: audit_writer)
  --password      Password to set (skips the secrets-file lookup below)
  --service-host  MongoDB service DNS name (default: psmdb-rs0.<namespace>.svc.cluster.local,
                   derived from --namespace; override only for a non-standard service name)
  --secrets-file  Path to a dotenv-style file holding AUDIT_WRITER_PASSWORD
                   (default: config/environments/<namespace-derived-env>-secrets.env
                   -- see config/environments/audit-writer-secrets.env.sample)
  --secret-name   Kubernetes Secret name to create/update (default: oms-audit-writer)
  -h, --help      Show this help

Password resolution order:
  1. --password, if given.
  2. AUDIT_WRITER_PASSWORD read from --secrets-file, if the file exists and
     the key is non-empty.
  3. Auto-generated (openssl rand -base64 24), printed once, and written
     back into --secrets-file so re-running this script reuses the same
     value instead of rotating the live user's password on every run.

The script connects to a running mongod pod using the userAdmin credentials
from the psmdb-secrets Kubernetes Secret (the same narrower role
scripts/create-audit-reader.sh already uses -- not the full database-admin
account).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --db) DB_NAME="${2:-}"; shift 2 ;;
    --collection) COLLECTION_NAME="${2:-}"; shift 2 ;;
    --username) USERNAME="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    --service-host) SERVICE_HOST="${2:-}"; shift 2 ;;
    --secrets-file) SECRETS_FILE="${2:-}"; shift 2 ;;
    --secret-name) SECRET_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown arg '$1'" >&2; usage; exit 1 ;;
  esac
done

# Default service host derived from the resolved namespace (same fix as
# issue #101/PR #102): the standard Kubernetes StatefulSet-Service DNS
# pattern this cluster's own mongodb verifier already relies on.
SERVICE_HOST="${SERVICE_HOST:-psmdb-rs0.${NAMESPACE}.svc.cluster.local}"

# Default secrets file derived from the namespace's environment suffix
# (e.g. mongodb-uat -> uat-secrets.env; mongodb -> dev-secrets.env for the
# legacy no-suffix namespace, matching this repo's default dev environment).
if [[ -z "$SECRETS_FILE" ]]; then
  if [[ "$NAMESPACE" == *-* ]]; then
    _env_suffix="${NAMESPACE##*-}"
  else
    _env_suffix="dev"
  fi
  SECRETS_FILE="config/environments/${_env_suffix}-secrets.env"
fi

# Read AUDIT_WRITER_PASSWORD from the secrets file without sourcing it (this
# file is untrusted-by-convention operator input, not executable config --
# same caution config/environments/<env>.env's own loader already applies).
_read_secrets_file_password() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local line value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == AUDIT_WRITER_PASSWORD=* ]] || continue
    value="${line#AUDIT_WRITER_PASSWORD=}"
    [[ -n "$value" ]] || return 1
    printf '%s' "$value"
    return 0
  done < "$file"
  return 1
}

_write_secrets_file_password() {
  local file="$1"
  local value="$2"
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]] && grep -q '^AUDIT_WRITER_PASSWORD=' "$file"; then
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    sed "s|^AUDIT_WRITER_PASSWORD=.*|AUDIT_WRITER_PASSWORD=${value}|" "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf 'AUDIT_WRITER_PASSWORD=%s\n' "$value" >> "$file"
  fi
  chmod 600 "$file"
}

if [[ -z "$PASSWORD" ]]; then
  if PASSWORD="$(_read_secrets_file_password "$SECRETS_FILE")"; then
    echo "Using existing password from $SECRETS_FILE"
  else
    PASSWORD="$(openssl rand -base64 24)"
    echo "Auto-generated password (saved to $SECRETS_FILE): $PASSWORD"
    _write_secrets_file_password "$SECRETS_FILE" "$PASSWORD"
  fi
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
echo "Creating/updating user '$USERNAME' with insert-only access on '$DB_NAME.$COLLECTION_NAME'..."

ROLE_NAME="${USERNAME}_insert_only"

kubectl -n "$NAMESPACE" exec "$POD" -c mongod -- mongosh --quiet \
  -u "$USER_ADMIN_USER" -p "$USER_ADMIN_PASS" --authenticationDatabase admin \
  --eval "
    const targetDb = db.getSiblingDB('$DB_NAME');
    const rolePrivileges = [{
      resource: { db: '$DB_NAME', collection: '$COLLECTION_NAME' },
      actions: ['insert']
    }];

    const existingRole = targetDb.getRole('$ROLE_NAME');
    if (existingRole) {
      print('Role already exists: $ROLE_NAME — updating privileges.');
      targetDb.updateRole('$ROLE_NAME', { privileges: rolePrivileges, roles: [] });
    } else {
      targetDb.createRole({
        role: '$ROLE_NAME',
        privileges: rolePrivileges,
        roles: []
      });
      print('Created role: $ROLE_NAME (insert-only on $DB_NAME.$COLLECTION_NAME)');
    }

    const existing = targetDb.getUser('$USERNAME');
    if (existing) {
      print('User already exists: $USERNAME — updating password and roles.');
      targetDb.updateUser('$USERNAME', {
        pwd: '$PASSWORD',
        roles: [{ role: '$ROLE_NAME', db: '$DB_NAME' }]
      });
    } else {
      targetDb.createUser({
        user: '$USERNAME',
        pwd: '$PASSWORD',
        roles: [{ role: '$ROLE_NAME', db: '$DB_NAME' }]
      });
      print('Created user: $USERNAME');
    }
  "

# Build the connection URI for the new restricted user (not the admin
# account) and create/update the k8s Secret the Boomi library reads.
MONGO_URI="mongodb://${USERNAME}:$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$PASSWORD")@${SERVICE_HOST}:27017/${DB_NAME}?authSource=${DB_NAME}&replicaSet=rs0"


echo "Creating/updating Secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl -n "$NAMESPACE" delete secret "$SECRET_NAME" --ignore-not-found=true >/dev/null
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal="mongoUri=$MONGO_URI"

echo ""
echo "Done. Connection details:"
echo "  Database:   $DB_NAME"
echo "  Collection: $COLLECTION_NAME (insert-only)"
echo "  Username:   $USERNAME"
echo "  Secret:     $NAMESPACE/$SECRET_NAME (key: mongoUri)"
echo "  Service:    $SERVICE_HOST"
echo ""
echo "The Boomi library reads this secret automatically -- no code needed."
echo "Boomi processes just call BoomiAuditLogLibrary.writeAuditLog(event)."
echo ""
echo "For local testing via port-forward, override with an env var instead:"
echo "  export BOOMI_AUDIT_MONGO_URI='mongodb://${USERNAME}:<password>@127.0.0.1:27017/${DB_NAME}?authSource=${DB_NAME}&directConnection=true'"
