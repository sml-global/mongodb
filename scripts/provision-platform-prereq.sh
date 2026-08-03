#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-platform-prereq.sh <scope> [--auto-approve]

Scopes:
  all         Apply MongoDB then PostgreSQL core+brand prerequisites (separate roots and states).
  mongodb     Apply only MongoDB prerequisite resources from the dedicated mongodb root.
  mongo       Alias of mongodb.
  pg          Alias of pg-core (kept for backward compatibility).
  pg-core     Apply only PostgreSQL "core" resources from the postgresql-core root.
  postgresql-core  Alias of pg-core.
  pg-brand    Apply only PostgreSQL "brand" resources from the postgresql-brand root.
  postgresql-brand  Alias of pg-brand.

Examples:
  scripts/provision-platform-prereq.sh all
  scripts/provision-platform-prereq.sh mongodb
  scripts/provision-platform-prereq.sh mongo
  scripts/provision-platform-prereq.sh pg-core --auto-approve
  scripts/provision-platform-prereq.sh pg-brand --auto-approve
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/legacy/dev/load-env-config.sh"

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
    # Run mongodb then pg-core sequentially, each with its own root and state.
    # pg-brand is intentionally NOT run by 'all' — brand is opt-in, applied
    # explicitly, matching the "independent lifecycle" design in
    # docs/guides/enterprise-architecture.md.
    if [[ "$AUTO_APPROVE" == "true" ]]; then
      bash "$0" mongodb --auto-approve
      bash "$0" pg-core --auto-approve
    else
      bash "$0" mongodb
      bash "$0" pg-core
    fi
    echo "Completed scope: all (mongodb + pg-core)"
    exit 0
    ;;
  mongodb|mongo)
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/mongodb"
    DEFAULT_TF_STATE_KEY="${MONGODB_STATE_KEY:-oms/dev/mongo.tfstate}"
    ;;
  pg|pg-core|postgresql-core)
    SCOPE="pg-core"
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/postgresql-core"
    DEFAULT_TF_STATE_KEY="${POSTGRESQL_CORE_STATE_KEY:-oms/dev/postgresql-core.tfstate}"
    ;;
  pg-brand|postgresql-brand)
    SCOPE="pg-brand"
    TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/postgresql-brand"
    DEFAULT_TF_STATE_KEY="${POSTGRESQL_BRAND_STATE_KEY:-oms/dev/postgresql-brand.tfstate}"
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: all, mongodb, mongo, pg-core, pg-brand" >&2
    usage
    exit 1
    ;;
esac

TF_STATE_KEY="${TF_STATE_KEY:-$DEFAULT_TF_STATE_KEY}"

# Per-environment tfvars: if the orchestrator has set ENVIRONMENT (via
# load_platform_env) and a terraform.<env>.tfvars file exists for this root,
# use it. Otherwise fall back to the single terraform.tfvars file, exactly
# matching this script's pre-existing standalone/legacy-dev behavior when
# invoked without an environment context.
TFVARS_FILE="terraform.tfvars"
if [[ -n "${ENVIRONMENT:-}" && -f "$TF_DIR/terraform.${ENVIRONMENT}.tfvars" ]]; then
  TFVARS_FILE="terraform.${ENVIRONMENT}.tfvars"
fi

ensure_tfvars() {
  local tfvars_file="$TF_DIR/$TFVARS_FILE"
  local sample_file="$TF_DIR/terraform.tfvars.sample"

  if [[ -f "$tfvars_file" ]]; then
    return 0
  fi

  echo "Error: missing required tfvars file: $tfvars_file" >&2
  if [[ -f "$sample_file" ]]; then
    echo "Create it from sample, then edit required values:" >&2
    if [[ "$SCOPE" == "mongodb" || "$SCOPE" == "mongo" ]]; then
      echo "  cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/$TFVARS_FILE" >&2
      echo "  # set cluster_name" >&2
    elif [[ "$SCOPE" == "pg-brand" ]]; then
      echo "  cp platform-prerequisites/terraform/postgresql-brand/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-brand/$TFVARS_FILE" >&2
      echo "  # set vpc_id, database_subnet_ids, allowed_source_security_group_id, cluster_kms_key_arn, aurora_engine_version" >&2
    else
      echo "  cp platform-prerequisites/terraform/postgresql-core/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-core/$TFVARS_FILE" >&2
      echo "  # set vpc_id, database_subnet_ids, allowed_source_security_group_id, cnpg_backup_bucket_name, postgresql_operator_iam_role_arn, cluster_kms_key_arn" >&2
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
  local tfvars_file="$TF_DIR/$TFVARS_FILE"

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

terraform -chdir="$TF_DIR" plan -var-file="$TFVARS_FILE" -out=tfplan
run_apply tfplan

echo "Completed scope: $SCOPE"
echo "Terraform root: $TF_DIR"
echo "Tfvars file: $TFVARS_FILE"
echo "State key: $TF_STATE_KEY"
