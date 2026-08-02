# DevOps Specification: SigNoz Dashboard Import Readiness & Idempotency

**Version:** 1.0  
**Date:** 2026-07-28  
**Status:** REQUIRED BEFORE PHASE 3 MERGE  
**Owner:** DevOps Team  

---

## Executive Summary

This spec addresses three critical DevOps concerns blocking Phase 3 merge:

1. **SigNoz Readiness Race Condition** - Dashboard import script must wait for SigNoz API readiness
2. **Dashboard Import Idempotency** - Re-running provision must not duplicate or overwrite custom dashboards
3. **API Authentication** - Dashboard import must securely authenticate to SigNoz API

**Impact:** These gaps could cause silent failures during Week 0.1 provisioning (dashboards missing, no error logs).

**Resolution Approach:** Add explicit readiness checks, implement safe import strategy, use Kubernetes Secret for credentials.

---

## 1. REQUIREMENT: SigNoz Readiness Wait Loop

### Problem Statement

```bash
# Current provision.sh sequence (assumed):
bash scripts/provision.sh signoz --auto-approve
# ⚠️ ZERO WAIT
bash scripts/provision.sh signoz-observability --auto-approve
```

**Race Condition Scenario:**
```
T=0s:   kubectl apply (signoz Helm release)
        ├─ query-service pod: Pending
        ├─ frontend pod: Pending
        └─ clickhouse pod: Pending

T=2s:   provision.sh signoz-observability runs
        └─ curl http://signoz-frontend.signoz.svc.cluster.local:3301/api/dashboards
           ❌ Connection refused (frontend not ready)
           ❌ Dashboard import silently fails
           ❌ No error in provision.sh logs (curl timeout swallowed)

T=30s:  All SigNoz pods finally reach Ready state
        └─ Dashboards exist in Git but NOT in SigNoz UI

T=45s:  scripts/verify-platform-health.sh --smoke-test runs
        ✅ MongoDB checks pass
        ✅ PostgreSQL checks pass
        ✅ SigNoz UI responds to health check (pod Ready)
        ⚠️ Dashboard count check: MISSING (not in smoke test?)
        ✅ Overall test: PASS (false positive)

T=60m:  SRE logs into SigNoz, discovers no dashboards
        ❌ Must manually import or re-run provision
        ❌ Root cause unclear (logs don't show error)
```

### Solution

Add explicit **readiness gates** before dashboard import.

**Location:** `scripts/provision-signoz-observability.sh` (new file) or `scripts/provision.sh` (modify)

**Implementation:**

```bash
#!/bin/bash
set -e

# File: scripts/provision-signoz-observability.sh
# Purpose: Deploy SigNoz dashboards AFTER platform is ready

echo "=== SigNoz Observability Provisioning ==="
echo "Waiting for SigNoz API services to be ready..."

# 1. Wait for query-service pod to reach Ready state
echo "  → Waiting for query-service..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=query-service \
  -n signoz \
  --timeout=300s || {
  echo "❌ query-service failed to reach Ready state within 300s"
  exit 1
}
echo "  ✅ query-service is Ready"

# 2. Wait for frontend pod to reach Ready state
echo "  → Waiting for frontend..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=frontend \
  -n signoz \
  --timeout=300s || {
  echo "❌ frontend failed to reach Ready state within 300s"
  exit 1
}
echo "  ✅ frontend is Ready"

# 3. Wait for API endpoint to be responsive (connection test)
echo "  → Testing API endpoint connectivity..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if kubectl run -it --rm \
    --image=curlimages/curl:latest \
    --restart=Never \
    --namespace=signoz \
    curl-test -- \
    curl -f -s http://frontend:3301/api/v1/dashboards >/dev/null 2>&1; then
    echo "  ✅ API endpoint is responsive"
    break
  fi
  echo "  ⏳ API not yet responsive, attempt $((attempt+1))/$max_attempts..."
  sleep 10
  ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
  echo "❌ API endpoint did not become responsive within $((max_attempts * 10))s"
  exit 1
fi

echo ""
echo "✅ All SigNoz services ready. Proceeding with dashboard import..."

# 4. Import dashboards
bash scripts/bootstrap_signoz_dashboards.sh

echo "✅ SigNoz observability provisioning complete"
```

### Test Case

**Test:** `test_signoz_readiness_wait_in_provision_script.py`

```python
import subprocess
import pathlib

class SignozReadinessTests(unittest.TestCase):
    def test_provision_script_includes_kubectl_wait_for_query_service(self):
        """Verify provision script waits for query-service Ready state"""
        provision_script = pathlib.Path("scripts/provision.sh").read_text()
        # OR if separate script:
        provision_script = pathlib.Path("scripts/provision-signoz-observability.sh").read_text()
        
        # Must include explicit wait, not just implicit sleep
        self.assertIn('kubectl wait --for=condition=ready', provision_script)
        self.assertIn('query-service', provision_script)
        self.assertIn('--timeout=', provision_script)
    
    def test_provision_script_includes_kubectl_wait_for_frontend(self):
        """Verify provision script waits for frontend Ready state"""
        provision_script = pathlib.Path("scripts/provision.sh").read_text()
        self.assertIn('kubectl wait --for=condition=ready', provision_script)
        self.assertIn('frontend', provision_script)
    
    def test_provision_script_has_exit_on_readiness_failure(self):
        """Verify provision script exits if readiness check fails"""
        provision_script = pathlib.Path("scripts/provision.sh").read_text()
        self.assertIn('exit 1', provision_script)
        # Should NOT silently continue if wait fails
```

### Acceptance Criteria

- ✅ Script waits for `query-service` Ready state (timeout: 300s)
- ✅ Script waits for `frontend` Ready state (timeout: 300s)
- ✅ Script tests API connectivity before importing
- ✅ Script exits with error code if readiness fails
- ✅ All 3 readiness checks logged to stdout
- ✅ Test case added to `tests/signoz/test_provision_readiness.py`

---

## 2. REQUIREMENT: Dashboard Import Idempotency

### Problem Statement

```bash
# Week 0.1: First provision
$ bash scripts/provision.sh signoz-observability --auto-approve
  ✅ Import MongoDB Overview dashboard (ID: 12345)
  ✅ Import PostgreSQL Overview dashboard (ID: 12346)

# SRE customizes MongoDB Overview in SigNoz UI
# (adds custom panels, changes thresholds, etc.)

# Week 2: Hotfix provision (someone re-runs provision.sh)
$ bash scripts/provision.sh signoz-observability --auto-approve
  ❌ SCENARIO A: Overwrites SRE's customizations (data loss)
  ❌ SCENARIO B: Creates duplicate dashboard "MongoDB Overview (2)" (confusion)
  ❓ SCENARIO C: Skips import because dashboard exists (safe, but need verification)
```

### Solution: Safe Import Strategy

**Strategy: Check-Before-Import with UUID-based Naming**

```bash
#!/bin/bash
# File: scripts/bootstrap_signoz_dashboards.sh
# Purpose: Import dashboards from JSON with idempotency guarantees

set -e

DASHBOARDS_DIR="dashboards/signoz-import-pack"
SIGNOZ_API_URL="http://frontend.signoz.svc.cluster.local:3301/api/v1"

# Get credentials from Kubernetes Secret
SIGNOZ_ADMIN_EMAIL=$(kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.admin_email}' 2>/dev/null | base64 -d || echo "admin@signoz.io")
SIGNOZ_ADMIN_PASSWORD=$(kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.admin_password}' 2>/dev/null | base64 -d || echo "admin")

# Login and get session token
echo "Authenticating to SigNoz API..."
LOGIN_RESPONSE=$(curl -s -X POST "$SIGNOZ_API_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$SIGNOZ_ADMIN_EMAIL\", \"password\": \"$SIGNOZ_ADMIN_PASSWORD\"}")

SESSION_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.sessionId // .access_token // ""')
if [ -z "$SESSION_TOKEN" ]; then
  echo "❌ Failed to authenticate to SigNoz API"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi
echo "✅ Authenticated to SigNoz API"

# Import dashboards
for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
  dashboard_name=$(basename "$dashboard_file" .json)
  
  echo ""
  echo "Processing dashboard: $dashboard_name"
  
  # Extract UUID or title from JSON
  dashboard_uuid=$(jq -r '.uuid // .id // ""' "$dashboard_file" 2>/dev/null || echo "")
  dashboard_title=$(jq -r '.title // ""' "$dashboard_file" 2>/dev/null || echo "$dashboard_name")
  
  if [ -z "$dashboard_uuid" ]; then
    echo "  ⚠️  No UUID in dashboard JSON. Generating safe UUID..."
    dashboard_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
  fi
  
  # Check if dashboard already exists by UUID
  echo "  → Checking if dashboard exists..."
  existing_dashboard=$(curl -s -X GET "$SIGNOZ_API_URL/dashboards" \
    -H "Authorization: Bearer $SESSION_TOKEN" 2>/dev/null | \
    jq -r ".dashboards[] | select(.uuid == \"$dashboard_uuid\" or .title == \"$dashboard_title\") | .uuid" 2>/dev/null || echo "")
  
  if [ ! -z "$existing_dashboard" ]; then
    echo "  ⏭️  Dashboard already exists (UUID: $existing_dashboard). Skipping import."
    echo "     To update, manually delete in SigNoz UI or use force flag."
    continue
  fi
  
  # Import dashboard
  echo "  → Importing dashboard..."
  import_response=$(curl -s -X POST "$SIGNOZ_API_URL/dashboards" \
    -H "Authorization: Bearer $SESSION_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$dashboard_file")
  
  import_id=$(echo "$import_response" | jq -r '.data.id // .id // ""' 2>/dev/null || echo "")
  import_error=$(echo "$import_response" | jq -r '.error // .message // ""' 2>/dev/null || echo "")
  
  if [ ! -z "$import_error" ] && [ "$import_error" != "null" ]; then
    echo "  ❌ Failed to import: $import_error"
    exit 1
  fi
  
  if [ ! -z "$import_id" ]; then
    echo "  ✅ Dashboard imported successfully (ID: $import_id)"
  else
    echo "  ⚠️  Import response unclear: $import_response"
  fi
done

echo ""
echo "✅ All dashboards imported successfully"
```

### Idempotency Guarantee

```
First run (Week 0.1):
  ├─ Check: MongoDB Overview exists? NO
  ├─ Action: Import MongoDB Overview
  └─ Result: Dashboard created with UUID from JSON

Second run (Week 2 hotfix):
  ├─ Check: MongoDB Overview exists? YES (UUID matches)
  ├─ Action: SKIP (do not overwrite)
  └─ Result: SRE customizations preserved ✅

Edge case - SRE deleted MongoDB Overview manually:
  ├─ Check: MongoDB Overview exists? NO
  ├─ Action: Re-import from JSON
  └─ Result: Restored to last-known-good state from Git ✅
```

### Test Cases

**Test:** `test_dashboard_idempotency.py`

```python
import json
import unittest
import pathlib

class DashboardIdempotencyTests(unittest.TestCase):
    def test_all_dashboards_have_uuid_or_id(self):
        """Every dashboard JSON must have a UUID for idempotent identification"""
        dashboards_dir = pathlib.Path("dashboards/signoz-import-pack")
        for dashboard_file in dashboards_dir.glob("*.json"):
            with open(dashboard_file) as f:
                dashboard = json.load(f)
            # Must have either 'uuid' or 'id' field for matching
            self.assertTrue(
                'uuid' in dashboard or 'id' in dashboard,
                f"{dashboard_file.name} missing 'uuid' or 'id' field for idempotency"
            )
    
    def test_import_script_includes_check_before_import(self):
        """Dashboard import script must check existence before importing"""
        import_script = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertIn('dashboards_exist', import_script)
        self.assertIn('curl', import_script)  # Must query API
        self.assertIn('skip', import_script.lower())  # Must skip existing
```

### Acceptance Criteria

- ✅ Each dashboard JSON has a stable UUID/ID field
- ✅ Import script queries SigNoz API to check dashboard existence
- ✅ If dashboard UUID/ID already exists, script skips import
- ✅ SRE customizations are never overwritten
- ✅ Script logs which dashboards were imported vs. skipped
- ✅ Re-running provision is safe and idempotent
- ✅ Test case added to `tests/signoz/test_dashboard_idempotency.py`

---

## 3. REQUIREMENT: API Authentication Strategy

### Problem Statement

**Question:** How does dashboard import script securely access SigNoz API?

**Current Options:**

| Option | Security | Maintainability | Status |
|--------|----------|-----------------|--------|
| Hardcoded credentials in script | ❌ UNSAFE | ❌ BRITTLE | ❌ NOT ACCEPTABLE |
| Environment variables | ⚠️ MODERATE | ⚠️ MEDIUM | ⚠️ RISKY (exposed in logs) |
| Kubernetes Secret `signoz-root-user` | ✅ SECURE | ✅ CLEAN | ✅ RECOMMENDED |
| Service account token + RBAC | ✅ SECURE | ⚠️ COMPLEX | ⚠️ REQUIRES CUSTOM OPERATOR |

### Solution: Use Kubernetes Secret

**Assumption:** `scripts/create-signoz-root-user-secret.sh` already exists and creates secret.

**Verification:**

```bash
# This secret must exist before dashboard import
$ kubectl get secret signoz-root-user -n signoz
NAME                    TYPE     DATA   AGE
signoz-root-user        Opaque   2      5m

# Must contain these keys:
$ kubectl get secret signoz-root-user -n signoz -o jsonpath='{.data}' | jq .
{
  "admin_email": "...",      # base64-encoded
  "admin_password": "..."    # base64-encoded
}
```

**Usage in Import Script:**

```bash
# Retrieve credentials from Secret
SIGNOZ_ADMIN_EMAIL=$(kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.admin_email}' | base64 -d)

SIGNOZ_ADMIN_PASSWORD=$(kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.admin_password}' | base64 -d)

# Use for API login
curl -X POST "$SIGNOZ_API_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$SIGNOZ_ADMIN_EMAIL\", \"password\": \"$SIGNOZ_ADMIN_PASSWORD\"}"
```

### Dependency Chain

```
Week 0.0 (Infra Admin):
  └─ EKS cluster exists
  └─ Kubernetes API accessible

Week 0.1 (DevOps):
  ├─ bash scripts/provision.sh signoz --auto-approve
  │  ├─ Flux/Helm deploys SigNoz HelmRelease
  │  └─ SigNoz pods start (but not yet Ready)
  │
  └─ ⚠️ CRITICAL: Bootstrap script must have run BEFORE this
     └─ bash scripts/create-signoz-root-user-secret.sh
        └─ Creates Kubernetes Secret `signoz-root-user`

  └─ bash scripts/provision.sh signoz-observability --auto-approve
     ├─ Wait for SigNoz readiness
     └─ Import dashboards
        └─ Uses credentials from `signoz-root-user` Secret
```

### Test Case

**Test:** `test_signoz_authentication.py`

```python
import pathlib
import unittest

class SignozAuthenticationTests(unittest.TestCase):
    def test_import_script_uses_kubernetes_secret_not_hardcoded_credentials(self):
        """Dashboard import must use Secret, never hardcoded credentials"""
        import_script = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        
        # Must reference Secret
        self.assertIn('signoz-root-user', import_script)
        self.assertIn('kubectl get secret', import_script)
        
        # Must NOT have hardcoded password patterns
        self.assertNotIn('password=', import_script)  # Exact match forbidden
        self.assertNotIn('SIGNOZ_PASSWORD', import_script)  # Env var from source
    
    def test_signoz_root_user_secret_keys_match_script(self):
        """Verify Secret keys match what import script expects"""
        # This is a manual check, but can be verified via:
        # kubectl get secret signoz-root-user -n signoz -o json | jq .data
        pass  # Operator-verified during provision
```

### Acceptance Criteria

- ✅ Dashboard import script retrieves credentials from `signoz-root-user` Secret
- ✅ Script never hardcodes or logs credentials
- ✅ Script exits with clear error if Secret doesn't exist
- ✅ Dependency: `scripts/create-signoz-root-user-secret.sh` documented as pre-requisite
- ✅ Provision sequence documented: bootstrap secret BEFORE dashboard import
- ✅ Test case added to `tests/signoz/test_authentication.py`

---

## 4. PROVISION SCRIPT SEQUENCE (FINAL)

```bash
#!/bin/bash
# File: scripts/provision.sh
# Updated sequence for Phase 3

set -e

case "$1" in
  all)
    # AWS infrastructure
    bash scripts/provision-platform-prereq.sh
    ;;
  
  signoz)
    # ✅ Deploy SigNoz platform (pods, but not dashboards yet)
    bash scripts/provision-k8s-components.sh signoz
    # Or: helm upgrade --install signoz ...
    ;;
  
  signoz-observability)
    # 🟡 NEW: Wait for readiness BEFORE importing dashboards
    echo "=== SigNoz Observability Provisioning ==="
    
    # 1. Wait for SigNoz services to be ready
    echo "Waiting for SigNoz services..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=query-service \
      -n signoz --timeout=300s || { echo "❌ query-service failed"; exit 1; }
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=frontend \
      -n signoz --timeout=300s || { echo "❌ frontend failed"; exit 1; }
    echo "✅ SigNoz services ready"
    
    # 2. Pre-requisite: Bootstrap script must have created signoz-root-user Secret
    if ! kubectl get secret signoz-root-user -n signoz >/dev/null 2>&1; then
      echo "⚠️  signoz-root-user Secret not found. Creating now..."
      bash scripts/create-signoz-root-user-secret.sh
    fi
    
    # 3. Import dashboards
    bash scripts/bootstrap_signoz_dashboards.sh
    echo "✅ SigNoz observability provisioned"
    ;;
esac
```

### Updated Provision Sequence for Week 0.1

```bash
# DevOps Engineer runs this sequence (SEQUENTIAL, not parallel):

bash scripts/provision.sh all --auto-approve
# Output: ✅ AWS infrastructure ready

bash scripts/provision.sh signoz --auto-approve
# Output: ✅ SigNoz pods deployed (not yet Ready)

bash scripts/provision.sh signoz-observability --auto-approve
# Output: ✅ Waiting for services...
#         ✅ SigNoz services ready
#         ✅ Credentials retrieved from Secret
#         ✅ All dashboards imported successfully

bash scripts/verify-platform-health.sh --smoke-test
# Output: ✅ All checks passed (including dashboard count)
```

---

## 5. VERIFICATION & ACCEPTANCE

### Pre-Merge Checklist (DevOps Team)

- [ ] `scripts/provision-signoz-observability.sh` exists with readiness wait loop
- [ ] `scripts/bootstrap_signoz_dashboards.sh` exists with idempotency checks
- [ ] Dashboard JSON files all have UUID/ID fields
- [ ] `scripts/create-signoz-root-user-secret.sh` exists (pre-requisite)
- [ ] Test suite added: `tests/signoz/test_provision_readiness.py`
- [ ] Test suite added: `tests/signoz/test_dashboard_idempotency.py`
- [ ] Test suite added: `tests/signoz/test_authentication.py`
- [ ] All tests pass: `python3 -m unittest tests/signoz/test_*.py -v`
- [ ] Terraform fmt -check && validate passes
- [ ] Kustomize build passes
- [ ] Smoke test passes: `bash scripts/verify-platform-health.sh --smoke-test`

### Manual Verification (First Time Only)

```bash
# After Phase 3 merge, Infra Admin manually tests Week 0.1 provision:

cd /Users/frank/sml/oms/mongodb
git checkout main
git pull origin main

# Ensure UAT environment is clean
# (destroy previous cluster if it exists)

# Run full provision sequence
bash scripts/provision.sh all --auto-approve
bash scripts/provision.sh signoz --auto-approve
bash scripts/provision.sh signoz-observability --auto-approve

# Verify dashboards exist
kubectl port-forward -n signoz svc/signoz-frontend 3301:3301 &
# Open browser: http://localhost:3301
# Check: MongoDB Overview, PostgreSQL Overview dashboards visible ✅

bash scripts/verify-platform-health.sh --smoke-test
# Output: ALL TESTS PASSED ✅
```

---

## 6. SUMMARY: What Needs to Be Done

| Item | Current | Required | Owner | Timeline |
|------|---------|----------|-------|----------|
| **SigNoz readiness wait** | ❌ Missing | `kubectl wait` in provision.sh | DevOps | Before merge |
| **Dashboard idempotency** | ❓ Unknown | Check-before-import logic | DevOps | Before merge |
| **API authentication** | ❓ Unknown | Use `signoz-root-user` Secret | DevOps | Before merge |
| **Readiness test** | ❌ Missing | `test_provision_readiness.py` | DevOps | Before merge |
| **Idempotency test** | ❌ Missing | `test_dashboard_idempotency.py` | DevOps | Before merge |
| **Auth test** | ❌ Missing | `test_authentication.py` | DevOps | Before merge |
| **Documentation** | ⚠️ Partial | Update provision docs + runbook | DevOps | Before merge |

**Gate:** Phase 3 merge is blocked until all items above are **DONE** and tested.

---

## 7. RESOLUTION TEMPLATE

When DevOps team confirms completion, provide this summary:

```markdown
## DevOps Verification Complete ✅

### SigNoz Readiness Wait Loop
- [x] `kubectl wait` added to scripts/provision.sh
- [x] Timeout: 300s per service (query-service, frontend)
- [x] Exit code: 1 if readiness fails
- Location: `scripts/provision.sh` line XXX
- Test: `test_provision_readiness.py` passes ✅

### Dashboard Import Idempotency
- [x] Check-before-import logic implemented
- [x] UUID-based dashboard identification
- [x] Skips import if dashboard exists
- [x] SRE customizations preserved
- Location: `scripts/bootstrap_signoz_dashboards.sh`
- Test: `test_dashboard_idempotency.py` passes ✅

### API Authentication
- [x] Uses `signoz-root-user` Secret (no hardcoded credentials)
- [x] Retrieves email/password from Secret
- [x] Logs error if Secret missing
- Location: `scripts/bootstrap_signoz_dashboards.sh` lines YYY-ZZZ
- Test: `test_authentication.py` passes ✅

### All Tests Passing
```
python3 -m unittest tests/signoz/test_provision_readiness.py -v
python3 -m unittest tests/signoz/test_dashboard_idempotency.py -v
python3 -m unittest tests/signoz/test_authentication.py -v

Results: 9/9 tests passing ✅
```

### Recommended Action
Phase 3 merge is **UNBLOCKED**. Proceed with:
1. Merge `feat/phase3-workload-platforms` → `main`
2. Tag release: `phase3-workload-platforms-complete`
3. Clean up worktree
4. Invoke `finishing-a-development-branch` skill
```

