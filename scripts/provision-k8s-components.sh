#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-k8s-components.sh <scope>

Scopes:
  mongodb   Apply MongoDB operator, Kyverno policies, bootstrap secrets, and dev overlay.
  mongo     Alias of mongodb.
  signoz    Apply optional open-source SigNoz GitOps base only.
  operators Apply only operator Helm layer.
  policies  Apply only Kyverno policies.
  overlay   Apply only MongoDB dev overlay.
  all       Apply MongoDB scope, then SigNoz.

Examples:
  scripts/provision-k8s-components.sh signoz
  scripts/provision-k8s-components.sh mongodb
  scripts/provision-k8s-components.sh mongo
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCOPE="${1:-}"
MONGODB_CRD_NAME="perconaservermongodbs.psmdb.percona.com"
WAIT_TIMEOUT_SECONDS="${MONGODB_OPERATOR_READY_TIMEOUT_SECONDS:-180}"

if [[ -z "$SCOPE" ]]; then
  usage
  exit 1
fi

apply_operators() {
  kubectl apply -k "$ROOT_DIR/gitops/operators/base"
}

apply_policies() {
  kubectl apply -k "$ROOT_DIR/policies/kyverno"
}

apply_overlay() {
  kubectl apply -k "$ROOT_DIR/k8s/overlays/dev"
}

apply_signoz() {
  kubectl apply -k "$ROOT_DIR/gitops/signoz/base"
}

wait_for_mongodb_crd() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  echo "Waiting for MongoDB CRD $MONGODB_CRD_NAME (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."
  while ! kubectl get crd "$MONGODB_CRD_NAME" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: MongoDB CRD '$MONGODB_CRD_NAME' not found within ${WAIT_TIMEOUT_SECONDS}s." >&2
      echo "Hint: ensure Flux and the operator HelmRelease are healthy before applying the overlay." >&2
      exit 1
    fi
    sleep 5
  done
}

case "$SCOPE" in
  mongodb|mongo)
    apply_operators
    "$ROOT_DIR/scripts/bootstrap-dev-secrets.sh"
    apply_policies
    wait_for_mongodb_crd
    apply_overlay
    ;;
  signoz)
    apply_signoz
    ;;
  operators)
    apply_operators
    ;;
  policies)
    apply_policies
    ;;
  overlay)
    apply_overlay
    ;;
  all)
    "$0" mongodb
    "$0" signoz
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, mongo, signoz, operators, policies, overlay, all" >&2
    usage
    exit 1
    ;;
esac

echo "Completed Kubernetes scope: $SCOPE"
