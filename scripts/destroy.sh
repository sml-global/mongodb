#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  destroy.sh <scope> [--auto-approve] [--keep-signoz-namespace]

Scopes:
  all       Remove SigNoz + MongoDB + PostgreSQL resources (dev teardown).
  mongodb   Remove MongoDB Kubernetes workloads/secrets, then destroy MongoDB Terraform scope.
  mongo     Alias of mongodb.
  pg        Destroy PostgreSQL Terraform scope.
  signoz    Remove SigNoz HelmRelease and namespace resources.
  signoz-observability  Destroy dashboards/alerts Terraform state (run before 'signoz' so the API is still reachable).

Options:
  --auto-approve          Skip Terraform approval prompts.
  --keep-signoz-namespace Keep signoz namespace object (delete app resources only).
  -h, --help              Show this help.

Examples:
  bash scripts/destroy.sh mongodb
  bash scripts/destroy.sh pg --auto-approve
  bash scripts/destroy.sh signoz
  bash scripts/destroy.sh signoz-observability --auto-approve
  bash scripts/destroy.sh all --auto-approve
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-sml-oms-dev-tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-ap-east-1}"

SCOPE="${1:-}"
AUTO_APPROVE="false"
KEEP_SIGNOZ_NAMESPACE="false"

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
    --auto-approve)
      AUTO_APPROVE="true"
      shift
      ;;
    --keep-signoz-namespace)
      KEEP_SIGNOZ_NAMESPACE="true"
      shift
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

ensure_tfvars() {
  local tf_dir="$1"
  local tfvars_file="$tf_dir/terraform.tfvars"
  local sample_file="$tf_dir/terraform.tfvars.sample"

  if [[ -f "$tfvars_file" ]]; then
    return 0
  fi

  echo "Error: missing required tfvars file: $tfvars_file" >&2
  if [[ -f "$sample_file" ]]; then
    echo "Create it from sample and set required values:" >&2
    echo "  cp $sample_file $tfvars_file" >&2
  fi
  exit 1
}

terraform_destroy_scope() {
  local scope="$1"
  local tf_dir=""
  local tf_state_key=""

  case "$scope" in
    mongodb|mongo)
      tf_dir="$ROOT_DIR/platform-prerequisites/terraform/mongodb"
      tf_state_key="oms/dev/mongo.tfstate"
      ;;
    pg)
      tf_dir="$ROOT_DIR/platform-prerequisites/terraform/postgresql"
      tf_state_key="oms/dev/pg.tfstate"
      ;;
    *)
      echo "Error: unsupported terraform destroy scope '$scope'" >&2
      exit 1
      ;;
  esac

  ensure_tfvars "$tf_dir"

  "$BOOTSTRAP_BACKEND_SCRIPT" \
    --tf-dir "$tf_dir" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$tf_state_key"

  echo "Destroying Terraform scope: $scope"
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform -chdir="$tf_dir" destroy -input=false -auto-approve
  else
    terraform -chdir="$tf_dir" destroy -input=false
  fi
}

destroy_signoz() {
  echo "Removing SigNoz HelmRelease and workload resources..."
  kubectl -n signoz delete helmrelease signoz --ignore-not-found=true || true

  if [[ "$KEEP_SIGNOZ_NAMESPACE" == "true" ]]; then
    echo "Keeping signoz namespace (--keep-signoz-namespace)."
    return 0
  fi

  if ! kubectl get namespace signoz >/dev/null 2>&1; then
    echo "signoz namespace already absent."
    return 0
  fi

  echo "Removing signoz namespace (non-blocking)..."
  # --wait=false: kubectl delete on a namespace blocks until fully terminated,
  # which never happens if a ClickHouse finalizer is stuck. Issue the delete
  # without waiting so we can clear finalizers below, then wait explicitly.
  kubectl delete namespace signoz --ignore-not-found=true --wait=false || true

  echo "Clearing ClickHouse/namespace finalizers if present..."
  local deadline=$((SECONDS + 60))
  while kubectl get namespace signoz >/dev/null 2>&1 && (( SECONDS < deadline )); do
    kubectl -n signoz get clickhouseinstallations.clickhouse.altinity.com -o name 2>/dev/null \
      | xargs -I{} kubectl -n signoz patch {} --type='json' -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
    kubectl patch namespace signoz --type='json' -p='[{"op":"replace","path":"/spec/finalizers","value":[]}]' >/dev/null 2>&1 || true
    sleep 3
  done

  if kubectl get namespace signoz >/dev/null 2>&1; then
    echo "Warning: signoz namespace still present after finalizer cleanup attempts." >&2
  else
    echo "signoz namespace removed."
  fi
}

destroy_mongodb_k8s() {
  echo "Removing MongoDB workload resources..."
  kubectl -n mongodb delete perconaservermongodb psmdb --ignore-not-found=true || true
  kubectl -n mongodb delete helmrelease percona-server-mongodb-operator --ignore-not-found=true || true

  # Remove cert-manager resources commonly created for MongoDB in this repo.
  kubectl -n mongodb delete certificate mongodb-ca mongodb-app-client psmdb-ca-cert psmdb-ssl psmdb-ssl-internal --ignore-not-found=true || true
  kubectl -n mongodb delete issuer mongodb-selfsigned mongodb-ca-issuer psmdb-issuer psmdb-ca-issuer --ignore-not-found=true || true

  echo "Removing MongoDB secrets and local escrow files..."
  kubectl -n mongodb delete secret psmdb-encryption-key psmdb-secrets internal-psmdb-users oms-audit-writer --ignore-not-found=true || true
  rm -f "$ROOT_DIR/.local-dev-encryption-key.txt" "$ROOT_DIR/.local-dev-user-passwords.txt"
}

destroy_mongodb() {
  destroy_mongodb_k8s
  terraform_destroy_scope mongodb
}

destroy_pg() {
  terraform_destroy_scope pg
}

destroy_signoz_observability() {
  local tf_dir="$ROOT_DIR/platform-prerequisites/terraform/signoz-observability"
  local tf_state_key="oms/dev/signoz-observability.tfstate"
  local pf_pid=""

  if ! kubectl -n signoz get secret signoz-api-key >/dev/null 2>&1; then
    echo "signoz-api-key Secret not found; nothing to destroy for signoz-observability (or it was never applied)."
    return 0
  fi

  export SIGNOZ_ACCESS_TOKEN
  SIGNOZ_ACCESS_TOKEN="$(kubectl -n signoz get secret signoz-api-key -o jsonpath='{.data.token}' | base64 -d)"
  export SIGNOZ_ENDPOINT="${SIGNOZ_ENDPOINT:-http://127.0.0.1:3301}"

  # Self-manage a temporary port-forward so this scope never depends on the
  # operator having a separate `open-signoz-ui.sh` session already running.
  if [[ "$SIGNOZ_ENDPOINT" =~ ^https?://(127\.0\.0\.1|localhost):([0-9]+)$ ]]; then
    local endpoint_local_port="${BASH_REMATCH[2]}"
    if ! curl -s -o /dev/null --max-time 2 "$SIGNOZ_ENDPOINT/api/v1/health"; then
      echo "Starting temporary port-forward to signoz:8080 on 127.0.0.1:${endpoint_local_port} ..."
      kubectl -n signoz port-forward svc/signoz "${endpoint_local_port}:8080" >/tmp/signoz-observability-destroy-pf.log 2>&1 &
      pf_pid=$!
      for _ in $(seq 1 30); do
        curl -s -o /dev/null --max-time 2 "$SIGNOZ_ENDPOINT/api/v1/health" && break
        sleep 1
      done
    fi
  fi

  if ! curl -sf -o /dev/null "$SIGNOZ_ENDPOINT/api/v1/health"; then
    echo "Warning: SigNoz endpoint $SIGNOZ_ENDPOINT is not reachable; skipping signoz-observability terraform destroy." >&2
    echo "(Its resources will be removed anyway when the signoz namespace/PVCs are deleted.)" >&2
    [[ -n "$pf_pid" ]] && kill "$pf_pid" >/dev/null 2>&1 || true
    return 0
  fi

  "$BOOTSTRAP_BACKEND_SCRIPT" \
    --tf-dir "$tf_dir" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$tf_state_key"

  echo "Destroying Terraform scope: signoz-observability"
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform -chdir="$tf_dir" destroy -input=false -auto-approve
  else
    terraform -chdir="$tf_dir" destroy -input=false
  fi

  [[ -n "$pf_pid" ]] && kill "$pf_pid" >/dev/null 2>&1 || true
}

main() {
  require_cmd kubectl
  require_cmd terraform
  require_cmd aws

  if [[ ! -x "$BOOTSTRAP_BACKEND_SCRIPT" ]]; then
    echo "Error: backend bootstrap script is not executable: $BOOTSTRAP_BACKEND_SCRIPT" >&2
    exit 1
  fi

  case "$SCOPE" in
    signoz)
      destroy_signoz
      ;;
    signoz-observability)
      destroy_signoz_observability
      ;;
    mongodb|mongo)
      destroy_mongodb
      ;;
    pg)
      destroy_pg
      ;;
    all)
      destroy_signoz_observability
      destroy_signoz
      destroy_mongodb
      destroy_pg
      ;;
    *)
      echo "Error: unknown scope '$SCOPE'. Expected one of: all, mongodb, mongo, pg, signoz, signoz-observability" >&2
      usage
      exit 1
      ;;
  esac

  echo "Completed destroy scope: $SCOPE"
}

main
