# Issue & PR Status Report - 2026-08-07

## PR → Issue Mapping & Review Order

### 🔄 Active PRs (Ready for Review/Merge)

| Order | PR | Closes Issue(s) | Status | Blocker | Review Priority |
|---|---|---|---|---|---|
| **1st** | **PR #76** | Issue #75 | ✅ Reviewed, Ready to Merge | ⚠️ Blocked on AWS org admin (real account IDs needed for deployment) | **MERGE FIRST** (base for #83, #84) |
| **2nd** | **PR #83** | Issue #79 | ✅ Reviewed, Ready to Merge | Depends on PR #76 merge (needs rebase to main) | MERGE SECOND |
| **3rd** | **PR #84** | Issue #78, Issue #80 | ✅ Reviewed, Ready to Merge | Depends on PR #76 merge (needs rebase to main) | MERGE THIRD |
| **4th** | **PR #77** | Issue #63 (already merged in prior session) | ⚠️ Test plan enhanced, needs testing | ⚠️ Cannot test (DEV cluster doesn't exist, UAT-only policy) | MERGE LAST (after testing decision) |

---

## Detailed PR Status

### PR #76: Cross-Account S3 Access (READY TO MERGE FIRST)
**Branch**: `feat/cross-account-s3-boomi-elt`  
**Closes**: Issue #75  
**Status**: ✅ **Reviewed and approved** by Claude  
**Size**: 2,845 additions, 213 deletions (14 files)

**What it does**:
- Terraform modules for cross-account S3 buckets (prod → UAT/DEV/SIT)
- Groovy library for Boomi ELT processes (AssumeRole with external IDs)
- **Consolidated documentation**:
  - `environment-reference.md` (14KB) - single source of truth for all environments
  - `aws-organization-requirements.md` (24KB) - IAM Identity Center + cross-account S3 policies
- Deleted redundant docs

**Deployment blocker**: ⚠️ **Waiting on AWS Organization administrator** to provide:
- Real AWS account IDs (currently uses placeholder env vars)
- Identity Center permission sets for UAT (4 permission sets, 5 users)
- Cross-account IAM roles per aws-organization-requirements.md

**Code status**: ✅ Ready to merge (Terraform/Groovy/docs all verified)  
**Deployment status**: 🚫 Cannot deploy until AWS org admin completes setup  

**Action for you**: 
1. **Review and approve PR #76** (code review)
2. **Merge PR #76 to main** (creates base docs for #83, #84)
3. **Then** coordinate with AWS org admin for deployment (separate from merge)

---

### PR #83: Namespace Naming Fix (READY TO MERGE SECOND)
**Branch**: `fix/issue-79-namespace-naming-consistency`  
**Closes**: Issue #79  
**Status**: ✅ **Reviewed and approved** by Claude  
**Size**: 5 additions, 1 deletion (1 file)

**What it does**:
- Fixes namespace table in `environment-reference.md`
- Clarifies DEV uses `mongodb` (legacy, no `-dev` suffix)
- Adds rationale for backward compatibility

**Dependency**: Must merge **after PR #76** (modifies file created by PR #76)  
**Current base**: `feat/cross-account-s3-boomi-elt` (will need rebase to main after #76 merges)

**Action for you**: 
1. Wait for PR #76 to merge
2. Rebase PR #83 to main: `git rebase main`
3. Review and approve PR #83
4. Merge PR #83 to main

---

### PR #84: Production 3-AZ Network (READY TO MERGE THIRD)
**Branch**: `feat/issue-78-production-3az-network`  
**Closes**: Issue #78, Issue #80  
**Status**: ✅ **Reviewed and approved** by Claude  
**Size**: 20 additions, 4 deletions (1 file)

**What it does**:
- Production: 3 AZs (AZ-a, AZ-b, AZ-c) instead of 2
  - MongoDB HA: 3-node replica set across 3 AZs (2/3 quorum survives 1 AZ loss)
- Right-sized subnets:
  - Public: `/26` (64 IPs per AZ) - saves 192 IPs per AZ vs. `/24`
  - Private: `/22` (1024 IPs per AZ) - doubles capacity vs. `/23`
  - DB: `/24` (256 IPs per AZ) - 3 AZs for Aurora
- Multiple SIT instances: SIT1, SIT2, SIT3 + reserved space

**CIDR math verified**: ✅ All subnets properly allocated, no overlaps

**Dependency**: Must merge **after PR #76** (modifies file created by PR #76)  
**Current base**: `feat/cross-account-s3-boomi-elt` (will need rebase to main after #76 merges)

**Action for you**: 
1. Wait for PR #76 to merge
2. Wait for PR #83 to merge (both modify same file)
3. Rebase PR #84 to main: `git rebase main`
4. Review and approve PR #84
5. Merge PR #84 to main

---

### PR #77: Destroy Operation Fixes (NEEDS TESTING DECISION)
**Branch**: `fix/issue-63-destroy-orphaned-resources`  
**Closes**: Issue #63 (closed in prior session, this is the fix)  
**Status**: ⚠️ **Test plan enhanced (10 test cases), but live testing blocked**  
**Size**: 2 files changed (destroy script + test plan)

**What it does**:
- Fixes orphaned Pod Identity associations during destroy
- Fixes stuck namespaces (CRD deletion order: CRs → operator → namespace)
- Adds AWS CLI cleanup for EKS Pod Identity associations

**Test plan status**:
- ✅ Core test cases (TC1-TC5): 30-45 minutes
- ✅ Enhanced test cases (TC6-TC10): 48-64 minutes (optional)
- ⚠️ **Cannot execute** - DEV cluster doesn't exist, UAT-only policy

**Testing blocker**: 
- DEV cluster (`oms-dev-eks-cluster`) doesn't exist in account `815402439714`
- Available clusters: `EKS-boomi-runtime-cluster`, `oms-test`
- UAT-only policy prevents provisioning DEV cluster

**Options to unblock**:
1. **Test in UAT** (requires UAT MongoDB to be provisioned first)
2. **Human manual testing in DEV** (you run test plan manually)
3. **Defer testing** until DEV cluster exists for other reasons
4. **Merge without live testing** (risky, not recommended)

**Action for you**: 
1. **Decide testing approach** (option 1, 2, 3, or 4 above)
2. If testing successful, review and approve PR #77
3. Merge PR #77 to main (independent of #76/#83/#84)

---

## Open Issues Status

### ✅ Issues with PRs Ready (Can Close After Merge)

| Issue | Status | Closing PR | Notes |
|---|---|---|---|
| **#75** | Open | PR #76 | Close after PR #76 merges |
| **#79** | Open | PR #83 | Close after PR #83 merges |
| **#78** | Open | PR #84 | Close after PR #84 merges |
| **#80** | Open | PR #84 | Close after PR #84 merges (same PR closes 2 issues) |

### ✅ Issues Completed (Can Close Now)

| Issue | Status | Closing PR/Event | Notes |
|---|---|---|---|
| **#81** | Open | Enhanced test plan complete (commit 5abf930 on PR #77) | ✅ **Can close now** - work complete, test cases added to TEST-PLAN-PR-77.md |

### 📋 Issues Without PRs (Documentation/Investigation Only)

| Issue | Type | Status | Action Needed |
|---|---|---|---|
| **#85** | Documentation | Just created today | 📝 Informational only - documents UAT-only safety rules (no PR needed) |
| **#82** | Investigation/Evaluation | Open | 📋 ArgoCD evaluation - phased approach, start after PRs merge |
| **#70** | Documentation | Open | 📝 FAQ entry needed - MongoDB anti-affinity for 2-node UAT cluster |
| **#69** | Documentation | Open | 📝 Troubleshooting guide needed - EKS node upgrades with PDBs |
| **#28** | Investigation/Validation | Open | 📋 User journey validation - scope UAT-only access |

---

## Recommended Review & Merge Order

### Phase 1: Documentation Foundation (No Blockers)
1. **Review PR #76** (cross-account S3 + consolidated docs)
   - Code review: Terraform, Groovy, documentation
   - Check: Environment account IDs, CIDR allocations, IAM policies
2. **Merge PR #76 to main**
   - Creates base documentation (`environment-reference.md`, `aws-organization-requirements.md`)
   - **Close Issue #75** after merge

### Phase 2: Documentation Refinements (Depends on PR #76)
3. **Rebase PR #83 to main** (after #76 merges)
4. **Review PR #83** (namespace naming fix)
5. **Merge PR #83 to main**
   - **Close Issue #79** after merge

6. **Rebase PR #84 to main** (after #76 and #83 merge)
7. **Review PR #84** (production 3-AZ network)
8. **Merge PR #84 to main**
   - **Close Issue #78** after merge
   - **Close Issue #80** after merge (same PR fixes both)

### Phase 3: Issue Cleanup (No Code Review Needed)
9. **Close Issue #81** (enhanced test plan)
   - Work complete: 5 test cases added to TEST-PLAN-PR-77.md
   - Commit: 5abf930 on PR #77 branch

### Phase 4: Destroy Fixes (Needs Testing Decision)
10. **Decide testing approach for PR #77**
    - Option A: Test in UAT (requires UAT MongoDB provisioned)
    - Option B: Manual testing by you in DEV
    - Option C: Defer until DEV cluster exists
11. **Review PR #77** (after testing complete or testing decision made)
12. **Merge PR #77 to main**
    - Issue #63 already closed (prior session)

---

## Summary for You

### Ready for Your Action Now:
1. ✅ **Close Issue #81** (work complete, no PR needed - test cases already added)
2. ✅ **Review & approve PR #76** (base documentation)
3. ✅ **Merge PR #76** (unblocks #83 and #84)

### After PR #76 Merges:
4. Rebase PR #83 to main
5. Review & merge PR #83 → Close Issue #79
6. Rebase PR #84 to main
7. Review & merge PR #84 → Close Issue #78, #80

### Needs Your Decision:
8. **PR #77 testing approach** (test in UAT / manual / defer)

### Documentation Issues (No Urgency):
- Issue #85 (UAT-only safety rules) - informational only
- Issue #82 (ArgoCD evaluation) - start after PRs merge
- Issue #70, #69, #28 (documentation tasks) - can be addressed anytime

---

**Bottom line**: You can merge 3 PRs (#76 → #83 → #84) and close 4 issues (#75, #79, #78, #80, #81) right now. PR #77 needs a testing decision first.
