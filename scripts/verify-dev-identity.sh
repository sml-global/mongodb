#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-mongodb}"
EXPECTED_SA="${2:-psmdb-db}"

echo "Checking MongoDB pod ServiceAccount in namespace ${NAMESPACE}"

pods="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=percona-server-mongodb -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"

if [[ -z "$pods" ]]; then
  echo "No MongoDB pods found."
  exit 1
fi

failed=0
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  sa="$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')"
  echo "Pod $pod uses ServiceAccount: $sa"
  if [[ "$sa" != "$EXPECTED_SA" ]]; then
    failed=1
  fi
done <<< "$pods"

if [[ "$failed" -ne 0 ]]; then
  echo "One or more pods are not using expected ServiceAccount: $EXPECTED_SA"
  exit 2
fi

echo "All MongoDB pods use expected ServiceAccount: $EXPECTED_SA"
