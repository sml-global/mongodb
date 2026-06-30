#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-platform-prereq.sh <scope> [--auto-approve]

Scopes:
  all       Plan and apply unified MongoDB + PostgreSQL prerequisites.
  mongodb   Apply only MongoDB prerequisite resources from the dedicated mongodb root.
  pg        Apply only PostgreSQL resources from the dedicated postgresql root.

Examples:
  scripts/provision-platform-prereq.sh all
  scripts/provision-platform-prereq.sh mongodb
  scripts/provision-platform-prereq.sh pg --auto-approve
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_REGION="${TF_STATE_REGION:-ap-east-1}"

SCOPE="${1:-}"
AUTO_APPROVE="false"
TF_DIR=""
DEFAULT_TF_STATE_KEY=""

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

case "$SCOPE" in
  all)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/dev"
    DEFAULT_TF_STATE_KEY="oms/dev/terraform.tfstate"
    ;;
  mongodb)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/mongodb"
    DEFAULT_TF_STATE_KEY="oms/dev/mongodb/terraform.tfstate"
    ;;
  pg)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/postgresql"
    DEFAULT_TF_STATE_KEY="oms/dev/postgresql/terraform.tfstate"
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: all, mongodb, pg" >&2
    usage
    exit 1
    ;;
esac

TF_STATE_KEY="${TF_STATE_KEY:-$DEFAULT_TF_STATE_KEY}"

init_backend() {
  if [[ -n "$TF_STATE_BUCKET" ]]; then
    if [[ ! -x "$BOOTSTRAP_BACKEND_SCRIPT" ]]; then
      echo "Error: backend bootstrap script is not executable: $BOOTSTRAP_BACKEND_SCRIPT" >&2
      exit 1
    fi

    "$BOOTSTRAP_BACKEND_SCRIPT" \
      --tf-dir "$TF_DIR" \
      --bucket "$TF_STATE_BUCKET" \
      --region "$TF_STATE_REGION" \
      --key "$TF_STATE_KEY"
  else
    echo "TF_STATE_BUCKET is not set; using local Terraform state in $TF_DIR"
    terraform -chdir="$TF_DIR" init
  fi
}

run_apply() {
  local -a args=("$@")
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform -chdir="$TF_DIR" apply -input=false -auto-approve "${args[@]}"
  else
    terraform -chdir="$TF_DIR" apply -input=false "${args[@]}"
  fi
}

init_backend
terraform -chdir="$TF_DIR" fmt -recursive
terraform -chdir="$TF_DIR" validate

terraform -chdir="$TF_DIR" plan -out=tfplan
run_apply tfplan

echo "Completed scope: $SCOPE"
echo "Terraform root: $TF_DIR"
echo "State key: $TF_STATE_KEY"
