#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH=""
OUTPUT_PATH=""
TEMP_OUTPUT=""

usage() {
  cat <<'EOF'
Usage:
  validate-uat-workforce-principals.sh --input <json> --output <json>

Validates the four UAT AWS IAM Identity Center role ARNs without calling AWS
and writes the three roles used for EKS access to the output file.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

reject_directory_output() {
  [[ ! -d "$OUTPUT_PATH" ]] || fail "output path must not be a directory or resolve to a directory; choose a regular file path: $OUTPUT_PATH"
}

cleanup() {
  if [[ -n "$TEMP_OUTPUT" ]]; then
    rm -f "$TEMP_OUTPUT"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      [[ $# -ge 2 && -n "$2" ]] || fail "--input requires a JSON file path."
      INPUT_PATH="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 && -n "$2" ]] || fail "--output requires a JSON file path."
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$INPUT_PATH" ]] || fail "missing required --input <json> argument."
[[ -n "$OUTPUT_PATH" ]] || fail "missing required --output <json> argument."
[[ -r "$INPUT_PATH" ]] || fail "input JSON is not readable: $INPUT_PATH"
command -v jq >/dev/null 2>&1 || fail "jq is required for offline principal validation."

OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
OUTPUT_NAME="$(basename "$OUTPUT_PATH")"
[[ -d "$OUTPUT_DIR" ]] || fail "output directory does not exist: $OUTPUT_DIR"
[[ -w "$OUTPUT_DIR" ]] || fail "output directory is not writable: $OUTPUT_DIR"
reject_directory_output

if ! jq -e '
  type == "object" and
  keys == [
    "application_developer_role_arn",
    "boomi_admin_role_arn",
    "infra_admin_role_arn",
    "process_owner_role_arn"
  ]
' "$INPUT_PATH" >/dev/null; then
  fail "input must be a JSON object with exactly four required keys: infra_admin_role_arn, application_developer_role_arn, boomi_admin_role_arn, and process_owner_role_arn."
fi

if ! jq -e '
  all(.[]; type == "string") and
  all(.[]; startswith("arn:aws:iam::672172129937:role/"))
' "$INPUT_PATH" >/dev/null; then
  fail "every principal must be a role ARN in UAT account 672172129937."
fi

if ! jq -e '[.[]] | length == (unique | length)' "$INPUT_PATH" >/dev/null; then
  fail "all four UAT workforce principal ARNs must be unique."
fi

if ! jq -e '
  .infra_admin_role_arn |
  test("^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATInfraAdminEA_[A-Za-z0-9]+$")
' "$INPUT_PATH" >/dev/null; then
  fail "infra_admin_role_arn must be an AWSReservedSSO_UATInfraAdminEA role in UAT account 672172129937."
fi

if ! jq -e '
  .application_developer_role_arn |
  test("^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATApplicationDeveloper_[A-Za-z0-9]+$")
' "$INPUT_PATH" >/dev/null; then
  fail "application_developer_role_arn must be an AWSReservedSSO_UATApplicationDeveloper role in UAT account 672172129937."
fi

if ! jq -e '
  .boomi_admin_role_arn |
  test("^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATBoomiAdmin_[A-Za-z0-9]+$")
' "$INPUT_PATH" >/dev/null; then
  fail "boomi_admin_role_arn must be an AWSReservedSSO_UATBoomiAdmin role in UAT account 672172129937."
fi

if ! jq -e '
  .process_owner_role_arn |
  test("^arn:aws:iam::672172129937:role/aws-reserved/sso\\.amazonaws\\.com/[^/]+/AWSReservedSSO_UATBoomiProcessOwner_[A-Za-z0-9]+$")
' "$INPUT_PATH" >/dev/null; then
  fail "process_owner_role_arn must be an AWSReservedSSO_UATBoomiProcessOwner role in UAT account 672172129937."
fi

TEMP_OUTPUT="$(mktemp "$OUTPUT_DIR/.${OUTPUT_NAME}.tmp.XXXXXX")"
if ! jq '{
  infra_admin_role_arn,
  application_developer_role_arn,
  boomi_admin_role_arn
}' "$INPUT_PATH" > "$TEMP_OUTPUT"; then
  fail "could not generate EKS principal output from: $INPUT_PATH"
fi

jq empty "$TEMP_OUTPUT" || fail "generated output is not valid JSON."
chmod 0600 "$TEMP_OUTPUT" || fail "could not set output permissions to 0600."
reject_directory_output
mv -f "$TEMP_OUTPUT" "$OUTPUT_PATH" || fail "could not atomically replace output: $OUTPUT_PATH"
TEMP_OUTPUT=""

echo "Validated UAT workforce principals and wrote EKS access roles to: $OUTPUT_PATH"
