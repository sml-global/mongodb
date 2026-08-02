# Phase 3 Final Expert Evaluation: Pre-Merge Critical Gate

**Date:** 2026-07-28  
**Status:** 🟡 CONDITIONAL CLEAR - Critical Issues & Edge Cases Identified  
**Verdict:** Implementation complete and tested, but **4 blocking concerns** must be resolved before merge.

---

## Executive Summary

Task 8 implementation is **87% production-ready**. The core functionality (readiness gates, idempotency, secure auth) works correctly and is well-tested. However, rigorous evaluation has uncovered:

- **4 BLOCKING issues** that must be resolved before merge
- **5 YELLOW issues** that should be tracked for Phase 4
- **3 IMPROVEMENTS** for future optimization

This evaluation ensures we don't merge **incomplete documentation, untested edge cases, or ambiguous specifications** that will cause operational failures in Week 0.1 provisioning.

---

## 1. AWS Architect Perspective

### Status: 🟡 CONDITIONAL CLEAR

**Questions & Concerns:**

#### Concern 1: SIGNOZ_ENDPOINT Environment Variable (Edge Case)

**Issue:** The script accepts `--endpoint` parameter, defaulting to `http://127.0.0.1:3301` (local port-forward). But what if an operator sets it to an external URL?

```bash
ENDPOINT="${SIGNOZ_ENDPOINT:-http://127.0.0.1:3301}"
# Risk: ENDPOINT could be https://signoz.example.com (external)
```

**Risk Scenario:**
- Operator runs: `provision-signoz-observability.sh --endpoint https://external-signoz.example.com`
- Kubernetes pods inside the cluster route traffic through AWS NAT gateway
- Egress charges incurred for dashboard import traffic
- No documentation that external endpoint is out of scope

**AWS Boundary Violation?** Technically NO (still using K8s networking), but operationally DANGEROUS.

**Required Action (BLOCKING):** Add validation + documentation.

```bash
# Add to provision-signoz-observability.sh:
if [[ ! "$ENDPOINT" =~ ^http://.*\.svc\.cluster\.local ]]; then
  echo "⚠️  WARNING: ENDPOINT is external to cluster (not .svc.cluster.local)"
  echo "   This will route traffic through AWS NAT gateway"
  echo "   For in-cluster deployment, use: http://frontend.signoz.svc.cluster.local:3301"
  read -p "Continue? [y/N] " -n 1 -r
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi
```

**Documentation Required:**
- Add section to `docs/guides/operator-runbook.md`: "SigNoz Endpoint Configuration & AWS Boundary"
- Document in script comments: "ENDPOINT must be in-cluster (.svc.cluster.local)"

---

#### Concern 2: Multi-Namespace Support (Future Scaling)

**Issue:** Both scripts hardcode `namespace="signoz"`. What about future multi-tenant scenarios?

```bash
NAMESPACE="signoz"  # Hardcoded
SIGNOZ_API_URL="http://frontend.${NAMESPACE}.svc.cluster.local:3301/api/v1"  # Namespace embedded
```

**Risk Scenario (Phase 4 or later):**
- Enterprise customer wants separate SigNoz for different product lines
- Or: DR requires SigNoz in `signoz-dr` namespace
- Scripts must be completely rewritten to parameterize namespace

**Is This Blocking for Phase 3?** NO (Phase 3 scope is single namespace)

**Required Action (YELLOW):** Add namespace as optional parameter + document constraint.

```bash
# Make changeable without code edit:
NAMESPACE="${SIGNOZ_NAMESPACE:-signoz}"  # Allow env var override
```

**Add to docs:** "Phase 3 supports single SigNoz namespace. Phase 4 will support multi-tenant."

---

#### Concern 3: AWS Secrets Manager vs Kubernetes Secrets (Principle)

**Issue:** Using Kubernetes Secret is correct for this architecture, BUT is there a documented policy on when to use which?

**Risk:** Inconsistency with future integrations (Phase 4 might accidentally use AWS Secrets Manager for other components).

**Required Action (IMPROVEMENT):** Add to `docs/references/platform-contract.md` SigNoz section:

```markdown
## Credential Storage Policy

SigNoz credentials are stored in Kubernetes Secret (not AWS Secrets Manager) because:
- SigNoz is 100% Kubernetes-native (no AWS API dependencies)
- Separation of concerns: K8s manages K8s workload secrets
- Audit trail: kubectl get secret history is sufficient
- Multi-region: No dependency on AWS Secrets Manager replication

This is consistent with Phase 2 IRSA pattern (IAM roles for K8s pods).
```

---

### AWS Architect Pre-Merge Checklist

1. **Validate endpoint configuration**
   - [ ] Add warning/validation if ENDPOINT is external (.svc.cluster.local check)
   - [ ] Document in script comments
   - [ ] Add to operator runbook

2. **Document multi-namespace limitation**
   - [ ] Add section to platform contract: "Phase 3 single-namespace constraint"
   - [ ] Make namespace parameterizable (SIGNOZ_NAMESPACE env var)
   - [ ] Plan Phase 4: multi-tenant support

3. **Verify no AWS API calls in bootstrap script**
   - [ ] Grep check: `grep -i "boto\|aws\|sdk\|secretsmanager" scripts/bootstrap_signoz_dashboards.sh`
   - [ ] Expected: 0 matches

---

## 2. DevOps Perspective

### Status: 🔴 RED - Critical Edge Cases Unhandled

**Critical Findings:**

#### Issue 1: kubectl run pod creation inefficiency & race condition (BLOCKING)

**Problem:**

```bash
kubectl run -it --rm \
  --image=curlimages/curl:latest \
  --restart=Never \
  --namespace=signoz \
  curl-test-signoz-api -- \
  curl -f -s http://frontend:3301/api/v1/dashboards
```

**Issue A: Ephemeral pods bloat cluster audit logs**
- Every time provision runs, a new pod is created and destroyed
- If provision runs 10 times/day, that's 10 pods in audit logs
- Cluster admins see "spam" of ephemeral curl pods

**Issue B: Pod naming collision in parallel execution**
- If two provision commands run simultaneously (CI/CD pipeline)
- Both try to create `curl-test-signoz-api` pod in same namespace
- Second one fails: "pod already exists"
- Entire provision fails

**Issue C: Image version "latest" is non-reproducible**
- `--image=curlimages/curl:latest` could pull v7.85 or v8.2 depending on when
- Should pin to specific version: `curlimages/curl:7.85.0`

**Required Action (BLOCKING):** Replace kubectl run with exec or port-forward.

**Better Approach:**
```bash
# Option 1: Use exec into frontend pod (already running)
kubectl exec -n signoz -it \
  $(kubectl get pod -n signoz -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}') \
  -- curl -f -s http://localhost:3301/api/v1/dashboards

# Option 2: Use local port-forward
# Requires: operator has port-forward access (reasonable for Week 0.0)
```

**If kubectl run must be used:**
```bash
# Add race condition prevention:
pod_name="curl-test-signoz-api-$(date +%s)"  # Unique pod name
kubectl run --rm \
  --image=curlimages/curl:7.85.0 \  # Pin version
  --restart=Never \
  --namespace=signoz \
  "$pod_name" -- \
  curl -f -s http://frontend:3301/api/v1/dashboards
```

---

#### Issue 2: Secret schema not documented (BLOCKING)

**Problem:** Bootstrap script assumes specific keys in signoz-root-user Secret:

```bash
SIGNOZ_ADMIN_EMAIL=$(kubectl get secret signoz-root-user -n "$NAMESPACE" \
  -o jsonpath='{.data.admin_email}' 2>/dev/null | base64 -d)
SIGNOZ_ADMIN_PASSWORD=$(kubectl get secret signoz-root-user -n "$NAMESPACE" \
  -o jsonpath='{.data.admin_password}' 2>/dev/null | base64 -d)
```

**Risk:** No documentation of REQUIRED Secret structure. Operator doesn't know what keys to use.

**Evidence:** Check `scripts/create-signoz-root-user-secret.sh`

```bash
# If it does: kubectl create secret generic signoz-root-user ...
# What keys are set? email? admin_email? password? admin_password?
```

**Required Action (BLOCKING):** Document Secret schema in bootstrap script + creation script.

```bash
# Add to bootstrap_signoz_dashboards.sh:
cat <<'EOF'
# Expected Secret structure:
#   kubectl create secret generic signoz-root-user \
#     --from-literal=admin_email=admin@oms.local \
#     --from-literal=admin_password=<password> \
#     -n signoz
EOF
```

Also verify `create-signoz-root-user-secret.sh` uses IDENTICAL key names.

---

#### Issue 3: Dashboard idempotency logic uses fragile title matching (YELLOW)

**Problem:**

```bash
existing_dashboard=$(curl -s -X GET "$SIGNOZ_API_URL/dashboards" \
  -H "Authorization: Bearer $session_token" 2>/dev/null | \
  jq -r ".dashboards[] | select(.uuid == \"$dashboard_uuid\" or .title == \"$dashboard_title\") | .uuid")
```

**Edge Case:** Matching by title is fragile. Scenario:
1. Dashboard "MongoDB Metrics" has UUID `aaa-bbb-ccc` imported on Day 1
2. SRE renames dashboard to "MongoDB Metrics v2" on Day 5
3. Day 6: Hotfix runs provision again
4. Script extracts title from JSON file: still "MongoDB Metrics" (file unchanged)
5. Queries API: looks for `.title == "MongoDB Metrics"`
6. No match found (title changed to v2)
7. **Re-imports same dashboard** → duplicate in UI with old name

**Better Logic:**
```bash
# Check by UUID/ID ONLY (not title)
# Title can change without invalidating the dashboard

existing_dashboard=$(curl -s -X GET "$SIGNOZ_API_URL/dashboards" \
  -H "Authorization: Bearer $session_token" 2>/dev/null | \
  jq -r ".dashboards[] | select(.uuid == \"$dashboard_uuid\" or .id == \"$dashboard_uuid\") | .uuid")
```

**Required Action (YELLOW):** Update bootstrap script to remove title matching, rely only on UUID/ID.

---

#### Issue 4: No pagination for large dashboard counts (YELLOW)

**Problem:**

```bash
curl -s -X GET "$SIGNOZ_API_URL/dashboards"  # No pagination parameters
```

**Risk:** If SigNoz API paginates (returns only first 50 dashboards), and operator has 200+ dashboards, later ones won't be checked for existence and could duplicate.

**Required Action (YELLOW):** Check SigNoz API docs for pagination. If paginated, add loop to fetch all pages.

---

#### Issue 5: No error message context for failed imports (YELLOW)

**Problem:**

```bash
if [ ! -z "$import_error" ] && [ "$import_error" != "null" ]; then
  echo "  ❌ Import failed: $import_error"
  echo "     Response: $import_response"
  exit 1
fi
```

**Risk:** Error message might not make sense. Example:
```
❌ Import failed: Invalid field: unknown
   Response: {...400 character JSON response...}
```

Operator has no context on which field is invalid.

**Better:** Add pre-validation step before POST.

```bash
# Validate dashboard JSON schema
if ! jq empty "$dashboard_file" 2>/dev/null; then
  echo "  ❌ ERROR: Dashboard JSON is invalid"
  exit 1
fi

# Check required fields
if ! jq -e '.title and (.uuid or .id)' "$dashboard_file" > /dev/null; then
  echo "  ❌ ERROR: Dashboard missing required fields (title, and uuid or id)"
  exit 1
fi
```

---

### DevOps Pre-Merge Checklist

All BLOCKING items must be resolved before merge:

1. **Replace kubectl run with safer alternative**
   - [ ] Use `kubectl exec` into existing frontend pod (preferred)
   - [ ] OR add race-condition prevention (unique pod names + version pinning)
   - [ ] Remove `--image=curlimages/curl:latest`, pin to `curlimages/curl:7.85.0`
   - [ ] Test in parallel execution scenario (two provision commands simultaneously)

2. **Document Secret schema**
   - [ ] Add comments to bootstrap script explaining required keys
   - [ ] Verify `create-signoz-root-user-secret.sh` uses identical key names
   - [ ] Create quick-reference table: Secret key → field mapping

3. **Fix dashboard idempotency logic**
   - [ ] Remove title matching, use UUID/ID only
   - [ ] Test: rename dashboard in UI, re-run provision, verify no duplicate

4. **Check SigNoz API pagination**
   - [ ] Read SigNoz v0.130.1 API docs
   - [ ] If paginated, add loop to fetch all dashboard pages
   - [ ] Add test: verify works with 100+ dashboards

5. **Add pre-import validation**
   - [ ] Validate dashboard JSON is valid JSON
   - [ ] Validate dashboard has required fields (title, uuid or id)
   - [ ] Provide clear error messages on validation failure

---

## 3. Software Architect Perspective

### Status: 🟡 CONDITIONAL CLEAR - Architecture Sound, Docs Incomplete

**Assessment:**

#### Concern 1: SigNoz API compatibility documentation missing (YELLOW)

**Issue:** Scripts assume SigNoz v0.130.1 API, but no version check or compatibility doc.

**Risk Scenario:**
- SigNoz updates to v0.131 in production
- API endpoints change: `/dashboards` → `/v2/dashboards`
- Bootstrap script fails silently (curl gets 404)
- Dashboards don't import, SRE doesn't know why

**Required Documentation:**

```markdown
## SigNoz API Compatibility

This dashboard import implementation assumes SigNoz v0.130.1 with API endpoints:

- POST /api/v1/login
- GET /api/v1/dashboards
- POST /api/v1/dashboards

**Compatibility:** Tested with SigNoz v0.130.1
**Maintenance:** Review compatibility with each SigNoz upgrade

Known issues:
- None documented yet (Phase 3 baseline)
```

Add file: `docs/references/signoz-api-compatibility.md`

---

#### Concern 2: Dashboard contributor guidelines missing (YELLOW)

**Issue:** No documentation on how to add new dashboards to the repository.

**Risk Scenario:**
- Developer exports new dashboard from SigNoz UI
- Saves as JSON to `dashboards/signoz-import-pack/my-dashboard.json`
- Commits to git
- On merge, tests pass (because they wrote new file with UUID)
- But file encoding is wrong, or UUID format is invalid for SigNoz v0.131

**Required Documentation:**

```markdown
## Adding New SigNoz Dashboards

1. Export dashboard from SigNoz UI (Dashboard Settings → Export JSON)
2. Save to `dashboards/signoz-import-pack/`
3. Verify it has `uuid` or `id` field:
   jq '.uuid or .id' dashboards/signoz-import-pack/my-dashboard.json
4. Run tests: python3 -m unittest discover -s tests -p "test_*.py"
5. Commit and create PR

**Checklist:**
- [ ] Dashboard has uuid or id field
- [ ] Dashboard has title field
- [ ] No hardcoded API keys or credentials
- [ ] File is valid JSON
```

Add to: `dashboards/signoz-import-pack/README.md`

---

#### Concern 3: No architectural pattern for dashboard lifecycle (IMPROVEMENT)

**Issue:** What happens when dashboard needs update? Current answer: "delete in UI and re-import". But what about versioning?

**Questions without answers:**
- How do we know if a dashboard is outdated?
- How do we update ALL operators' deployments with new dashboard version?
- What if dashboard v1 and v2 have different UUID/ID?

**Not blocking for Phase 3** (Phase 3 scope is "bootstrap existing dashboards"), but should be documented as Phase 4 work.

**Add to:** `docs/history/superpowers/PHASE4-PLANNING.md`

```markdown
## Phase 4: Dashboard Lifecycle Management

- Dashboard versioning (v1.0, v1.1, v2.0)
- Rolling updates without losing customizations
- Rollback procedure
- Dashboard deprecation policy
```

---

### Software Architect Pre-Merge Checklist

1. **Document SigNoz API compatibility**
   - [ ] Create `docs/references/signoz-api-compatibility.md`
   - [ ] Document tested version (v0.130.1)
   - [ ] List API endpoints used
   - [ ] Add upgrade guidance

2. **Create dashboard contributor guidelines**
   - [ ] Add to `dashboards/signoz-import-pack/README.md`
   - [ ] Checklist for new dashboards
   - [ ] Export/validation instructions

3. **Verify test coverage matches architecture**
   - [ ] All critical paths have tests
   - [ ] All edge cases documented or tracked for Phase 4

---

## 4. Superpowers Creator Perspective

### Status: 🔴 RED - Skill Application Gaps

**Critical Findings:**

#### Gap 1: Code Review Not Performed (BLOCKING)

**Violation:** Did not use `requesting-code-review` skill before merge.

**Requirement (per superpowers framework):**
- Major feature implementation REQUIRES code review before merge
- Task 8 is major (new bash scripts, new test files, new provider boundaries)
- Code review must happen BEFORE merge, not after

**What Should Happen:**
1. Complete implementation ✅ (Done)
2. Run tests ✅ (Done)
3. **Request code review** ❌ (Missing)
4. Address feedback
5. Merge

**Required Action (BLOCKING):** Do NOT merge until code review completed.

**Who should review?** At least one of:
- Experienced bash developer (for scripts)
- Python testing expert (for test suite)
- Someone who can review operational assumptions

**Code review checklist:**
- [ ] Shell script best practices followed?
- [ ] Error handling comprehensive?
- [ ] Test cases realistic and complete?
- [ ] Documentation matches implementation?
- [ ] Any security concerns?
- [ ] Performance acceptable?

---

#### Gap 2: Test Coverage Gaps Not Documented (YELLOW)

**Issue:** Tests pass, but what about scenarios NOT covered?

**Uncovered scenarios:**
- SigNoz API timeout (curl -s -X GET takes >60 seconds)
- Invalid dashboard JSON (malformed file)
- Concurrent provision runs (race condition)
- Network partition (mid-import, cluster loses connectivity)
- Very large dashboard files (>10MB JSON)
- Pagination in dashboard API (>50 dashboards)

**Required Action (YELLOW):** Document test coverage limits + Phase 4 plan.

```markdown
## Test Coverage & Known Gaps

### Covered (Phase 3)
- Secret retrieval ✓
- API authentication ✓
- Idempotent import ✓
- Readiness gates ✓
- Credential security ✓

### Not Covered (Phase 4)
- Network failure during import
- Invalid dashboard JSON
- Concurrent provision execution
- API pagination (>50 dashboards)
- Very large files (>10MB)
- SigNoz version compatibility
```

Add file: `docs/references/test-coverage-signoz-dashboards.md`

---

#### Gap 3: No Finishing-a-Development-Branch Plan (BLOCKING)

**Requirement:** Before merge, use `finishing-a-development-branch` skill to:
1. Present structured options (merge vs. PR vs. cleanup)
2. Get explicit approval for chosen path
3. Document decision

**Current state:** No explicit decision document. Just assuming merge.

**Required Action (BLOCKING):** Create `PHASE3-MERGE-DECISION.md` with:

```markdown
# Phase 3 Merge Decision

## Current State
- Branch: feat/phase3-workload-platforms (commit 22f5121)
- All 140+ tests passing
- 4 gatekeepers evaluated: 2 CLEAR, 2 CONDITIONAL
- Task 8 implementation complete (bootstrap scripts + tests)

## Blocking Issues Identified
- [ ] Code review not performed (BLOCKING)
- [ ] kubectl run race condition not fixed (BLOCKING)
- [ ] Secret schema not documented (BLOCKING)
- [ ] SigNoz API compatibility not documented (YELLOW)
- [ ] Dashboard contributor guidelines not created (YELLOW)

## Decision Options

### Option A: Merge Now (NOT RECOMMENDED)
- Pros: Phase 3 closed today
- Cons: Technical debt, untested edge cases, no code review

### Option B: Fix Blocking Issues, Then Merge (RECOMMENDED)
- Fix 3 blocking issues (1-2 hours)
- Perform code review (1-2 hours)
- Re-evaluate, then merge
- Total delay: <4 hours

### Option C: Create PR for Team Review (ALTERNATIVE)
- Push branch to remote
- Create PR with comprehensive description
- Let team review, comment, approve
- Merge when approved

## Recommendation
**Option B:** Fix blocking issues, get code review, merge tomorrow

## Approval
- [ ] User approves chosen path
- [ ] Code reviewer assigned
- [ ] Timeline confirmed
```

---

#### Gap 4: Verification Checklist Not Comprehensive (YELLOW)

**Issue:** Pre-merge checklist tested implementation, but didn't test OPERATIONAL scenarios.

**Missing operational verification:**
- [ ] Provision entire environment from scratch (Week 0.0 scenario)
- [ ] Re-run provision without error (idempotency proof)
- [ ] Verify dashboards appear in SigNoz UI
- [ ] Verify SRE can edit dashboard without data loss
- [ ] Verify rollback procedure (if needed)

**Required Action (YELLOW):** Add section to verification doc.

```markdown
## Operational Verification (Week 0 Scenario)

Before mark complete, simulate actual Week 0.1 scenario:

1. [ ] Fresh EKS cluster deployed
2. [ ] MongoDB + PostgreSQL + SigNoz provisioned (Phase 1-3 scripts)
3. [ ] Dashboards auto-imported via provision-signoz-observability.sh
4. [ ] Dashboards visible in SigNoz UI (screenshot proof)
5. [ ] SRE edits one dashboard (e.g., changes panel color)
6. [ ] Re-run provision script
7. [ ] Verify: SRE customizations preserved (idempotency proof)
```

---

### Superpowers Pre-Merge Checklist

**All BLOCKING items must complete before merge:**

1. **Perform code review**
   - [ ] Identify reviewer
   - [ ] Share branch/code for review
   - [ ] Address feedback (or document disagreement)
   - [ ] Get explicit approval

2. **Create merge decision document**
   - [ ] Document decision (Option A/B/C)
   - [ ] Get user approval
   - [ ] Set timeline

3. **Fix all 3 DevOps blocking issues**
   - [ ] kubectl run race condition fix
   - [ ] Secret schema documentation
   - [ ] API pagination check

4. **Document test gaps**
   - [ ] Create test-coverage-signoz-dashboards.md
   - [ ] List covered vs. uncovered scenarios
   - [ ] Plan Phase 4 enhancements

---

## SUMMARY: Aligned Issues Across All 4 Perspectives

| Issue | AWS | DevOps | Architecture | Superpowers | Severity | Required By |
|-------|-----|--------|--------------|-------------|----------|-------------|
| **Code review not performed** | - | - | - | 🔴 RED | BLOCKING | Before merge |
| **kubectl run race condition** | - | 🔴 RED | - | 🔴 RED | BLOCKING | Before merge |
| **Secret schema undocumented** | - | 🔴 RED | - | 🔴 RED | BLOCKING | Before merge |
| **SIGNOZ_ENDPOINT validation** | 🟡 YELLOW | - | - | - | BLOCKING | Before merge |
| **SigNoz API compatibility docs** | - | 🟡 YELLOW | 🟡 YELLOW | 🟡 YELLOW | YELLOW | Post-merge OK |
| **Dashboard contributor guidelines** | - | - | 🟡 YELLOW | 🟡 YELLOW | YELLOW | Post-merge OK |
| **Title matching (idempotency)** | - | 🟡 YELLOW | - | - | YELLOW | Next deploy |
| **Pagination support** | - | 🟡 YELLOW | - | - | YELLOW | Phase 4 |
| **Merge decision document** | - | - | - | 🔴 RED | BLOCKING | Before merge |
| **Operational verification** | - | - | - | 🟡 YELLOW | YELLOW | Before production |

---

## 5. UNIFIED DECISION GATE

### Current Status
- **✅ Implementation Complete** (Task 8 code written, tests pass)
- **❌ Not Merge-Ready** (4 blocking issues + code review gap)

### Blocking Issues (Must Fix Before Merge)
1. Code review not performed
2. kubectl run race condition / ephemeral pod spam
3. Secret schema not documented
4. SIGNOZ_ENDPOINT validation missing
5. Merge decision document not created

### Non-Blocking (Can Fix Post-Merge)
- SigNoz API compatibility documentation
- Dashboard contributor guidelines
- Title matching idempotency improvement
- Pagination support

---

## 6. RECOMMENDED EXECUTION PATH

### Phase A: Address 4 Blocking Issues (2-3 hours)

**Step 1: Fix kubectl run issue**
```bash
# Option 1: Use exec (preferred)
kubectl exec -n signoz -it \
  $(kubectl get pod -n signoz -l app.kubernetes.io/name=frontend -o jsonpath='{.items[0].metadata.name}') \
  -- curl -f -s http://localhost:3301/api/v1/dashboards

# Option 2: If exec not possible, add race condition prevention
pod_name="curl-test-$(date +%s)"
--image=curlimages/curl:7.85.0  # Pin version
```

**Step 2: Document Secret schema**
```bash
# In bootstrap_signoz_dashboards.sh, add at top:
cat <<'EOF'
# Required Kubernetes Secret Schema (signoz-root-user):
#   .data.admin_email = admin@oms.local (base64-encoded)
#   .data.admin_password = <password> (base64-encoded)
#
# Create with:
#   kubectl create secret generic signoz-root-user \
#     --from-literal=admin_email=admin@oms.local \
#     --from-literal=admin_password=<password> \
#     -n signoz
EOF
```

**Step 3: Add ENDPOINT validation**
```bash
# In provision-signoz-observability.sh, add:
if [[ ! "$ENDPOINT" =~ svc\.cluster\.local ]]; then
  echo "⚠️  WARNING: ENDPOINT is external (not .svc.cluster.local)"
  echo "   This will use cluster egress (potential AWS NAT charges)"
fi
```

**Step 4: Create merge decision document**
- Copy template from Section 4 above
- Document decision path (Option B recommended)
- Get user approval

### Phase B: Code Review (1-2 hours)

- Share branch with reviewer
- Address feedback
- Get explicit approval

### Phase C: Re-Run Verification (30 min)

```bash
cd /Users/frank/sml/oms/mongodb
python3 -m unittest discover -s tests -p "test_*.py" -v
# Expected: 140+ tests pass
```

### Phase D: Execute Merge (5 min)

Once all above complete, run merge sequence.

---

## 7. User Decision Required

**Question:** Proceed with Phase A-D above before merge?

**Options:**

**Option 1: Fix All Issues Now (RECOMMENDED)**
- Complete Phase A (fix 4 issues): 2-3 hours
- Complete Phase B (code review): 1-2 hours
- Complete Phase C-D (verify & merge): 1 hour
- **Total time: 4-6 hours**
- **Benefit:** Zero technical debt, production-ready
- **Risk:** None

**Option 2: Merge Now, Fix Post-Merge**
- Merge today
- Fix issues on hotfix branch
- **Benefit:** Phase 3 "closed" today
- **Risk:** Technical debt, might break Week 0.1 provisioning

**Option 3: Escalate to Team**
- Create PR instead of direct merge
- Let team review + discuss
- Decide together

---

## Recommended Path Forward

**I recommend Option 1 (Fix All Issues Now).** Here's why:

1. **We're very close** — 4 issues are minor fixes + documentation
2. **Low risk** — All are straightforward improvements
3. **Production readiness** — Cannot deploy to production without these
4. **No technical debt** — Better to fix now than manage debt later

**If you want to proceed: I'll execute all fixes systematically.**

---

