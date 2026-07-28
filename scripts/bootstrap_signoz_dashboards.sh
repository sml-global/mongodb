#!/usr/bin/env bash
set -euo pipefail

# File: scripts/bootstrap_signoz_dashboards.sh
# Purpose: Import SigNoz dashboards with idempotency guarantees
#
# This script:
# 1. Retrieves SigNoz admin credentials from Kubernetes Secret (signoz-root-user)
# 2. Authenticates to SigNoz API
# 3. Checks each dashboard for existence (by UUID/ID or title)
# 4. Imports new dashboards, skips existing ones (preserves SRE customizations)
# 5. Logs status for each dashboard
#
# Idempotency Guarantee:
# - First run: Imports all dashboards
# - Second run: Skips existing dashboards (check by UUID), restores missing ones
# - SRE customizations: NEVER overwritten
#
# Exit with error code 1 if authentication or import fails.

NAMESPACE="signoz"
DASHBOARDS_DIR="dashboards/signoz-import-pack"
SIGNOZ_API_URL="http://frontend.${NAMESPACE}.svc.cluster.local:3301/api/v1"

echo "=== SigNoz Dashboard Import ==="
echo ""

# Retrieve credentials from Kubernetes Secret
echo "Retrieving SigNoz credentials from Kubernetes Secret..."
if ! kubectl get secret signoz-root-user -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "❌ Kubernetes Secret 'signoz-root-user' not found in namespace '$NAMESPACE'"
  echo "   Please create it first: bash scripts/create-signoz-root-user-secret.sh"
  exit 1
fi

SIGNOZ_ADMIN_EMAIL=$(kubectl get secret signoz-root-user -n "$NAMESPACE" \
  -o jsonpath='{.data.admin_email}' 2>/dev/null | base64 -d || echo "admin@oms.local")
SIGNOZ_ADMIN_PASSWORD=$(kubectl get secret signoz-root-user -n "$NAMESPACE" \
  -o jsonpath='{.data.admin_password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$SIGNOZ_ADMIN_PASSWORD" ]; then
  echo "❌ Could not retrieve password from Secret. Secret may be incomplete."
  exit 1
fi

echo "✅ Credentials retrieved (admin email: $SIGNOZ_ADMIN_EMAIL)"
echo ""

# Authenticate to SigNoz API
echo "Authenticating to SigNoz API..."
login_response=$(curl -s -X POST "$SIGNOZ_API_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$SIGNOZ_ADMIN_EMAIL\", \"password\": \"$SIGNOZ_ADMIN_PASSWORD\"}" 2>/dev/null || echo "{}")

session_token=$(echo "$login_response" | jq -r '.sessionId // .access_token // ""' 2>/dev/null || echo "")

if [ -z "$session_token" ]; then
  echo "❌ Failed to authenticate to SigNoz API"
  echo "   Response: $login_response"
  exit 1
fi

echo "✅ Authenticated to SigNoz API"
echo ""

# Import dashboards
echo "Processing dashboards..."
dashboards_imported=0
dashboards_skipped=0

if [ ! -d "$DASHBOARDS_DIR" ]; then
  echo "❌ Dashboards directory not found: $DASHBOARDS_DIR"
  exit 1
fi

for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
  if [ ! -f "$dashboard_file" ]; then
    continue
  fi

  dashboard_name=$(basename "$dashboard_file" .json)
  
  echo ""
  echo "Processing: $dashboard_name"
  
  # Extract UUID, ID, or title from JSON
  dashboard_uuid=$(jq -r '.uuid // .id // ""' "$dashboard_file" 2>/dev/null || echo "")
  dashboard_title=$(jq -r '.title // ""' "$dashboard_file" 2>/dev/null || echo "$dashboard_name")
  
  if [ -z "$dashboard_uuid" ]; then
    echo "  → No UUID/ID in JSON. Generating safe identifier..."
    # Use jq to add a UUID if missing (for future consistency)
    dashboard_uuid=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "generated-$(date +%s)")
  fi
  
  # Check if dashboard already exists by UUID or title
  echo "  → Checking if dashboard exists..."
  existing_dashboard=$(curl -s -X GET "$SIGNOZ_API_URL/dashboards" \
    -H "Authorization: Bearer $session_token" 2>/dev/null | \
    jq -r ".dashboards[] | select(.uuid == \"$dashboard_uuid\" or .title == \"$dashboard_title\") | .uuid" 2>/dev/null || echo "")
  
  if [ ! -z "$existing_dashboard" ]; then
    echo "  ⏭️  Skipping: Dashboard already exists (UUID: $existing_dashboard)"
    echo "     To update, manually delete in SigNoz UI or re-import with new UUID"
    ((dashboards_skipped++)) || true
    continue
  fi
  
  # Import dashboard
  echo "  → Importing dashboard..."
  import_response=$(curl -s -X POST "$SIGNOZ_API_URL/dashboards" \
    -H "Authorization: Bearer $session_token" \
    -H "Content-Type: application/json" \
    -d @"$dashboard_file" 2>/dev/null || echo "{}")
  
  import_id=$(echo "$import_response" | jq -r '.data.id // .id // ""' 2>/dev/null || echo "")
  import_error=$(echo "$import_response" | jq -r '.error // .message // ""' 2>/dev/null || echo "")
  
  if [ ! -z "$import_error" ] && [ "$import_error" != "null" ]; then
    echo "  ❌ Import failed: $import_error"
    echo "     Response: $import_response"
    exit 1
  fi
  
  if [ ! -z "$import_id" ]; then
    echo "  ✅ Imported: Dashboard created (ID: $import_id)"
    ((dashboards_imported++)) || true
  else
    echo "  ⚠️  Import response unclear. Response: $import_response"
  fi
done

echo ""
echo "=== Summary ==="
echo "  ✅ Imported: $dashboards_imported dashboard(s)"
echo "  ⏭️  Skipped: $dashboards_skipped dashboard(s) (existing, customizations preserved)"
echo ""
echo "✅ SigNoz dashboard import complete"
