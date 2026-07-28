# Phase 3 Task 7: Final Gatekeeper Sign-Off & Ready to Execute

**Date:** 2026-07-27  
**Status:** READY FOR EXECUTION  
**Decision:** All 4 perspectives CLEAR with 2 minor implementation clarifications  
**Branch:** `feat/phase3-workload-platforms`  
**Worktree:** `/Users/frank/sml/oms/mongodb/.worktrees/phase3-workload-platforms`

---

## Executive Summary

The **corrected subagent prompt** fixes the critical DevOps execution gap identified by the expert gatekeeper. All 4 perspectives now evaluate to **CLEAR**. Two minor implementation clarifications have been documented to ensure robust script creation. Ready to proceed with subagent execution.

---

## 4-Perspective Final Evaluation

### 1. AWS Architect Perspective: ✅ CLEAR

**Evaluation of Corrected Prompt:**

The addition of `scripts/create-signoz-clickhouse-secret.sh` creates no new AWS infrastructure concerns:
- Script is Kubernetes-native (bash + kubectl)
- No AWS IAM, KMS, S3, or other AWS service interactions
- Does not conflict with Phase 2 IRSA boundaries
- SigNoz remains Kubernetes-only; no AWS resources introduced

**Alignment with AWS Contract:**
- ✅ MongoDB contract correctly documents IRSA role, S3, KMS prerequisites
- ✅ PostgreSQL contract correctly documents IRSA role, S3, KMS prerequisites
- ✅ SigNoz contract explicitly states "No AWS prerequisites"
- ✅ Documentation tests encode AWS boundaries via assertions on `IRSA`, `KMS`, `S3` keywords

**Status:** **CLEAR** — No doubts, disagreements, missing cases, or areas to improve.

**AWS Architect Signature:** ✅ APPROVED

---

### 2. DevOps Perspective: ✅ YELLOW → CLEAR (FIXED)

**Original Concern (Identified by Expert DevOps Perspective):**

The initial execution plan's `git add docs/references/ tests/` would **fail Gate 4** (git status clean) if the subagent created `scripts/create-signoz-clickhouse-secret.sh` but didn't stage it. This was a critical execution gap.

**Corrected Prompt Fixes This:**

The corrected subagent prompt now explicitly:
```bash
git add docs/references/ tests/ scripts/create-signoz-clickhouse-secret.sh
```

This ensures:
- ✅ The missing bootstrap script is created
- ✅ The script is executable (`chmod +x`)
- ✅ The script is staged before the commit
- ✅ Gate 4 (git status clean) will pass

**Verification of Script Requirements:**

The corrected prompt directs:
> "It must be idempotent, accept a password via env var or argument, create the `signoz-clickhouse` secret in the `signoz` namespace with key `password`, and be executable (`chmod +x`)."

**Implementation Clarity (Minor Additions for Robustness):**

Two implementation details should be locked to ensure consistency:

1. **Environment Variable Name:** The prompt should specify:
   - Primary input: `CLICKHOUSE_ROOT_PASSWORD` environment variable
   - Fallback: If not provided, generate a secure password (similar to `create-signoz-root-user-secret.sh`)
   - Minimum requirements: ≥12 characters, no special restrictions (unlike SigNoz admin password)

2. **Script Pattern:** The script should follow the existing bootstrap script pattern:
   - Model: `scripts/create-signoz-root-user-secret.sh` (idempotent, accepts args, stores credentials in `.local-dev-user-passwords.txt`)
   - Check if secret exists: `kubectl -n signoz get secret signoz-clickhouse 2>/dev/null` → skip if exists (idempotent)
   - Create if missing: `kubectl -n signoz create secret generic signoz-clickhouse --from-literal=password="$PASSWORD"`
   - Log result to `.local-dev-user-passwords.txt` for operator reference

**Validation in Tests:**

The SigNoz documentation tests will verify:
- ✅ Prerequisites mentions "create-signoz-clickhouse-secret.sh"
- ✅ Prerequisites contains "CLICKHOUSE_ROOT_PASSWORD"
- ✅ Test can run: `bash scripts/create-signoz-clickhouse-secret.sh --help` (script exists and is executable)

**Status:** **CLEAR** — The corrected prompt resolves the original DevOps concern. Script creation is explicitly mandated and staged in the atomic commit.

**DevOps Architect Signature:** ✅ APPROVED

---

### 3. Software Architect Perspective: ✅ CLEAR

**Evaluation of Documentation Testing Strategy:**

The corrected prompt maintains the shift from structural testing (header existence) to semantic testing (content quality assertions):

**Test Coverage:**
- ✅ Files exist (basic sanity)
- ✅ Required sections exist (structure)
- ✅ Sections contain keywords (semantic validation):
  - MongoDB/PostgreSQL: `IRSA`, `KMS`, `S3`, `operator_iam_role_arn`
  - SigNoz: `signoz-clickhouse`, `create-signoz-clickhouse-secret.sh`, `CLICKHOUSE_ROOT_PASSWORD`
  - All: `pre-destroy`, `validate`, `SHA-256`, `replica set`/`ClickHouse`

**Minor Edge Case Noted (Addressed):**

The provided test code uses:
```python
prerequisites = content.split("## Prerequisites")[1].split("##")[0]
```

This throws `IndexError` if the target section is the **last** section in the file.

**Mitigation:**
- Each contract template ends with `## Configuration Reference` (prerequisites is NOT last) ✓
- The subagent can write robust parsing using regex or `str.find()` if it encounters edge cases during testing
- Tests are TDD-driven, so parsing robustness will be validated on first execution

**Atomic Commit Constraint Check:**

Adding a bash script to the commit (alongside docs + tests) does **not** violate atomic commit principles:
- Single logical change: "Add platform contracts, tests, and missing bootstrap script"
- All 3 file types serve the same purpose: Complete Phase 3 contract + deployment readiness
- No partial implementations: Script is complete, not a stub

**Status:** **CLEAR** — Test strategy is sound. Edge case is mitigated by contract structure. Atomic commit boundary is valid.

**Software Architect Signature:** ✅ APPROVED

---

### 4. Superpowers Creator Perspective: ✅ CLEAR

**Evaluation of Superpowers Process Alignment:**

**Atomic Commit Invariant (from finishing-a-development-branch skill):**
- ✅ Single logical unit: Contract docs + tests + bootstrap script
- ✅ All files are complete, not stubs or placeholders
- ✅ No partial implementations
- ✅ All validation gates must pass before commit
- ✅ Commit message is clear and structured

**Task Scope Boundary:**
- ✅ Task 7 ONLY: No Task 8 work, no merge logic
- ✅ Subagent execution stops after atomic commit
- ✅ Manual gatekeeper review is post-execution (not part of Task 7)

**Corrected Prompt Alignment:**
- ✅ Explicitly mandates script creation (fixes DevOps gap)
- ✅ Explicitly mandates 4 gates with expected pass counts
- ✅ Explicitly prohibits merge: "Do NOT execute the merge to main"
- ✅ Atomic commit is clearly defined with all 3 file types staged

**What We Should Do Next:**
1. **Lock this design** (document approved by all 4 gatekeepers)
2. **Dispatch the corrected subagent** with explicit execution prompt
3. **Await subagent results** (gates passing, commit successful)
4. **Execute post-Task 7 manual review** by AWS Architect + DevOps + Software Architect
5. **Merge to main** only after all reviews approve

**How We Should Do That:**
- Document this sign-off as final gatekeeper approval
- Copy the corrected prompt exactly as provided by user
- Execute it directly into VSCode Copilot as a subagent invocation
- Wait for completion and report results
- Proceed to manual review phase (separate step)

**Superpowers Skill Alignment:**
- ✅ `finishing-a-development-branch`: Task 7 is final implementation task before completion gates
- ✅ `subagent-driven-development`: Subagent execution with clear scope and atomic commit boundary
- ✅ Atomic Commit Invariant: No partial implementations, all gates must pass

**Status:** **CLEAR** — Process is aligned with superpowers skills. Ready to proceed.

**Superpowers Creator Signature:** ✅ APPROVED

---

## Final Implementation Requirements (Locked)

### Requirement 1: Bootstrap Script Pattern

**File:** `scripts/create-signoz-clickhouse-secret.sh`

**Must Include:**
1. **Shebang & Options:** `#!/usr/bin/env bash` + `set -euo pipefail`
2. **Idempotency:** Check if secret already exists before creating
   ```bash
   kubectl -n signoz get secret signoz-clickhouse >/dev/null 2>&1 && { echo "Secret already exists"; exit 0; }
   ```
3. **Password Input:** Accept via environment variable or argument
   - Primary: `CLICKHOUSE_ROOT_PASSWORD` environment variable
   - Fallback: Generate secure password if not provided
   - Minimum: 12 characters
4. **Secret Creation:** 
   ```bash
   kubectl -n signoz create secret generic signoz-clickhouse \
     --from-literal=password="$PASSWORD"
   ```
5. **Optional:** Log credentials to `.local-dev-user-passwords.txt` (like existing bootstrap scripts)
6. **Executable:** `chmod +x scripts/create-signoz-clickhouse-secret.sh`

**Validation:** SigNoz documentation tests will verify script exists and is executable.

---

### Requirement 2: Contract Document Sections

**All 3 Contracts (MongoDB, PostgreSQL, SigNoz) Must Include:**

1. ✅ `## Ownership & Maintenance`
2. ✅ `## Lifecycle` (with ### Provisioning and ### Destruction subsections)
3. ✅ `## Identities` (with IRSA/IAM for MongoDB/PostgreSQL; Kubernetes Secrets for SigNoz)
4. ✅ `## Guard Semantics` (with 7-step protocol: Seam Read, Parse, Validate, Identity, SHA-256, Callback, Return)
5. ✅ `## Prerequisites` (AWS + Kubernetes + Operator)
6. ✅ `## Service Dependencies`
7. ✅ `## Configuration Reference`

**SigNoz Contract MUST ALSO Include:**
- ✅ Explicit statement: "No AWS prerequisites"
- ✅ Explicit requirement: "`signoz-clickhouse` Secret must be created before deployment"
- ✅ Reference: "Run `bash scripts/create-signoz-clickhouse-secret.sh`"
- ✅ Link: To actual bootstrap script in Prerequisites section

---

### Requirement 3: Documentation Tests

**All 3 Test Modules Must Verify:**

1. ✅ Contract file exists
2. ✅ All required sections exist
3. ✅ Sections contain required keywords:
   - MongoDB/PostgreSQL: `IRSA`, `KMS`, `S3`, `operator_iam_role_arn`, `pre-destroy`, `validate`, `SHA-256`
   - SigNoz: `signoz-clickhouse`, `create-signoz-clickhouse-secret.sh`, `CLICKHOUSE_ROOT_PASSWORD`, `pre-destroy`, `validate`, `SHA-256`

**Robust Parsing:**
- Use regex or `str.find()` to extract sections (avoid fragile string splitting if edge case occurs)
- Wrap in try/except if parsing fails to provide helpful error messages

---

### Requirement 4: Phase 3 Final Gates

**Gate 1 (All Tests):**
```bash
python3 -m unittest discover -s tests -p "test_*.py" -v
# Expected: 132+ tests PASS
# Includes: 123 (Tasks 1-6) + ~9 new documentation tests
```

**Gate 2 (Terraform Validation):**
```bash
cd platform-prerequisites/terraform/mongodb
terraform fmt -check && terraform validate

cd ../postgresql
terraform fmt -check && terraform validate
# Expected: All PASS
```

**Gate 3 (GitOps Builds):**
```bash
kustomize build gitops/mongodb/overlays/uat > /dev/null
kustomize build gitops/postgresql/overlays/uat > /dev/null
kustomize build gitops/signoz/overlays/uat > /dev/null
# Expected: All PASS
```

**Gate 4 (Git Status):**
```bash
git status --porcelain | wc -l
# Expected: 0 (everything staged and committed)
```

---

### Requirement 5: Atomic Commit

```bash
git add docs/references/mongodb-platform-contract.md \
        docs/references/postgresql-platform-contract.md \
        docs/references/signoz-platform-contract.md \
        tests/mongodb/test_documentation.py \
        tests/postgresql/test_documentation.py \
        tests/signoz/test_documentation.py \
        scripts/create-signoz-clickhouse-secret.sh

git commit -m "docs(phase3): add platform contracts, documentation tests, and missing bootstrap script

- Add: scripts/create-signoz-clickhouse-secret.sh (idempotent, creates signoz-clickhouse Secret)
- Add: mongodb-platform-contract.md (Ownership, Lifecycle, Identities, Guard Semantics, Prerequisites)
- Add: postgresql-platform-contract.md (Ownership, Lifecycle, Identities, Guard Semantics, Prerequisites)
- Add: signoz-platform-contract.md (Ownership, Lifecycle, Kubernetes Secrets, Guard Semantics, ClickHouse bootstrap prerequisites)
- Add: test_documentation.py for each platform (verify sections exist + content quality via keyword assertions)
- Passed all Phase 3 final validation gates:
  * Gate 1: 132+ tests PASS
  * Gate 2: Terraform fmt & validate PASS
  * Gate 3: Kustomize builds PASS
  * Gate 4: Git status CLEAN

Phase 3 Task 7 COMPLETE. Ready for manual gatekeeper review before merge to main."
```

**Important:** Do NOT merge to main. Stop after commit.

---

## Post-Task 7: Manual Gatekeeper Review (After Subagent Execution)

**Only proceed to merge after:**

1. **AWS Architect Review:**
   - [ ] Prerequisites docs accurately reference Phase 2 IRSA roles
   - [ ] KMS key identifiers are correct
   - [ ] S3 bucket names are correct
   - [ ] SigNoz contract correctly states "No AWS prerequisites"

2. **DevOps Review:**
   - [ ] ClickHouse secret bootstrap script exists and is executable
   - [ ] Script is idempotent (checks for existing secret first)
   - [ ] Documentation clearly explains secret creation steps
   - [ ] Tests verify script requirement in prerequisites section

3. **Software Architect Review:**
   - [ ] All contract sections are complete and accurate
   - [ ] Guard Semantics describes 7-step protocol clearly
   - [ ] Tests verify content quality, not just structure
   - [ ] Contracts are consistent across all 3 components

4. **All Gatekeepers:**
   - [ ] Atomic commit is self-contained
   - [ ] All 132+ tests pass
   - [ ] No partial implementations
   - [ ] Working tree is clean

**Merge Decision:**
- ✅ **IF all reviews APPROVED:** Proceed with `git merge main`
- ❌ **IF any review REQUEST CHANGES:** Document feedback and return to implementation

---

## Gatekeeper Sign-Off (All Perspectives)

| Perspective | Status | Reviewed By | Date | Signature |
|---|---|---|---|---|
| AWS Architect | ✅ CLEAR | Expert AWS Architect | 2026-07-27 | ✅ APPROVED |
| DevOps | ✅ CLEAR | Expert DevOps Perspective | 2026-07-27 | ✅ APPROVED |
| Software Architect | ✅ CLEAR | Expert Software Architect | 2026-07-27 | ✅ APPROVED |
| Superpowers Creator | ✅ CLEAR | Expert Superpowers Creator | 2026-07-27 | ✅ APPROVED |

---

## Final Decision: READY TO EXECUTE

**Status:** ✅ **ALL 4 GATEKEEPERS CLEAR**

**Next Step:** Execute the corrected subagent prompt provided by the expert gatekeepers.

**Subagent Prompt to Use:** [Exactly as provided in the user's gatekeeper evaluation]

**Expected Outcome:**
- All 4 gates pass
- Atomic commit created with all 7 files (3 contracts + 3 test modules + 1 bootstrap script)
- Working tree clean
- Subagent reports "Task 7 COMPLETE"

**Then:** Proceed to post-Task 7 manual gatekeeper review before merge to main.

---

## Summary

The **corrected subagent prompt** successfully:
1. ✅ Fixes the critical DevOps gap (script creation + staging)
2. ✅ Maintains atomic commit boundary (docs + tests + scripts as single unit)
3. ✅ Aligns with all superpowers skills
4. ✅ Passes all 4-perspective gatekeeper evaluation
5. ✅ Is ready for immediate execution

**No further design work required. Proceed to subagent execution.**
