#!/usr/bin/env bash
set -euo pipefail

# Creates the Kubernetes Secret that bootstraps the SigNoz "root user" at
# startup (SigNoz Root User Configuration feature, v0.112.0+). This removes
# the manual first-visit "Sign Up" step in the SigNoz UI: the admin account
# is provisioned automatically when the signoz pod starts, driven entirely by
# this Secret + the SIGNOZ_USER_ROOT_* env vars wired in
# gitops/signoz/base/helmreleases.yaml.
#
# Reference: https://signoz.io/docs/manage/administrator-guide/configuration/root-user/
#
# Usage:
#   scripts/create-signoz-root-user-secret.sh [--namespace <ns>] [--email <email>] [--org-name <name>]

NAMESPACE="signoz"
SECRET_NAME="signoz-root-user"
EMAIL="admin@oms.local"
ORG_NAME="oms"
PASSWORDS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.local-dev-user-passwords.txt"

usage() {
  cat <<'EOF'
Usage:
  create-signoz-root-user-secret.sh [--namespace <ns>] [--email <email>] [--org-name <name>]

Creates the Kubernetes Secret 'signoz-root-user' with 'email' and 'password'
keys, consumed by gitops/signoz/base/helmreleases.yaml to auto-provision the
SigNoz admin (root) user at pod startup. No manual UI signup required.

Options:
  --namespace   Kubernetes namespace (default: signoz)
  --email       Root user email/login (default: admin@oms.local)
  --org-name    Organization name (default: oms) -- must match
                SIGNOZ_USER_ROOT_ORG_NAME in the HelmRelease values.
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --org-name) ORG_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown arg '$1'" >&2; usage; exit 1 ;;
  esac
done

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'. Skipping."
  echo "To rotate the password, delete it first: kubectl -n $NAMESPACE delete secret $SECRET_NAME"
  exit 0
fi

# SigNoz requires >=12 chars with at least one uppercase, one lowercase, one
# digit, and one symbol from its allowed set (~!@#$%^&*()_+`-={}|[]\:"<>?,./).
# The trailing "Aa1!" guarantees all classes are present.
PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-16)Aa1!"

kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal="email=$EMAIL" \
  --from-literal="password=$PASSWORD"

{
  echo ""
  echo "# SigNoz root user (generated $(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "SIGNOZ_ROOT_EMAIL=$EMAIL"
  echo "SIGNOZ_ROOT_PASSWORD=$PASSWORD"
  echo "SIGNOZ_ROOT_ORG_NAME=$ORG_NAME"
} >> "$PASSWORDS_FILE"

echo ""
echo "Created secret: $NAMESPACE/$SECRET_NAME"
echo "  email:    $EMAIL"
echo "  org name: $ORG_NAME"
echo "  password: saved to $PASSWORDS_FILE (gitignored)"
echo ""
echo "Next steps:"
echo "1. Ensure gitops/signoz/base/helmreleases.yaml wires SIGNOZ_USER_ROOT_* to this secret."
echo "2. Apply/refresh SigNoz: bash scripts/provision.sh signoz"
echo "3. Log in at the SigNoz UI with the email/password above -- no signup needed."
