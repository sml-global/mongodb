#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export-database-snapshot.sh <mongodb|postgresql> [--wait-timeout-seconds N]

Triggers an on-demand, native backup for the given database into its
existing, already-configured S3 destination:
  mongodb     Runs `pbm backup --wait` inside the PBM agent container.
  postgresql  Applies a CNPG on-demand `Backup` custom resource and polls
              its status until it reaches `completed` or `failed`.

Options:
  --wait-timeout-seconds N  Timeout for waiting on completion (default: 900).
  -h, --help                Show this help.

Examples:
  scripts/export-database-snapshot.sh mongodb
  scripts/export-database-snapshot.sh postgresql --wait-timeout-seconds 1800
EOF
}

SCOPE="${1:-}"
WAIT_TIMEOUT_SECONDS="900"

if [[ "$SCOPE" == "-h" || "$SCOPE" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$SCOPE" ]]; then
  usage
  exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait-timeout-seconds)
      if ! [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --wait-timeout-seconds requires a positive integer, got: ${2:-<missing>}" >&2
        exit 1
      fi
      WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

export_mongodb() {
  local namespace="${MONGODB_NAMESPACE:-mongodb}"
  local pbm_pod
  pbm_pod="$(kubectl -n "$namespace" get pods -l app.kubernetes.io/component=mongod -o jsonpath='{.items[0].metadata.name}')"
  if [[ -z "$pbm_pod" ]]; then
    echo "ERROR: no MongoDB pod found in namespace '$namespace' (label app.kubernetes.io/component=mongod)." >&2
    return 1
  fi
  echo "Triggering on-demand PBM backup on pod $pbm_pod (namespace $namespace) ..."
  kubectl -n "$namespace" exec "$pbm_pod" -c pbm-agent -- \
    pbm backup --wait --wait-time "${WAIT_TIMEOUT_SECONDS}s" --mongodb-uri="mongodb://localhost:27017"
}

export_postgresql() {
  # Backup CR schema (spec.method, spec.cluster.name, status.phase=completed|failed)
  # verified against CNPG operator 1.24.x docs (pinned version in gitops/postgresql/base/operator.yaml).
  local namespace="${POSTGRESQL_NAMESPACE:-postgresql}"
  local cluster_name="${POSTGRESQL_CLUSTER_NAME:-oms-postgresql}"
  local backup_name="on-demand-$(date -u +%Y%m%dt%H%M%Sz)"

  echo "Requesting on-demand CNPG backup '$backup_name' for cluster '$cluster_name' ..."
  cat <<EOF | kubectl -n "$namespace" apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $namespace
spec:
  method: barmanObjectStore
  cluster:
    name: $cluster_name
EOF

  echo "Waiting for backup '$backup_name' to complete (timeout: ${WAIT_TIMEOUT_SECONDS}s) ..."
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
  while true; do
    local phase
    phase="$(kubectl -n "$namespace" get backup "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      completed)
        echo "Backup '$backup_name' completed."
        return 0
        ;;
      failed)
        echo "ERROR: backup '$backup_name' failed." >&2
        return 1
        ;;
    esac
    if (( SECONDS >= deadline )); then
      echo "ERROR: timed out waiting for backup '$backup_name' to complete (last phase: ${phase:-unknown})." >&2
      return 1
    fi
    sleep 5
  done
}

case "$SCOPE" in
  mongodb|mongo)
    export_mongodb
    ;;
  postgresql|pg)
    export_postgresql
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, postgresql" >&2
    usage
    exit 1
    ;;
esac

echo "Completed on-demand export for scope: $SCOPE"
