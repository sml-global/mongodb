#!/usr/bin/env bash
# logging-helpers.sh — Structured telemetry logging for bash scripts
# Enforces unified schema across all operational logs (same 10 fields as MongoDB audit)

# Emit structured telemetry log to SigNoz (via stdout → OTEL agent)
# Usage: log_telemetry <severity> <message> <action> <error_code> <resource_type> <resource_id> <user_id>
#
# Example (infrastructure warning):
#   log_telemetry "WARN" "Secret not found, using fallback" "config.fallback" "CONFIG_NOT_FOUND" "config.secret" "mongodb/oms-audit-writer" ""
#
# Example (business failure):
#   log_telemetry "ERROR" "MongoDB write failed" "boomi.document.load" "MONGO_TIMEOUT" "boomi.document" "TCHIBO-0001.csv" ""
log_telemetry() {
  local severity="$1"           # ERROR | WARN | INFO | DEBUG
  local message="$2"            # Human-readable message
  local action="$3"             # Action (e.g., "boomi.document.load", "config.fallback")
  local error_code="$4"         # Error code (null if success, e.g., "MONGO_TIMEOUT")
  local resource_type="$5"      # Resource type (e.g., "boomi.document", "config.secret")
  local resource_id="$6"        # Resource ID (empty if N/A)
  local user_id="$7"            # User ID (empty if automated)

  local service="${SERVICE_NAME:-unknown}"
  local trace_id="${TRACE_ID:-$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'unknown')}"
  local timestamp

  # Try to get millisecond precision timestamp
  if date --version 2>/dev/null | grep -q GNU; then
    # GNU date (Linux)
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  elif command -v gdate >/dev/null 2>&1; then
    # GNU date via Homebrew (macOS)
    timestamp="$(gdate -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  else
    # BSD date fallback (no milliseconds)
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi

  # ALWAYS include unified schema fields (empty string if not provided)
  cat <<EOF
{
  "timestamp": "$timestamp",
  "severity": "$severity",
  "message": "$message",
  "trace_id": "$trace_id",
  "ip": "",
  "action": "${action:-}",
  "error_code": "${error_code:-}",
  "resource_type": "${resource_type:-}",
  "resource_id": "${resource_id:-}",
  "user_id": "${user_id:-}",
  "meta": {}
}
EOF
}

# Emit telemetry with additional metadata
# Usage: log_telemetry_with_meta <severity> <message> <action> <error_code> <resource_type> <resource_id> <user_id> <meta_json>
#
# Example:
#   log_telemetry_with_meta "ERROR" "MongoDB write failed" "boomi.document.load" "MONGO_TIMEOUT" \
#     "boomi.document" "TCHIBO-0001.csv" "" '{"boomi_process_id":"EU-TC-0001","retry_count":3}'
log_telemetry_with_meta() {
  local severity="$1"
  local message="$2"
  local action="$3"
  local error_code="$4"
  local resource_type="$5"
  local resource_id="$6"
  local user_id="$7"
  local meta_json="$8"  # JSON object as string

  local service="${SERVICE_NAME:-unknown}"
  local trace_id="${TRACE_ID:-$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'unknown')}"
  local timestamp

  if date --version 2>/dev/null | grep -q GNU; then
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  elif command -v gdate >/dev/null 2>&1; then
    timestamp="$(gdate -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  else
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi

  # Validate meta_json is valid JSON (basic check)
  if [[ -n "$meta_json" ]] && ! echo "$meta_json" | jq empty 2>/dev/null; then
    meta_json="{}"  # Fallback to empty object if invalid
  fi

  cat <<EOF
{
  "timestamp": "$timestamp",
  "severity": "$severity",
  "message": "$message",
  "trace_id": "$trace_id",
  "ip": "",
  "action": "${action:-}",
  "error_code": "${error_code:-}",
  "resource_type": "${resource_type:-}",
  "resource_id": "${resource_id:-}",
  "user_id": "${user_id:-}",
  "meta": ${meta_json:-{}}
}
EOF
}

# Convenience wrappers for common scenarios

# Log infrastructure warning (no business context)
# Usage: log_infra_warning <message> <action> <error_code> <resource_type> <resource_id>
log_infra_warning() {
  log_telemetry "WARN" "$1" "$2" "$3" "$4" "$5" ""
}

# Log infrastructure error (no business context)
# Usage: log_infra_error <message> <action> <error_code> <resource_type> <resource_id>
log_infra_error() {
  log_telemetry "ERROR" "$1" "$2" "$3" "$4" "$5" ""
}

# Log business failure (with business context)
# Usage: log_business_failure <message> <action> <error_code> <resource_type> <resource_id>
log_business_failure() {
  log_telemetry "ERROR" "$1" "$2" "$3" "$4" "$5" ""
}

# Log success (info level)
# Usage: log_success <message> <action> <resource_type> <resource_id>
log_success() {
  log_telemetry "INFO" "$1" "$2" "" "$3" "$4" ""
}
