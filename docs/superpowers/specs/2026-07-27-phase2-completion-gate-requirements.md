# Phase 2 EKS Platform Completion Gate Requirements

**Date:** 2026-07-27  
**Status:** Gate Definition (Pre-Merge)  
**Branch:** `feat/uat-access-foundation`  
**Commits:** 15 (Tasks 1-8 complete + rubrics + gate spec)  
**Execution Model:** Local admin validation (no remote CI/CD, no Pull Requests)

---

## Executive Summary

Phase 2 EKS Platform implementation is **functionally complete** (all 8 tasks committed, 177/177 unit tests passing locally). However, **static validation alone is insufficient** for infrastructure-as-code safety. This document formalizes the gate criteria required before merging to main or proceeding to Phase 3.

**Local Admin Validation Model:**
1. All testing and validation runs **on admin's local machine**
2. AWS credentials and sandbox account access **required locally**
3. Terraform backend bootstrap is **prerequisite before plan**
4. All 177 tests must pass **in local environment**
5. Terraform plan must succeed **against real sandbox AWS account**
6. Local merge to main is **authorized only after all gates pass**

**Corrected per Gatekeeper Critique:**
- ✅ **AWS Architect:** Live terraform plan now requires S3 backend bootstrap + terraform init (prerequisite)
- ✅ **DevOps:** Removed CI/CD pipeline requirement; strict local test discipline instead
- ✅ **System Architect:** Removed redundant `platform-contract-interface.md`; interface already locked in `outputs.tf`
- ✅ **Superpowers:** Local merge authorized via `finishing-a-development-branch` skill

---

## Gate Criteria (All Must Pass Locally)

### Gate 1: DevOps Architect — Local Test Discipline

**Requirement:** All 177 unit tests must pass in local environment, bash/python syntax must be valid.

**Validation Sequence:**

**(1a) Run unit test suite:**
```bash
cd /Users/frank/sml/oms/mongodb/.worktrees/uat-access-foundation
python3 -m unittest \
  tests.eks_platform.test_handlers \
  tests.eks_platform.test_verifiers \
  tests.eks_platform.test_documentation \
  tests.environment_orchestration.test_scope_registry -v
```
**Expected:** `Ran 177 tests in ~40s ... OK` ✅

**Failure:** If any test fails, stop and debug locally; re-run until all pass.

**(1b) Validate bash syntax:**
```bash
bash -n scripts/lib/scope-verifiers.d/20-eks-platform.sh
bash -n scripts/lib/scope-handlers.d/20-eks-platform.sh
bash -n scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh
bash -n scripts/lib/packages/20-eks-platform/internal/verifiers.sh
bash -n scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh
```
**Expected:** No errors

**(1c) Validate python syntax:**
```bash
python3 -m py_compile tests/eks_platform/test_handlers.py
python3 -m py_compile tests/eks_platform/test_verifiers.py
python3 -m py_compile tests/eks_platform/test_documentation.py
python3 -m py_compile tests/environment_orchestration/test_scope_registry.py
```
**Expected:** All files compile successfully

**Gate 1 Status:** ✅ PASS if all tests pass + all syntax valid

---

### Gate 2: AWS Architect — Live Terraform Plan (Sandbox)

**Requirement:** Terraform configuration must validate and plan successfully against a live AWS sandbox account.

**Prerequisites:**
- [ ] AWS CLI installed locally (`aws --version`)
- [ ] Terraform binary available (`terraform version`)
- [ ] Sandbox AWS Account ID identified
- [ ] Sandbox AWS region identified
- [ ] AWS credentials configured for sandbox account

**Validation Sequence:**

**(2a) Authenticate to sandbox AWS:**
```bash
export AWS_REGION="ap-east-1"              # Your sandbox region
export SANDBOX_ACCOUNT_ID="123456789012"   # Your sandbox account ID
export AWS_PROFILE="sandbox"                # Or use aws configure

# Verify credentials
aws sts get-caller-identity --profile sandbox
```
**Expected:** Output shows sandbox Account ID (not production)

**(2b) Bootstrap S3 backend (prerequisite):**
```bash
cd /Users/frank/sml/oms/mongodb/.worktrees/uat-access-foundation
bash scripts/bootstrap-terraform-s3-backend.sh
```
**Expected:** S3 bucket created, DynamoDB lock table created

**(2c) Initialize terraform:**
```bash
cd platform-prerequisites
terraform init -backend=true
```
**Expected:** Providers downloaded, modules initialized, backend configured

**(2d) Validate terraform syntax:**
```bash
terraform validate
```
**Expected:** `Success!` (0 errors)

**(2e) Check terraform formatting:**
```bash
terraform fmt -check
```
**Expected:** All files already formatted correctly

**(2f) Execute terraform plan:**
```bash
terraform plan -out=/tmp/phase2.tfplan
```
**Expected:** 0 errors, plan shows resources to be created

**Critical Checks in Plan Output:**
- ✅ EKS cluster ARN derivation is correct
- ✅ Workload identity root (IAM roles, OIDC) provisioning valid
- ✅ Platform controllers GitOps paths resolve
- ✅ EFS, Backup Vault, EKS deletion protection configurations valid
- ✅ No `InvalidParameterException`, `AccessDenied`, or `ThrottlingException` errors
- ✅ No region-specific quota warnings

**Gate 2 Status:** ✅ PASS if plan succeeds with 0 errors

---

### Gate 3: System Architect — platform_contract Output Lock

**Requirement:** The `platform_contract` outputs are locked in `outputs.tf` and documented in `eks-platform-contract.md`. This gate verifies the interface is immutable for Phase 3.

**Verification (Non-Executable):**

**(3a) Verify outputs.tf exists and is unchanged:**
```bash
cd /Users/frank/sml/oms/mongodb/.worktrees/uat-access-foundation

# List all outputs
cat platform-prerequisites/terraform/reusable/outputs.tf | grep 'output "'
```
**Expected:** Shows outputs (eks_cluster_name, eks_platform_identity, aws_region, etc.)

**(3b) Verify contract documentation:**
```bash
head -50 docs/references/eks-platform-contract.md
```
**Expected:** Shows contract header, ownership section, promotion modes, etc.

**(3c) Confirm no changes to outputs.tf since last commit:**
```bash
git diff HEAD~1 -- platform-prerequisites/terraform/reusable/outputs.tf
```
**Expected:** No changes (or only doc comments)

**Stability Rule (Locked):** Phase 2 outputs in `outputs.tf` are immutable for Phase 3. If Phase 3 requires additional data, Phase 2 must ADD new outputs (never remove or rename existing ones).

**Gate 3 Status:** ✅ PASS if outputs.tf is unchanged and contract is documented

---

### Gate 4: Superpowers — Sequential Local Merge Authorization

**Requirement:** All prior gates must pass before local merge is authorized. Merge is executed locally (not via PR/GitHub/etc.).

**Prerequisites:**
- [ ] Gate 1 status: PASS (177/177 tests, all syntax valid)
- [ ] Gate 2 status: PASS (terraform plan succeeds)
- [ ] Gate 3 status: PASS (outputs locked)
- [ ] Current branch: `feat/uat-access-foundation`
- [ ] Worktree is clean (no uncommitted changes beyond this gate spec)

**Merge Authorization:**

**(4a) Final pre-merge checklist:**
```
✅ Gate 1 (DevOps): 177/177 tests passing, syntax valid
✅ Gate 2 (AWS): Terraform plan succeeds against sandbox
✅ Gate 3 (System): platform_contract outputs locked
✅ All 15 commits are on feat/uat-access-foundation branch
```

**(4b) Execute local merge to main:**
```bash
cd /Users/frank/sml/oms/mongodb/.worktrees/uat-access-foundation

# Switch to main
git checkout main

# Merge with explicit merge commit (not fast-forward)
git merge feat/uat-access-foundation --no-ff -m "Merge Phase 2 EKS Platform (Tasks 1-8)

Phase 2 implementation complete:
  - Task 1-4: Infrastructure baseline + workload identity root
  - Task 5: Platform controllers GitOps delivery
  - Task 6: Canonical handler wrappers (provision/destroy)
  - Task 7: Canonical verifiers + pre-destroy guards + exactly-once callback
  - Task 8: Documentation contract + 34-test validation suite

All Gates Passed (Local Validation):
  - Unit tests: 177/177 passing (local environment)
  - Terraform: plan succeeds against sandbox AWS
  - Bash & Python: All syntax valid
  - platform_contract: Outputs locked, documented

Next: Phase 3 planning begins after worktree cleanup.

Closes #Phase2EksPlatform"
```
**Expected:** Merge commit created on main

**(4c) Verify merge succeeded:**
```bash
git log --oneline -5
```
**Expected:** Newest commit is "Merge Phase 2 EKS Platform (Tasks 1-8)"

**(4d) Clean up worktree:**
```bash
git worktree prune
```
**Expected:** Worktree references cleaned

**Gate 4 Status:** ✅ PASS if merge to main succeeds

---

## Success Criteria (Phase 2 Complete)

Phase 2 is **formally complete** when **ALL** of the following are true:

1. ✅ Gate 1 (DevOps): 177/177 tests passing locally
2. ✅ Gate 1 (DevOps): Bash + Python syntax valid
3. ✅ Gate 2 (AWS): Terraform plan succeeds against sandbox AWS
4. ✅ Gate 2 (AWS): Plan output shows 0 errors, all resources valid
5. ✅ Gate 3 (System): platform_contract outputs locked in outputs.tf
6. ✅ Gate 3 (System): Contract documentation present (eks-platform-contract.md)
7. ✅ Gate 4 (Superpowers): Merge commit recorded on main branch
8. ✅ Gate 4 (Superpowers): Worktree cleaned (git worktree prune)

**Only after all 8 criteria are met, Phase 3 planning can begin.**

---

## What Happens After All Gates Pass

**Post-Merge Sequence:**

1. **Verify main branch is current:**
   ```bash
   git checkout main
   git log --oneline -3
   # Confirm merge commit is at HEAD
   ```

2. **Invoke superpowers:finishing-a-development-branch skill:**
   - Document the Phase 2 completion
   - Record all gate results
   - Transition to Phase 3 readiness

3. **Wait 24 hours for emergency hotfixes:**
   - If any critical bug is found, patch on main
   - Do not start Phase 3 until main is stable

4. **Begin Phase 3 Planning:**
   - Invoke `superpowers:writing-plans` skill
   - Draft Phase 3 (MongoDB, PostgreSQL, SigNoz)
   - Define Tasks 1-6 for Phase 3

---

## Items Removed (Per Gatekeeper Critique)

**No Longer Required (Local Admin Model):**
- ❌ Pull Requests (GitHub, GitLab, Bitbucket)
- ❌ Remote CI/CD pipelines (GitHub Actions, GitLab CI, Jenkins)
- ❌ Peer review gates (assumed local admin has authority)
- ❌ Branch protection rules (local merge authorized by this spec)
- ❌ Redundant `platform-contract-interface.md` file (outputs.tf + contract sufficient)
- ❌ Cloud storage for test results (tests run locally, results printed to console)

**Rationale:** Local admin model assumes single trusted operator with:
- Repository write access
- AWS sandbox account credentials
- Decision authority for merge

---

## Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Terraform plan fails due to AWS API changes | HIGH | Execute plan immediately; document error; debug before merge |
| Sandbox AWS credentials are invalid | HIGH | Verify with `aws sts get-caller-identity` before plan |
| S3 backend bootstrap fails | MEDIUM | Check AWS permissions; verify S3 bucket doesn't already exist |
| Unit tests fail due to environment issues | MEDIUM | Run tests locally; confirm Python/pytest versions; check test isolation |
| platform_contract outputs modified | MEDIUM | Compare outputs.tf against previous commit; revert if changed |
| Local merge to main causes conflicts | MEDIUM | Ensure feat/uat-access-foundation is up-to-date with main first |
| Phase 3 planning begins before merge completes | CRITICAL | Enforce strict sequential execution; halt all Phase 3 work until merge verified |

---

## Final Checklist Before Merge

**Print this and check off each item:**

```
PRE-MERGE VERIFICATION
======================

[ ] AWS CLI configured and sandbox account verified
[ ] Terraform binary available (terraform version)
[ ] Python 3.7+ available (python3 --version)
[ ] Current branch is feat/uat-access-foundation
[ ] No uncommitted changes (git status --short)

GATE 1: LOCAL TESTS
===================

[ ] Unit tests: 177/177 passing
[ ] Bash syntax: All 5 files valid (bash -n)
[ ] Python syntax: All 4 test files compile

GATE 2: TERRAFORM PLAN
======================

[ ] AWS credentials authenticated (aws sts get-caller-identity)
[ ] S3 backend bootstrap completed
[ ] Terraform init succeeded
[ ] Terraform validate passed
[ ] Terraform format check passed
[ ] Terraform plan succeeded with 0 errors
[ ] Plan output shows expected resources
[ ] No AWS API errors in plan

GATE 3: OUTPUTS LOCK
====================

[ ] outputs.tf exists and is unchanged
[ ] Contract documentation present (eks-platform-contract.md)
[ ] No breaking changes to platform_contract

GATE 4: MERGE READY
===================

[ ] All prior gates passed (1, 2, 3)
[ ] Ready to checkout main
[ ] Ready to execute local merge
[ ] Ready to clean up worktree

MERGE AUTHORIZATION
===================

If ALL checkboxes above are checked ✅, then:
  git checkout main
  git merge feat/uat-access-foundation --no-ff -m "..."
  git worktree prune
```

---

## User Action Required

**This specification is complete and committed (commit: `a68bcfa`). You are ready to execute the gates.**

**Next Step:** Execute the four gates in sequence:

1. **Gate 1:** Run tests locally (`python3 -m unittest`)
2. **Gate 2:** Run terraform plan locally (requires sandbox AWS account)
3. **Gate 3:** Verify outputs.tf is unchanged
4. **Gate 4:** Merge to main locally

**When finished:** All 8 success criteria will be met, and Phase 2 will be formally merged into main. Phase 3 planning can then proceed.

---

## How to Get Help

If any gate fails:

1. **Gate 1 failure:** Check test error output; fix code; re-run tests
2. **Gate 2 failure:** Check terraform error; verify AWS credentials; check backend initialization
3. **Gate 3 failure:** Check if outputs.tf was modified; revert if needed
4. **Gate 4 failure:** Check git status; ensure clean worktree before merge

If terraform plan fails due to AWS infrastructure issues (missing VPC, IAM permissions, etc.), this indicates a prerequisite is missing in the sandbox AWS environment. Document the error and consult your AWS infrastructure team.

---

**Specification Ready for Execution**
