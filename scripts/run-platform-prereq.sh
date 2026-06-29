#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/dev"
BOOTSTRAP_BACKEND_SCRIPT="$ROOT_DIR/scripts/bootstrap-terraform-s3-backend.sh"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_REGION="${TF_STATE_REGION:-us-east-1}"
TF_STATE_KEY="${TF_STATE_KEY:-mongodb/platform-prerequisites/dev/terraform.tfstate}"

cd "$TF_DIR"

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
	terraform init
fi

terraform fmt -recursive
terraform validate
terraform plan -out=tfplan

echo "Terraform plan complete: $TF_DIR/tfplan"
echo "To apply this infrastructure, run: cd \"$TF_DIR\" && terraform apply tfplan"