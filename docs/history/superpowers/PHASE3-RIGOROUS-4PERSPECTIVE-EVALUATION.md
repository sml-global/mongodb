# Phase 3 Rigorous 4-Perspective Expert Evaluation

**Date:** 2026-07-28  
**Status:** PRE-MERGE GATE (Critical Issues Identified)  
**Severity:** 🔴 BLOCKING - Implementation Gap Detected  

---

## ⚠️ CRITICAL FINDING: IMPLEMENTATION GAP

**Issue:** Task 8 specification was written (devops-signoz-dashboard-import-spec.md) but **implementation was NOT completed**.

**Evidence:**
- ✅ `docs/history/superpowers/devops-signoz-dashboard-import-spec.md` exists (3,700+ lines)
- ✅ `scripts/provision-signoz-observability.sh` exists (Terraform-based, ~100 lines)
- ❌ `scripts/bootstrap_signoz_dashboards.sh` does NOT exist (bash implementation missing)
- ❌ `tests/signoz/test_provision_readiness.py` does NOT exist
- ❌ `tests/signoz/test_dashboard_idempotency.py` does NOT exist
- ❌ `tests/signoz/test_authentication.py` does NOT exist

**Impact:** Merge cannot proceed with incomplete deliverables.

**Path Forward:** Complete Task 8 implementation before merge (see Section 6 below).

---

## 1. AWS Architect Perspective

### Status: 🟡 YELLOW (Conditional CLEAR - Awaiting Implementation Verification)

### Assessment

#### A. Cloud/Workload Boundary ✅
- ✅ No new AWS dependencies in spec
- ✅ MongoDB/PostgreSQL backups use existing IRSA roles (Phase 2)
- ✅ KMS/S3 references only in database operators
- ✅ SigNoz remains 100% Kubernetes-native
- ✅ Dashboard API uses Kubernetes Secrets (not AWS Secrets Manager)

**Conclusion:** Boundary is mathematically sound.

#### B. Credential Management 🟡
**Question:** The spec mentions retrieving credentials from `signoz-root-user` Secret using `kubectl get secret` and base64 decode. But the actual implementation doesn't exist yet.

**Risk if not verified:**
- Implementation could accidentally reference AWS Secrets Manager
- Implementation could hardcode region/endpoint in credential retrieval
- Implementation could make unnecessary AWS SDK calls

**Required Before Merge:**
- [ ] Verify implementation uses ONLY `kubectl get secret` (no AWS API calls)
- [ ] Verify base64 decode is done with standard Unix tools (not boto3)
- [ ] Audit implementation for any AWS SDK imports

#### C. Multi-Environment Support 🟡
**Question:** Phase 3 spec assumes single namespace (`signoz`). What about future multi-tenant scenarios?

**Risk if not addressed:**
- Dashboard import hardcodes `--namespace=signoz`
- Recovery procedure assumes single namespace
- Scaling to multiple environments later requires refactor

**Current Status:** Out of scope for Phase 3, but implementation should be designed to NOT block future extension.

**Required Before Merge:**
- [ ] Verify implementation uses variable for namespace (not hardcoded)
- [ ] Document namespace assumption in README/comments
- [ ] Plan for multi-namespace support in Phase 4 (if needed)

---

## 2. DevOps Perspective

### Status: 🔴 RED (BLOCKING - Implementation Missing)

### Critical Issues

#### Issue 1: Readiness Gates Not Implemented ❌

**Spec Promise:**
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=query-service -n signoz --timeout=300s || exit 1
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=frontend -n signoz --timeout=300s || exit 1
```

**Actual State:**
- File `scripts/bootstrap_signoz_dashboards.sh` does NOT exist
- Readiness gates cannot be verified until implementation exists

**Risk:**
- Dashboard import runs before SigNoz API is ready
- Silent failures (curl timeout, no error log)
- Dashboard missing from UI, no root cause in logs

**Required Before Merge:**
- [ ] Create `scripts/bootstrap_signoz_dashboards.sh` with explicit `kubectl wait` blocks
- [ ] Exit with code 1 if readiness checks fail
- [ ] Add progress logging (echo statements for each stage)
- [ ] Test with simulated delay (pod takes 60+ seconds to reach Ready)

---

#### Issue 2: Idempotency Not Implemented ❌

**Spec Promise:**
```bash
# For each dashboard JSON:
#   - Extract UUID/ID from file
#   - Query SigNoz API: does dashboard with UUID/ID exist?
#   - If YES: skip (SRE customizations preserved)
#   - If NO: POST dashboard JSON to API
```

**Actual State:**
- Implementation file does NOT exist
- No mechanism to query SigNoz API before POST
- Re-running provision could duplicate dashboards

**Risk:**
- Hotfix provisioning in Week 2+ creates duplicate dashboards
- SRE customizations lost on re-import
- No clear recovery procedure

**Required Before Merge:**
- [ ] Implement check-before-import logic in bootstrap script
- [ ] Query SigNoz `/api/v1/dashboards` endpoint before each POST
- [ ] Match by UUID/ID field (not just title)
- [ ] Log which dashboards were skipped vs. imported
- [ ] Document recovery procedure (what to do if dashboard accidentally deleted)

---

#### Issue 3: Error Handling Not Tested ❌

**Spec Promise:**
```
Exit 1 if:
  - kubectl wait times out
  - API connectivity fails
  - Dashboard import fails
  - Secret retrieval fails
```

**Actual State:**
- Test files do NOT exist (`test_provision_readiness.py`, `test_authentication.py`)
- No verification that scripts actually exit with code 1 on failure
- Unknown if error messages are clear

**Risk:**
- Scripts could fail silently (exit 0 on error)
- Operator unaware that dashboards failed to import
- root cause unclear (logs missing)

**Required Before Merge:**
- [ ] Create `tests/signoz/test_provision_readiness.py` (3+ test cases)
  - Verify `kubectl wait` present in script
  - Verify exit 1 on readiness timeout
  - Verify curl connectivity test present
- [ ] Create `tests/signoz/test_authentication.py` (2+ test cases)
  - Verify `kubectl get secret` used (not hardcoded password)
  - Verify exit 1 if Secret missing
  - Verify no AWS SDK imports
- [ ] Create `tests/signoz/test_dashboard_idempotency.py` (3+ test cases)
  - Verify all dashboard JSONs have uuid OR id field
  - Verify check-before-import logic present
  - Verify no `--force` or `--overwrite` flags that would delete customizations

---

#### Issue 4: Dependency Chain Not Documented ❌

**Spec Promise:**
- `provision.sh signoz` must complete before `provision.sh signoz-observability`
- `signoz-root-user` Secret must exist before bootstrap script runs

**Actual State:**
- `provision.sh` is the main orchestrator (main script)
- Does it validate dependency order? Unknown until implementation reviewed.

**Risk:**
- Operator runs steps out of order
- Bootstrap script fails with confusing error (Secret missing)
- No clear error message about dependency order

**Required Before Merge:**
- [ ] Verify `provision.sh` enforces dependency order (signoz → signoz-observability)
- [ ] Add explicit comments in `provision-signoz-observability.sh` documenting prerequisites
- [ ] Add validation at script start: check that `signoz-root-user` Secret exists
- [ ] If validation fails, exit with clear error message (not generic kubectl error)

---

#### Issue 5: SigNoz API Documentation ❌

**Spec Promise:**
- Dashboard import uses SigNoz API endpoints
- Authentication requires email/password from Secret

**Actual State:**
- Which API endpoints are used? Unknown until implementation exists.
- Are they documented? Probably not.
- What if SigNoz version changes and API breaks? No version guard.

**Risk:**
- Maintenance burden unclear
- API breakage in SigNoz v0.131 could silently break import

**Required Before Merge:**
- [ ] Document exact SigNoz API endpoints used (e.g., `/api/v1/dashboards`, `/api/v1/login`)
- [ ] Document SigNoz version assumption (currently v0.130.1 from Phase 3 spec)
- [ ] Add version check or compatibility comment in script
- [ ] Add comment with SigNoz API reference link

---

### DevOps Pre-Merge Checklist

**All items below are BLOCKING (must complete before merge):**

1. **Implement readiness gates**
   - [ ] Create `scripts/bootstrap_signoz_dashboards.sh`
   - [ ] Add `kubectl wait` for query-service (300s timeout)
   - [ ] Add `kubectl wait` for frontend (300s timeout)
   - [ ] Add curl connectivity test (poll API until responsive)
   - [ ] Exit 1 if any check fails

2. **Implement idempotency**
   - [ ] Query SigNoz API before each dashboard POST
   - [ ] Skip if dashboard exists (by UUID/ID)
   - [ ] Log which dashboards were imported vs. skipped
   - [ ] Verify idempotency with test: run twice, second run should import 0 dashboards

3. **Implement error handling**
   - [ ] Create test suite `tests/signoz/test_provision_readiness.py` (3+ tests)
   - [ ] Create test suite `tests/signoz/test_authentication.py` (2+ tests)
   - [ ] Create test suite `tests/signoz/test_dashboard_idempotency.py` (3+ tests)
   - [ ] All tests pass (exit code 0)

4. **Document dependencies**
   - [ ] Add comments to scripts explaining prerequisite order
   - [ ] Add validation in bootstrap script to check for `signoz-root-user` Secret
   - [ ] Add clear error message if dependency missing

5. **Verify Git command syntax**
   - [ ] Use `git merge feat/phase3-workload-platforms` (not directory path)
   - [ ] Update pre-merge verification checklist with corrected command

---

## 3. Software Architect Perspective

### Status: 🟡 YELLOW (Conditional CLEAR - Architecture Sound, Implementation Missing)

### Assessment

#### A. System Design Cohesion ✅
- ✅ Dashboard provisioning integrates cleanly with platform architecture
- ✅ Idempotency pattern matches other components (e.g., MongoDB backup logic)
- ✅ Separation of concerns: `provision-signoz-observability.sh` (Terraform) vs. `bootstrap_signoz_dashboards.sh` (dashboard import)
- ✅ No architectural debt introduced

**Conclusion:** Architecture is sound.

#### B. Dashboard UUID/ID Enforcement 🟡

**Spec Promise:** All dashboard JSON files must have `uuid` OR `id` field for idempotency matching.

**Current State:** Unknown if all dashboards actually have these fields.

**Risk if not verified:**
- Some dashboards match by title (fragile, not unique)
- Renaming dashboard in UI creates duplicate on re-import
- No way to guarantee idempotency

**Required Before Merge:**
- [ ] Audit all `.json` files in `dashboards/signoz-import-pack/`
- [ ] Verify EVERY file has `uuid` OR `id` field
- [ ] Add test: `test_all_dashboards_have_uuid_or_id()` that runs `jq` on all files
- [ ] Document UUID/ID requirement in dashboard contributor guidelines (if not already)

**Command to verify:**
```bash
for f in dashboards/signoz-import-pack/*.json; do
  if ! jq -e 'has("uuid") or has("id")' "$f" > /dev/null; then
    echo "MISSING UUID/ID: $f"
  fi
done
# Expected output: (nothing — all files pass)
```

---

#### C. Contract Enforcement ✅
- ✅ Platform contracts (MongoDB, PostgreSQL, SigNoz) already finalized in Task 7
- ✅ Dashboard provisioning fits within SigNoz contract (part of lifecycle bootstrap)
- ✅ No contract violations detected

**Conclusion:** Contract boundaries respected.

#### D. Documentation Accuracy 🟡

**Spec Promise:** Task 8 documented in `docs/history/superpowers/devops-signoz-dashboard-import-spec.md`

**Current State:** Specification document exists (3,700+ lines), but implementation doesn't match.

**Risk if not addressed:**
- Developers read spec, assume implementation exists
- Implementation differs from spec (inconsistent error handling, missing edge cases)
- Maintenance burden: spec and code drift apart

**Required Before Merge:**
- [ ] After implementation complete, verify code matches spec exactly
- [ ] Update spec with any deviations (with justification)
- [ ] Add code comments referencing spec sections (bidirectional traceability)
- [ ] Document SigNoz API assumptions (version, endpoints, auth)

---

### Software Architect Pre-Merge Checklist

1. **Verify dashboard UUID/ID enforcement**
   - [ ] Run `for f in dashboards/signoz-import-pack/*.json; do jq -e 'has("uuid") or has("id")' "$f"; done`
   - [ ] All files pass (exit code 0)
   - [ ] Create test `test_all_dashboards_have_uuid_or_id()` (must pass)

2. **Verify idempotency pattern**
   - [ ] Implementation uses UUID/ID for matching (not title)
   - [ ] Test: import dashboards twice, verify second run imports 0 dashboards
   - [ ] Verify SRE customizations preserved (no overwrite flag)

3. **Verify contract alignment**
   - [ ] Bootstrap script part of SigNoz lifecycle (documented in platform contract)
   - [ ] No new dependencies introduced
   - [ ] No architectural debt

4. **Verify documentation consistency**
   - [ ] Specification matches implementation (after implementation complete)
   - [ ] Code comments reference spec sections
   - [ ] SigNoz API assumptions documented

---

## 4. Superpowers Creator Perspective

### Status: 🔴 RED (BLOCKING - Verification-Before-Completion Principle Violated)

### Critical Findings

#### Finding 1: Implementation Never Executed 🔴

**Violation:** The `verification-before-completion` skill explicitly states:
> "Evidence before assertions always" — never claim work is complete without running verification commands and confirming output.

**What Happened:**
- Conversation summary claimed "Task 8 COMPLETE" with "all tests passing"
- Gatekeeper provided "unanimous approval"
- But file search shows implementation files do NOT exist

**Impact:**
- Merge checklist based on false premise
- Pre-merge verification would fail immediately
- User misled about completion status

**Root Cause:** Specification was completed, but implementation delegation (to subagent) was not actually executed or was executed but never committed.

**Resolution Required:** Complete Task 8 implementation now, not post-merge.

---

#### Finding 2: Skills Not Applied Per Guidelines 🟡

**Applicable Skills (All Violated):**

| Skill | Requirement | Status |
|-------|-----------|--------|
| `test-driven-development` | Write tests BEFORE implementation | ❌ Tests don't exist, no TDD |
| `systematic-debugging` | Diagnose before proposing fixes | ⚠️ Spec diagnostic was good, but implementation gap not caught |
| `verification-before-completion` | Run verification before claiming complete | ❌ No verification run, false completion claim |
| `finishing-a-development-branch` | Structured options for merge (not blindly merge) | ⚠️ Merge checklist was premature (based on incomplete work) |
| `writing-plans` | Spec before implementation | ✅ Spec written, but implementation didn't follow |
| `brainstorming` | Explore requirements before design | ✅ Completed well in previous turns |

**Impact:** Superpowers workflow not followed for Task 8.

**Required Corrections:**
1. Apply `test-driven-development` skill: Write tests for Task 8 FIRST
2. Apply `verification-before-completion` skill: Run tests and verify implementation end-to-end
3. Apply `writing-plans` skill: Create Task 8 implementation plan (below)
4. Re-evaluate merge eligibility after implementation + verification complete

---

#### Finding 3: Gatekeeper Evaluation Based on Spec, Not Implementation 🟡

**The Problem:**
- Gatekeeper asked critical questions about idempotency, readiness gates, auth
- Spec answered all questions comprehensively
- **But gatekeeper did not verify that actual code exists**

**This is a Process Gap:**
- Spec ≠ Implementation
- Answering "What should we do?" ≠ Doing it
- Gatekeeper evaluation should include file verification step

**Lesson Learned:** Future gatekeeper evaluations must include:
```bash
# Verify that deliverable files actually exist
[ -f scripts/bootstrap_signoz_dashboards.sh ] || echo "❌ MISSING: bootstrap script"
[ -f tests/signoz/test_provision_readiness.py ] || echo "❌ MISSING: readiness tests"
# etc.
```

---

### Superpowers Pre-Merge Checklist

**All items BLOCKING (must complete before merge):**

1. **Complete Task 8 Implementation**
   - [ ] Create implementation plan (see Section 6 below)
   - [ ] Create `scripts/bootstrap_signoz_dashboards.sh` (bash)
   - [ ] Create `tests/signoz/test_provision_readiness.py` (unit tests)
   - [ ] Create `tests/signoz/test_dashboard_idempotency.py` (unit tests)
   - [ ] Create `tests/signoz/test_authentication.py` (unit tests)

2. **Run Verification Commands (Post-Implementation)**
   - [ ] `python3 -m unittest discover -s tests -p "test_*.py" -v` → 140+ tests pass
   - [ ] All new tests pass (8 new tests from Task 8)
   - [ ] No errors in bash scripts: `bash -n scripts/bootstrap_signoz_dashboards.sh`
   - [ ] `git status --porcelain` → clean working tree

3. **Execute Merge Only After Verification Passes**
   - [ ] DO NOT merge until all verification commands pass
   - [ ] DO NOT merge if any checklist item fails
   - [ ] Document git command used (with branch name, not directory path)

4. **Create Implementation Plan Document**
   - [ ] Write structured Task 8 implementation plan (spec → code → tests → verify)
   - [ ] Save to `docs/history/superpowers/TASK8-IMPLEMENTATION-PLAN.md`
   - [ ] Include specific script signatures, test cases, expected behavior
   - [ ] Ready for code review before merge

---

## 5. Aligned Findings Across All 4 Perspectives

### Critical Issues (All Perspectives Agree - BLOCKING)

| Issue | AWS | DevOps | Architecture | Superpowers |
|-------|-----|--------|--------------|-------------|
| **Implementation Missing** | - | 🔴 BLOCKING | 🟡 YELLOW | 🔴 BLOCKING |
| **No Tests Exist** | - | 🔴 BLOCKING | 🟡 YELLOW | 🔴 BLOCKING |
| **Verification Not Run** | - | 🔴 BLOCKING | 🟡 YELLOW | 🔴 BLOCKING |
| **Error Handling Unknown** | 🟡 YELLOW | 🔴 BLOCKING | - | 🔴 BLOCKING |
| **Credential Strategy (AWS or K8s)** | 🟡 YELLOW | 🟡 YELLOW | - | - |
| **Git Merge Command Syntax** | - | 🟡 YELLOW | - | 🟡 YELLOW |

### Consensus Decision

**All 4 perspectives agree: MERGE BLOCKED UNTIL IMPLEMENTATION COMPLETE**

- AWS Architect: Conditional approval pending verification that no AWS APIs used
- DevOps: RED - cannot merge without implementation + tests
- Software Architect: Conditional approval pending UUID/ID verification
- Superpowers Creator: RED - violation of verification-before-completion principle

---

## 6. DETAILED TASK 8 IMPLEMENTATION PLAN

### Scope

Complete Task 8: SigNoz Dashboard Automation with Readiness Gates & Idempotency

**Deliverables:**
1. `scripts/bootstrap_signoz_dashboards.sh` — Bash script for idempotent dashboard import
2. `scripts/provision-signoz-observability.sh` — Already exists, verify it calls bootstrap script
3. `tests/signoz/test_provision_readiness.py` — Unit tests for readiness gates
4. `tests/signoz/test_dashboard_idempotency.py` — Unit tests for idempotency
5. `tests/signoz/test_authentication.py` — Unit tests for secure auth
6. Documentation: Verify comments in scripts explain logic

**Total Effort:** ~4-6 hours (implementation + testing + verification)

### Phase A: Test-Driven Development (Write Tests First)

**File:** `tests/signoz/test_provision_readiness.py`

```python
import unittest
import pathlib

PROVISION_SCRIPT = pathlib.Path("scripts/provision-signoz-observability.sh")

class ProvisionReadinessTests(unittest.TestCase):
    def test_provision_script_exists(self):
        self.assertTrue(PROVISION_SCRIPT.exists(), "provision-signoz-observability.sh not found")

    def test_provision_script_includes_kubectl_wait_for_query_service(self):
        """Readiness gate: query-service pod must be Ready"""
        content = PROVISION_SCRIPT.read_text()
        self.assertIn("kubectl wait", content, "kubectl wait command missing")
        self.assertIn("query-service", content, "query-service label missing")
        self.assertIn("--timeout=300s", content, "300s timeout not set")

    def test_provision_script_includes_kubectl_wait_for_frontend(self):
        """Readiness gate: frontend pod must be Ready"""
        content = PROVISION_SCRIPT.read_text()
        self.assertIn("kubectl wait", content, "kubectl wait command missing")
        self.assertIn("frontend", content, "frontend label missing")
        self.assertIn("--timeout=300s", content, "300s timeout not set")

    def test_provision_script_exits_on_readiness_failure(self):
        """Failure handling: exit 1 if readiness check fails"""
        content = PROVISION_SCRIPT.read_text()
        self.assertIn("exit 1", content, "exit 1 not found for error handling")

    def test_provision_script_includes_curl_connectivity_test(self):
        """API connectivity check: curl to SigNoz API endpoint"""
        content = PROVISION_SCRIPT.read_text()
        self.assertIn("curl", content, "curl not used for connectivity test")
        self.assertIn("api/v1/dashboards", content, "SigNoz API endpoint not used")
```

**File:** `tests/signoz/test_dashboard_idempotency.py`

```python
import unittest
import pathlib
import json

class DashboardIdempotencyTests(unittest.TestCase):
    def test_all_dashboards_have_uuid_or_id(self):
        """Idempotency anchor: all dashboards must have UUID or ID field"""
        dashboards_dir = pathlib.Path("dashboards/signoz-import-pack")
        for dashboard_file in dashboards_dir.glob("*.json"):
            data = json.loads(dashboard_file.read_text())
            self.assertTrue(
                "uuid" in data or "id" in data,
                f"Dashboard {dashboard_file.name} missing uuid or id field"
            )

    def test_bootstrap_script_exists(self):
        bootstrap_script = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh")
        self.assertTrue(bootstrap_script.exists(), "bootstrap_signoz_dashboards.sh not found")

    def test_bootstrap_script_includes_check_before_import(self):
        """Idempotency logic: query API before importing"""
        content = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertIn("api/v1/dashboards", content, "Dashboard API query missing")
        # Check for conditional logic (if exists then skip)
        self.assertTrue(
            "if" in content and ("exist" in content or "found" in content or "200" in content),
            "Check-before-import logic missing"
        )

    def test_bootstrap_script_preserves_sre_customizations(self):
        """Safety: no --force or --overwrite flag that would delete customizations"""
        content = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertNotIn("--force", content, "Dangerous --force flag found")
        self.assertNotIn("--overwrite", content, "Dangerous --overwrite flag found")
        self.assertNotIn("-f", content, "Dangerous -f flag found (could mean --force)")
```

**File:** `tests/signoz/test_authentication.py`

```python
import unittest
import pathlib

class AuthenticationTests(unittest.TestCase):
    def test_bootstrap_script_uses_kubernetes_secret_not_hardcoded_credentials(self):
        """Security: credentials from Secret, not hardcoded"""
        content = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertIn("kubectl get secret", content, "kubectl get secret not used")
        self.assertIn("signoz-root-user", content, "signoz-root-user Secret not referenced")
        # Negative check: ensure no hardcoded password
        self.assertNotIn("password=", content, "Hardcoded password found!")
        self.assertNotIn("admin:", content, "Hardcoded credentials in URL found!")

    def test_bootstrap_script_exits_if_secret_missing(self):
        """Error handling: exit if Secret doesn't exist"""
        content = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertIn("exit 1", content, "exit 1 not found")
        # Should check for secret existence
        self.assertTrue(
            "secret" in content.lower() and ("missing" in content.lower() or "not found" in content.lower()),
            "Error message for missing secret not found"
        )

    def test_bootstrap_script_uses_base64_decode(self):
        """Credential handling: base64 decode Secret (not raw text)"""
        content = pathlib.Path("scripts/bootstrap_signoz_dashboards.sh").read_text()
        self.assertTrue(
            "base64" in content or "b64" in content,
            "Base64 decoding not found (Secret is base64-encoded)"
        )
```

### Phase B: Write Implementation

**File:** `scripts/bootstrap_signoz_dashboards.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Import SigNoz dashboards from JSON files with idempotency guarantee.
# Prerequisites:
#   - SigNoz pods are Ready (use scripts/provision-signoz-observability.sh which waits)
#   - signoz-root-user Secret exists (created by scripts/create-signoz-root-user-secret.sh)
#   - Dashboard JSON files in dashboards/signoz-import-pack/ have uuid or id field
#
# Idempotency:
#   - First run: imports all missing dashboards
#   - Second run: skips existing dashboards (SRE customizations preserved)
#   - If dashboard deleted: re-run imports it again

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DASHBOARDS_DIR="$ROOT_DIR/dashboards/signoz-import-pack"
SIGNOZ_NAMESPACE="signoz"
SIGNOZ_SECRET="signoz-root-user"

# Retrieve SigNoz root user credentials from Kubernetes Secret
echo "=== Dashboard Import: Retrieving Credentials ==="
if ! kubectl get secret "$SIGNOZ_SECRET" -n "$SIGNOZ_NAMESPACE" &>/dev/null; then
    echo "❌ ERROR: Secret '$SIGNOZ_SECRET' not found in namespace '$SIGNOZ_NAMESPACE'"
    echo "   Prerequisites: Run scripts/create-signoz-root-user-secret.sh first"
    exit 1
fi

# Extract email and password from Secret (base64-encoded by kubectl)
SIGNOZ_EMAIL=$(kubectl get secret "$SIGNOZ_SECRET" -n "$SIGNOZ_NAMESPACE" -o jsonpath='{.data.email}' | base64 -d)
SIGNOZ_PASSWORD=$(kubectl get secret "$SIGNOZ_SECRET" -n "$SIGNOZ_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

# Determine SigNoz API endpoint (use port-forward or in-cluster service)
SIGNOZ_API="${SIGNOZ_ENDPOINT:-http://frontend.${SIGNOZ_NAMESPACE}.svc.cluster.local:3301/api/v1}"

echo "✅ Credentials retrieved from Secret"
echo ""

# Authenticate to SigNoz API
echo "=== Dashboard Import: Authenticating to SigNoz API ==="
LOGIN_RESPONSE=$(curl -s -X POST "${SIGNOZ_API%/api/v1}/api/v1/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$SIGNOZ_EMAIL\", \"password\": \"$SIGNOZ_PASSWORD\"}")

if ! echo "$LOGIN_RESPONSE" | jq -e '.accessJwt' > /dev/null 2>&1; then
    echo "❌ ERROR: Authentication failed"
    echo "   Response: $LOGIN_RESPONSE"
    exit 1
fi

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessJwt')
echo "✅ Authenticated successfully"
echo ""

# Import dashboards
echo "=== Dashboard Import: Processing Dashboard Files ==="
IMPORT_COUNT=0
SKIP_COUNT=0

for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
    if [ ! -f "$dashboard_file" ]; then
        echo "⚠️  No dashboard files found in $DASHBOARDS_DIR"
        break
    fi

    dashboard_name=$(basename "$dashboard_file" .json)
    
    # Extract UUID or ID from dashboard JSON (idempotency key)
    dashboard_id=$(jq -r '.uuid // .id // empty' "$dashboard_file")
    if [ -z "$dashboard_id" ]; then
        echo "❌ ERROR: Dashboard $dashboard_name missing uuid or id field"
        exit 1
    fi

    # Check if dashboard already exists (by UUID/ID)
    echo "  → Checking $dashboard_name (ID: $dashboard_id)..."
    existing_dashboard=$(curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
        "${SIGNOZ_API}/dashboards" | jq -r ".payload[] | select(.uuid == \"$dashboard_id\" or .id == \"$dashboard_id\") | .uuid // .id")

    if [ -n "$existing_dashboard" ]; then
        echo "    ⏭️  SKIP (already exists, SRE customizations preserved)"
        ((SKIP_COUNT++))
    else
        # Import new dashboard
        echo "    📥 IMPORT..."
        if curl -s -X POST "${SIGNOZ_API}/dashboards" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Content-Type: application/json" \
            -d "@$dashboard_file" | jq -e '.data' > /dev/null 2>&1; then
            echo "    ✅ IMPORTED"
            ((IMPORT_COUNT++))
        else
            echo "    ❌ ERROR: Failed to import dashboard"
            exit 1
        fi
    fi
done

echo ""
echo "=== Dashboard Import: Complete ==="
echo "✅ Imported: $IMPORT_COUNT dashboards"
echo "✅ Skipped: $SKIP_COUNT dashboards (existing)"
echo ""
```

### Phase C: Update Main Provision Script

**File:** `scripts/provision-signoz-observability.sh` (modify to call bootstrap)

Add at the end of the script (after Terraform apply):

```bash
echo ""
echo "=== SigNoz Observability: Importing Dashboards ==="

# Call dashboard bootstrap script
if [ -f "scripts/bootstrap_signoz_dashboards.sh" ]; then
    bash scripts/bootstrap_signoz_dashboards.sh || {
        echo "❌ Dashboard import failed"
        exit 1
    }
else
    echo "⚠️  Warning: bootstrap_signoz_dashboards.sh not found, skipping dashboard import"
fi

echo "✅ SigNoz observability provisioning complete"
```

### Phase D: Run Tests & Verification

**Command Sequence:**

```bash
cd /Users/frank/sml/oms/mongodb

# 1. Run all unit tests (including new Task 8 tests)
python3 -m unittest discover -s tests -p "test_*.py" -v

# Expected output:
#   test_provision_readiness.py: 4 tests PASS
#   test_dashboard_idempotency.py: 4 tests PASS
#   test_authentication.py: 2 tests PASS
#   Total: 140+ tests PASS (0 failures)

# 2. Verify bash syntax
bash -n scripts/bootstrap_signoz_dashboards.sh

# 3. Verify git working tree clean
git status --porcelain
# Expected: (empty)

# 4. Verify all dashboard JSONs have UUID/ID
for f in dashboards/signoz-import-pack/*.json; do
  jq 'has("uuid") or has("id")' "$f"
done
# Expected: true for all files
```

---

## 7. Execution Roadmap (Before Merge)

### Step 1: Write Tests (TDD)
- [ ] Create `tests/signoz/test_provision_readiness.py` (run tests, expect failure)
- [ ] Create `tests/signoz/test_dashboard_idempotency.py` (run tests, expect failure)
- [ ] Create `tests/signoz/test_authentication.py` (run tests, expect failure)
- [ ] Commit: "Task 8: Add readiness, idempotency, and auth tests"

### Step 2: Implement Bootstrap Script
- [ ] Create `scripts/bootstrap_signoz_dashboards.sh`
- [ ] Run tests (expect all to pass now)
- [ ] Run bash syntax check
- [ ] Commit: "Task 8: Implement dashboard bootstrap with readiness, idempotency, auth"

### Step 3: Verify Provision Script Integration
- [ ] Verify `scripts/provision-signoz-observability.sh` calls bootstrap script
- [ ] Add error handling if bootstrap fails
- [ ] Commit: "Task 8: Integrate bootstrap script into provision orchestration"

### Step 4: Run Full Verification
- [ ] Run all 140+ unit tests (must pass)
- [ ] Run bash syntax checks (must pass)
- [ ] Verify dashboard UUID/ID fields (all must have uuid or id)
- [ ] Verify git working tree clean
- [ ] Create detailed verification report

### Step 5: Update Documentation
- [ ] Verify devops-signoz-dashboard-import-spec.md matches implementation
- [ ] Add code comments explaining idempotency, readiness, auth
- [ ] Document SigNoz API assumptions
- [ ] Update any relevant README files

### Step 6: Pre-Merge Checklist
- [ ] All 9 pre-merge items from Section 2-4 above PASS
- [ ] No conflicts with main branch
- [ ] Merge dry-run successful
- [ ] Ready for merge authorization

---

## 8. Decision Gate: Proceed with Implementation or Escalate?

**Two Options:**

### Option A: Proceed with Implementation Now (Recommended)
- Complete all Task 8 deliverables today
- Run full verification suite
- Re-run 4-perspective evaluation
- Proceed to merge (if all checks pass)
- Estimated time: 4-6 hours

**Advantages:**
- Phase 3 closure today
- All work verified before merge
- No technical debt
- Follows superpowers verification principles

### Option B: Escalate to User for Decision
- User reviews this evaluation
- User decides: implement now vs. defer vs. reject
- User may want code review before implementation starts

**Recommended:** Option A (implement now, we're so close)

---

## Summary: Status Before Implementation

| Perspective | Status | Blocking | Required Action |
|---|---|---|---|
| AWS Architect | 🟡 YELLOW | No | Verify no AWS APIs in implementation |
| DevOps | 🔴 RED | **YES** | Implement + test readiness, idempotency, auth |
| Software Architect | 🟡 YELLOW | No | Verify dashboard UUID/ID enforcement |
| Superpowers Creator | 🔴 RED | **YES** | Complete implementation + verification |

**Overall Status: MERGE BLOCKED until Task 8 implemented + verified**

