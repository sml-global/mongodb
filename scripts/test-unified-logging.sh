#!/usr/bin/env bash
# Test unified logging schema — emits structured telemetry logs
# Verifies the 10 base fields are present in SigNoz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging-helpers.sh"

export SERVICE_NAME="audit-log-test"
export TRACE_ID="test-$(uuidgen | tr '[:upper:]' '[:lower:]')"

echo "=== Testing Unified Logging Schema ==="
echo "Service: $SERVICE_NAME"
echo "Trace ID: $TRACE_ID"
echo ""

# Test 1: Business failure (MongoDB write failed)
echo "Test 1: Business failure with full context"
log_telemetry "ERROR" "MongoDB write failed - connection timeout" \
  "boomi.document.load" "MONGO-CONN-0001" \
  "boomi.document" "TCHIBO-ORDER-001.csv" ""

echo ""

# Test 2: Infrastructure warning (config fallback)
echo "Test 2: Infrastructure warning"
log_infra_warning "Secret not found, using fallback credentials" \
  "config.fallback" "CONFIG-NOT-FOUND" \
  "config.secret" "mongodb/oms-audit-writer"

echo ""

# Test 3: Success event
echo "Test 3: Success event"
log_success "Document processed successfully" \
  "boomi.document.validated" \
  "boomi.document" "TCHIBO-ORDER-001.csv"

echo ""

# Test 4: Business failure with metadata
echo "Test 4: Business failure with metadata"
log_telemetry_with_meta "ERROR" "Order validation failed - missing required field" \
  "orders.order.validate" "ORDER-VAL-0003" \
  "orders.order" "ORD-2026-08-06-001" "" \
  '{"boomi_process_id":"EU-TC-0001","missing_field":"customer_id","retry_count":0}'

echo ""
echo "=== Test Complete ==="
echo "Search in SigNoz for trace_id=$TRACE_ID"
echo "Verify all 10 base fields present: trace_id, ip, time, action, error_code, resource_type, resource_id, user_id, message, meta"
