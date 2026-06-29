#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap-terraform-s3-backend.sh \
    --tf-dir <terraform-root-dir> \
    --bucket <s3-bucket-name> \
    --region <aws-region> \
    --key <state-object-key>

Behavior:
- Creates the S3 bucket if it does not exist.
- Applies safe baseline controls (versioning, encryption, public access block).
- If remote state object exists, configures Terraform to use it.
- If remote state object is missing but local terraform.tfstate exists, migrates local state to S3 once.
- If both are missing, configures fresh S3 backend with empty state.
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

bucket_exists() {
  aws s3api head-bucket --bucket "$1" >/dev/null 2>&1
}

remote_state_exists() {
  aws s3api head-object --bucket "$1" --key "$2" >/dev/null 2>&1
}

create_bucket_if_missing() {
  local bucket="$1"
  local region="$2"

  if bucket_exists "$bucket"; then
    echo "S3 bucket exists: $bucket"
    return 0
  fi

  echo "S3 bucket missing. Creating: $bucket (region: $region)"
  if [[ "$region" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$bucket" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --create-bucket-configuration LocationConstraint="$region" >/dev/null
  fi

  echo "Applying bucket baseline controls"
  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    --versioning-configuration Status=Enabled >/dev/null

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  echo "S3 bucket created and baseline controls applied: $bucket"
}

ensure_backend_block_exists() {
  local tf_dir="$1"
  if ! rg -n 'backend\s+"s3"' "$tf_dir"/*.tf >/dev/null 2>&1; then
    echo "Error: No Terraform backend \"s3\" block found in $tf_dir/*.tf" >&2
    echo "Add the following first:" >&2
    echo 'terraform { backend "s3" {} }' >&2
    exit 1
  fi
}

main() {
  local tf_dir=""
  local bucket=""
  local region=""
  local key=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tf-dir)
        tf_dir="$2"
        shift 2
        ;;
      --bucket)
        bucket="$2"
        shift 2
        ;;
      --region)
        region="$2"
        shift 2
        ;;
      --key)
        key="$2"
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

  if [[ -z "$tf_dir" || -z "$bucket" || -z "$region" || -z "$key" ]]; then
    echo "Error: --tf-dir, --bucket, --region, and --key are required" >&2
    usage
    exit 1
  fi

  require_cmd aws
  require_cmd terraform
  require_cmd rg

  if [[ ! -d "$tf_dir" ]]; then
    echo "Error: Terraform directory not found: $tf_dir" >&2
    exit 1
  fi

  ensure_backend_block_exists "$tf_dir"
  create_bucket_if_missing "$bucket" "$region"

  echo "Preparing Terraform backend in: $tf_dir"

  if remote_state_exists "$bucket" "$key"; then
    echo "Remote state exists at s3://$bucket/$key"
    terraform -chdir="$tf_dir" init -reconfigure -input=false \
      -backend-config="bucket=$bucket" \
      -backend-config="key=$key" \
      -backend-config="region=$region" \
      -backend-config="encrypt=true"
    echo "Backend configured to existing remote state"
    return 0
  fi

  if [[ -f "$tf_dir/terraform.tfstate" ]]; then
    echo "Remote state missing but local terraform.tfstate found. Migrating local state once."
    terraform -chdir="$tf_dir" init -migrate-state -input=false \
      -backend-config="bucket=$bucket" \
      -backend-config="key=$key" \
      -backend-config="region=$region" \
      -backend-config="encrypt=true"
    echo "Local state migrated to s3://$bucket/$key"
    return 0
  fi

  echo "No remote state and no local state found. Initializing fresh S3 backend."
  terraform -chdir="$tf_dir" init -reconfigure -input=false \
    -backend-config="bucket=$bucket" \
    -backend-config="key=$key" \
    -backend-config="region=$region" \
    -backend-config="encrypt=true"
  echo "Fresh S3 backend configured at s3://$bucket/$key"
}

main "$@"
