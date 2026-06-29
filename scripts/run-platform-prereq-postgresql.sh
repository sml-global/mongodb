#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/dev-postgresql"

cd "$TF_DIR"
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan

echo "Terraform plan complete: $TF_DIR/tfplan"
echo "To apply this infrastructure, run: cd \"$TF_DIR\" && terraform apply tfplan"