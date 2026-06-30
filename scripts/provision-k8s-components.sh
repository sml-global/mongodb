#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-k8s-components.sh <scope>

Scopes:
  mongodb   Apply MongoDB operator, Kyverno policies, bootstrap secrets, and dev overlay.
  signoz    Apply optional open-source SigNoz GitOps base only.
  operators Apply only operator Helm layer.
  policies  Apply only Kyverno policies.
  overlay   Apply only MongoDB dev overlay.
  all       Apply MongoDB scope, then SigNoz.

Examples:
  scripts/provision-k8s-components.sh signoz
  scripts/provision-k8s-components.sh mongodb
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCOPE="${1:-}"

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

case "$SCOPE" in
  mongodb)
    apply_operators
    "$ROOT_DIR/scripts/bootstrap-dev-secrets.sh"
    apply_policies
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
    echo "Error: unknown scope '$SCOPE'" >&2
    usage
    exit 1
    ;;
esac

echo "Completed Kubernetes scope: $SCOPE"
