#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/examples/dev"
TEMPLATE_FILE="$ROOT_DIR/k8s/overlays/dev/patch-psmdb.yaml.tmpl"
INJECTED_FILE="$ROOT_DIR/k8s/overlays/dev/patch-psmdb-injected.yaml"

echo "Fetching Terraform outputs from $TF_DIR..."

get_terraform_output() {
  local output_name="$1"
  local output_value

  set +e
  output_value="$(terraform -chdir="$TF_DIR" output -raw "$output_name" 2>/dev/null)"
  local output_status=$?
  set -e

  if [[ $output_status -ne 0 ]]; then
    echo "ERROR: Terraform output '$output_name' is unavailable. Run terraform apply first." >&2
    exit 1
  fi

  if [[ -z "$output_value" ]]; then
    echo "ERROR: Terraform output '$output_name' is empty. Run terraform apply first." >&2
    exit 1
  fi

  printf '%s' "$output_value"
}

BUCKET="$(get_terraform_output backup_bucket_name)"
REGION="$(get_terraform_output backup_bucket_region)"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Missing template file: $TEMPLATE_FILE" >&2
  exit 1
fi

echo "Injecting values into dev overlay..."
sed \
  -e "s/CHANGE_ME_DEV_BACKUP_BUCKET/$BUCKET/g" \
  -e "s/CHANGE_ME_AWS_REGION/$REGION/g" \
  "$TEMPLATE_FILE" > "$INJECTED_FILE"

echo "Successfully generated $INJECTED_FILE"