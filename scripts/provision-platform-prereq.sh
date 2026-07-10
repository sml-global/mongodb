#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-platform-prereq.sh <scope> [--auto-approve]

Scopes:
  all       Apply MongoDB then PostgreSQL prerequisites (separate roots and states).
  mongodb   Apply only MongoDB prerequisite resources from the dedicated mongodb root.
  mongo     Alias of mongodb.
  pg        Apply only PostgreSQL resources from the dedicated postgresql root.

Examples:
  scripts/provision-platform-prereq.sh all
  scripts/provision-platform-prereq.sh mongodb
  scripts/provision-platform-prereq.sh mongo
  scripts/provision-platform-prereq.sh pg --auto-approve
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-sml-oms-dev-tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-ap-east-1}"

SCOPE="${1:-}"
AUTO_APPROVE="false"
TF_DIR=""
DEFAULT_TF_STATE_KEY=""

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
    # Run mongodb then pg sequentially, each with its own root and state.
    if [[ "$AUTO_APPROVE" == "true" ]]; then
      bash "$0" mongodb --auto-approve
      bash "$0" pg --auto-approve
    else
      bash "$0" mongodb
      bash "$0" pg
    fi
    echo "Completed scope: all (mongodb + pg)"
    exit 0
    ;;
  mongodb|mongo)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/mongodb"
    DEFAULT_TF_STATE_KEY="oms/dev/mongo.tfstate"
    ;;
  pg)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/postgresql"
    DEFAULT_TF_STATE_KEY="oms/dev/pg.tfstate"
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: all, mongodb, mongo, pg" >&2
    usage
    exit 1
    ;;
esac

TF_STATE_KEY="${TF_STATE_KEY:-$DEFAULT_TF_STATE_KEY}"

ensure_tfvars() {
  local tfvars_file="$TF_DIR/terraform.tfvars"
  local sample_file="$TF_DIR/terraform.tfvars.sample"

  if [[ -f "$tfvars_file" ]]; then
    return 0
  fi

  echo "Error: missing required tfvars file: $tfvars_file" >&2
  if [[ -f "$sample_file" ]]; then
    echo "Create it from sample, then edit required values:" >&2
    if [[ "$SCOPE" == "mongodb" || "$SCOPE" == "mongo" ]]; then
      echo "  cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/terraform.tfvars" >&2
      echo "  # set cluster_name" >&2
    else
      echo "  cp platform-prerequisites/terraform/postgresql/terraform.tfvars.sample platform-prerequisites/terraform/postgresql/terraform.tfvars" >&2
      echo "  # set vpc_id, private_subnet_ids, db_master_password" >&2
    fi
  else
    echo "Error: sample file also missing: $sample_file" >&2
  fi
  exit 1
}

init_backend() {
  if [[ ! -x "$BOOTSTRAP_BACKEND_SCRIPT" ]]; then
    echo "Error: backend bootstrap script is not executable: $BOOTSTRAP_BACKEND_SCRIPT" >&2
    exit 1
  fi

  "$BOOTSTRAP_BACKEND_SCRIPT" \
    --tf-dir "$TF_DIR" \
    --bucket "$TF_STATE_BUCKET" \
    --region "$TF_STATE_REGION" \
    --key "$TF_STATE_KEY"
}

run_apply() {
  local -a args=("$@")
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform -chdir="$TF_DIR" apply -input=false -auto-approve "${args[@]}"
  else
    terraform -chdir="$TF_DIR" apply -input=false "${args[@]}"
  fi
}

resolve_tfvar_string() {
  local key="$1"
  local tfvars_file="$TF_DIR/terraform.tfvars"

  if [[ ! -f "$tfvars_file" ]]; then
    return 1
  fi

  awk -F'=' -v search_key="$key" '
    $1 ~ "^[[:space:]]*"search_key"[[:space:]]*$" {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$tfvars_file"
}

auto_import_pbm_bucket_if_needed() {
  local resource_addr="module.mongodb_prerequisites.aws_s3_bucket.pbm"
  local bucket_name=""

  if [[ "$SCOPE" != "mongodb" && "$SCOPE" != "mongo" ]]; then
    return 0
  fi

  if terraform -chdir="$TF_DIR" state show "$resource_addr" >/dev/null 2>&1; then
    return 0
  fi

  bucket_name="$(resolve_tfvar_string pbm_bucket_name || true)"
  if [[ -z "$bucket_name" ]]; then
    echo "Warning: unable to resolve pbm_bucket_name from $TF_DIR/terraform.tfvars; skipping auto-import drift recovery." >&2
    return 0
  fi

  if ! command -v aws >/dev/null 2>&1; then
    echo "Warning: aws CLI not found; cannot auto-import existing PBM bucket '$bucket_name'." >&2
    return 0
  fi

  if aws s3api head-bucket --bucket "$bucket_name" >/dev/null 2>&1; then
    echo "Detected existing PBM bucket '$bucket_name' not tracked in Terraform state. Importing for recovery..."
    terraform -chdir="$TF_DIR" import "$resource_addr" "$bucket_name"
  fi
}

ensure_tfvars
init_backend
terraform -chdir="$TF_DIR" fmt -recursive
terraform -chdir="$TF_DIR" validate

auto_import_pbm_bucket_if_needed

terraform -chdir="$TF_DIR" plan -out=tfplan
run_apply tfplan

echo "Completed scope: $SCOPE"
echo "Terraform root: $TF_DIR"
echo "State key: $TF_STATE_KEY"
