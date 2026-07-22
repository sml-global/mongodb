#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap-terraform-s3-backend.sh \
    --tf-dir <terraform-root-dir> \
    --bucket <s3-bucket-name> \
    --region <aws-region> \
    --key <state-object-key> \
    [--expected-bucket-owner <12-digit-aws-account-id>]

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
  local bucket="$1"
  local expected_owner="$2"
  local owner_args=()
  if [[ -n "$expected_owner" ]]; then
    owner_args=(--expected-bucket-owner "$expected_owner")
  fi

  aws s3api head-bucket --bucket "$bucket" "${owner_args[@]}" >/dev/null 2>&1
}

inspect_remote_state() {
  local bucket="$1"
  local key="$2"
  local expected_owner="$3"
  local owner_args=()
  local error_output=""
  if [[ -n "$expected_owner" ]]; then
    owner_args=(--expected-bucket-owner "$expected_owner")
  fi

  if error_output="$(aws s3api head-object \
    --bucket "$bucket" \
    --key "$key" \
    "${owner_args[@]}" 2>&1 >/dev/null)"; then
    return 0
  fi

  case "$error_output" in
    *"(404)"*|*"Not Found"*|*"NoSuchKey"*) return 1 ;;
    *)
      echo "Error: Unable to determine whether remote state exists at s3://$bucket/$key" >&2
      return 2
      ;;
  esac
}

create_bucket_if_missing() {
  local bucket="$1"
  local region="$2"
  local expected_owner="$3"
  local owner_args=()
  if [[ -n "$expected_owner" ]]; then
    owner_args=(--expected-bucket-owner "$expected_owner")
  fi

  if bucket_exists "$bucket" "$expected_owner"; then
    echo "S3 bucket exists: $bucket"
    return 0
  fi

  echo "S3 bucket missing. Creating: $bucket (region: $region)"
  # AWS S3 create-bucket is a special case: us-east-1 must not send LocationConstraint.
  if [[ "$region" == "us-east-1" ]]; then
    if ! aws s3api create-bucket --bucket "$bucket" >/dev/null 2>&1; then
      if [[ -z "$expected_owner" ]] || ! bucket_exists "$bucket" "$expected_owner"; then
        echo "Error: S3 bucket creation failed and ownership could not be confirmed: $bucket" >&2
        return 1
      fi
      echo "S3 bucket was created concurrently by the expected account: $bucket"
    fi
  else
    if ! aws s3api create-bucket \
      --bucket "$bucket" \
      --create-bucket-configuration LocationConstraint="$region" >/dev/null 2>&1; then
      if [[ -z "$expected_owner" ]] || ! bucket_exists "$bucket" "$expected_owner"; then
        echo "Error: S3 bucket creation failed and ownership could not be confirmed: $bucket" >&2
        return 1
      fi
      echo "S3 bucket was created concurrently by the expected account: $bucket"
    fi
  fi

  echo "Applying bucket baseline controls"
  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --versioning-configuration Status=Enabled >/dev/null

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  echo "S3 bucket created and baseline controls applied: $bucket"
}

verify_bucket_controls() {
  local bucket="$1"
  local requested_region="$2"
  local expected_owner="$3"
  local actual_region=""
  local versioning_status=""
  local encryption_algorithms=""
  local encryption_algorithm=""
  local public_access_block=""
  local owner_args=(--expected-bucket-owner "$expected_owner")

  if ! bucket_exists "$bucket" "$expected_owner"; then
    echo "Error: S3 bucket is inaccessible or is not owned by expected account: $bucket" >&2
    exit 1
  fi

  actual_region="$(aws s3api get-bucket-location \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --query LocationConstraint \
    --output text)"
  if [[ "$actual_region" == "None" || "$actual_region" == "null" ]]; then
    actual_region="us-east-1"
  elif [[ "$actual_region" == "EU" ]]; then
    actual_region="eu-west-1"
  fi
  if [[ "$actual_region" != "$requested_region" ]]; then
    echo "Error: S3 bucket region does not match requested region: $bucket" >&2
    exit 1
  fi

  versioning_status="$(aws s3api get-bucket-versioning \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --query Status \
    --output text)"
  if [[ "$versioning_status" != "Enabled" ]]; then
    echo "Error: S3 bucket versioning is not enabled: $bucket" >&2
    exit 1
  fi

  encryption_algorithms="$(aws s3api get-bucket-encryption \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --query 'ServerSideEncryptionConfiguration.Rules[].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text)"
  [[ -n "$encryption_algorithms" && "$encryption_algorithms" != "None" ]] || {
    echo "Error: S3 bucket encryption is not configured: $bucket" >&2
    exit 1
  }
  for encryption_algorithm in $encryption_algorithms; do
    case "$encryption_algorithm" in
      AES256) ;;
      *)
        echo "Error: S3 bucket encryption is not approved: $bucket" >&2
        exit 1
        ;;
    esac
  done

  public_access_block="$(aws s3api get-public-access-block \
    --bucket "$bucket" \
    "${owner_args[@]}" \
    --query '[PublicAccessBlockConfiguration.BlockPublicAcls,PublicAccessBlockConfiguration.IgnorePublicAcls,PublicAccessBlockConfiguration.BlockPublicPolicy,PublicAccessBlockConfiguration.RestrictPublicBuckets]' \
    --output text)"
  if [[ "$public_access_block" != $'True\tTrue\tTrue\tTrue' ]]; then
    echo "Error: S3 bucket public access block is incomplete: $bucket" >&2
    exit 1
  fi

  echo "S3 bucket ownership and baseline controls verified: $bucket"
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
  local expected_owner=""

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
      --expected-bucket-owner)
        expected_owner="$2"
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
  if [[ -n "$expected_owner" && ! "$expected_owner" =~ ^[0-9]{12}$ ]]; then
    echo "Error: --expected-bucket-owner must be a 12-digit AWS account ID" >&2
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
  create_bucket_if_missing "$bucket" "$region" "$expected_owner"
  if [[ -n "$expected_owner" ]]; then
    verify_bucket_controls "$bucket" "$region" "$expected_owner"
  fi

  echo "Preparing Terraform backend in: $tf_dir"

  local backend_owner_config=()
  if [[ -n "$expected_owner" ]]; then
    backend_owner_config=(-backend-config="expected_bucket_owner=$expected_owner")
  fi

  local remote_state_status=0
  if inspect_remote_state "$bucket" "$key" "$expected_owner"; then
    remote_state_status=0
  else
    remote_state_status=$?
  fi

  case "$remote_state_status" in
    0)
      echo "Remote state exists at s3://$bucket/$key"
      terraform -chdir="$tf_dir" init -reconfigure -input=false \
        -backend-config="bucket=$bucket" \
        -backend-config="key=$key" \
        -backend-config="region=$region" \
        -backend-config="encrypt=true" \
        "${backend_owner_config[@]}"
      echo "Backend configured to existing remote state"
      return 0
      ;;
    1) ;;
    *) return "$remote_state_status" ;;
  esac

  if [[ -f "$tf_dir/terraform.tfstate" ]]; then
    echo "Remote state missing but local terraform.tfstate found. Migrating local state once."
    terraform -chdir="$tf_dir" init -migrate-state -input=false \
      -backend-config="bucket=$bucket" \
      -backend-config="key=$key" \
      -backend-config="region=$region" \
      -backend-config="encrypt=true" \
      "${backend_owner_config[@]}"
    echo "Local state migrated to s3://$bucket/$key"
    return 0
  fi

  echo "No remote state and no local state found. Initializing fresh S3 backend."
  terraform -chdir="$tf_dir" init -reconfigure -input=false \
    -backend-config="bucket=$bucket" \
    -backend-config="key=$key" \
    -backend-config="region=$region" \
    -backend-config="encrypt=true" \
    "${backend_owner_config[@]}"
  echo "Fresh S3 backend configured at s3://$bucket/$key"
}

main "$@"
