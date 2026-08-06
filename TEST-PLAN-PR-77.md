# Test Plan: PR #77 - Destroy Operation Fixes

**PR**: #77  
**Issue**: #63  
**Date**: 2026-08-07  
**Tester**: Infrastructure Operator

## Overview

This test plan validates that PR #77 correctly fixes both orphaned resource problems reported in issue #63:
1. Pod Identity associations are cleaned up during destroy
2. Percona CRD finalizers don't block namespace deletion

## Prerequisites

- AWS CLI configured with credentials for the target environment
- kubectl configured with access to the EKS cluster
- MongoDB provisioned and healthy (`bash scripts/provision.sh mongodb --auto-approve`)

## Test Scope

**In-scope:**
- MongoDB destroy operation completes without manual intervention
- Pod Identity associations are deleted
- Namespace deletion completes (not stuck in `Terminating`)
- No orphaned AWS resources remain

**Out-of-scope:**
- PostgreSQL destroy (separate scope)
- SigNoz destroy (separate scope)
- Production environment testing (test in DEV only)

---

## Test Case 1: Pod Identity Association Cleanup

**Objective**: Verify Pod Identity associations are deleted during mongodb destroy.

### Pre-Conditions
1. MongoDB provisioned: `bash scripts/provision.sh mongodb --auto-approve`
2. Verify Pod Identity associations exist:
   ```bash
   aws eks list-pod-identity-associations \
     --cluster-name oms-dev-eks-cluster \
     --region ap-east-1 \
     --query "associations[?namespace=='mongodb']"
   ```
   **Expected**: Should return at least one association

### Test Steps
1. Run destroy:
   ```bash
   bash scripts/destroy.sh mongodb
   # Type "DESTROY" when prompted
   ```

2. Wait for destroy to complete (should take 2-5 minutes)

3. Check Pod Identity associations:
   ```bash
   aws eks list-pod-identity-associations \
     --cluster-name oms-dev-eks-cluster \
     --region ap-east-1 \
     --query "associations[?namespace=='mongodb']"
   ```

### Expected Results
- ✅ Destroy script completes without errors
- ✅ Console output shows: "Cleaning up EKS Pod Identity associations for mongodb namespace..."
- ✅ Console output shows: "Found Pod Identity associations to delete: <id>"
- ✅ Console output shows: "Deleting Pod Identity association: <id>"
- ✅ `aws eks list-pod-identity-associations` returns empty array: `{"associations": []}`
- ✅ **NO MANUAL CLEANUP REQUIRED**

### Pass/Fail Criteria
**PASS** if:
- Destroy completes successfully
- All Pod Identity associations for `mongodb` namespace are deleted
- No manual `aws eks delete-pod-identity-association` commands needed

**FAIL** if:
- Pod Identity associations remain after destroy
- Manual cleanup is required

---

## Test Case 2: CRD Finalizer Ordering (Namespace Deletion)

**Objective**: Verify namespace doesn't get stuck in `Terminating` due to CRD finalizers.

### Pre-Conditions
1. MongoDB provisioned with at least one backup CR:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   # Wait for MongoDB to be healthy
   kubectl -n mongodb get perconaservermongodbbackup
   ```
   **Expected**: Should show at least one `PerconaServerMongoDBBackup` CR (cron backup)

2. Verify operator is running:
   ```bash
   kubectl -n mongodb get pod -l app.kubernetes.io/name=percona-server-mongodb-operator
   ```
   **Expected**: Operator pod in `Running` state

### Test Steps
1. Run destroy:
   ```bash
   bash scripts/destroy.sh mongodb
   # Type "DESTROY" when prompted
   ```

2. Monitor console output for deletion order

3. Check namespace status immediately after destroy completes:
   ```bash
   kubectl get namespace mongodb
   ```

4. If namespace still exists, wait 30 seconds and check again

5. Verify no stuck CRD resources:
   ```bash
   kubectl -n mongodb get perconaservermongodbbackup
   kubectl -n mongodb get perconaservermongodb
   ```

### Expected Results
- ✅ Console shows deletion order:
  1. "Deleting PerconaServerMongoDBBackup CRs (backup finalizers need operator running)..."
  2. "Deleting PerconaServerMongoDB CR (PSMDB finalizers need operator running)..."
  3. "Deleting Percona operator HelmRelease..."
- ✅ Namespace deletes within 60 seconds
- ✅ `kubectl get namespace mongodb` returns: `Error from server (NotFound): namespaces "mongodb" not found`
- ✅ **NO STUCK NAMESPACE** (not in `Terminating` state for >2 minutes)
- ✅ **NO MANUAL FINALIZER REMOVAL REQUIRED**

### Pass/Fail Criteria
**PASS** if:
- Namespace deletes successfully
- No CRD resources remain
- No manual `kubectl patch` commands needed to remove finalizers

**FAIL** if:
- Namespace stuck in `Terminating` state for >2 minutes
- CRD resources remain with finalizers
- Manual `kubectl patch` commands are required

---

## Test Case 3: End-to-End Provision → Destroy → Re-provision

**Objective**: Verify complete cleanup allows clean re-provisioning.

### Test Steps
1. **First provision:**
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   ```
   **Expected**: Succeeds

2. **Destroy:**
   ```bash
   bash scripts/destroy.sh mongodb
   # Type "DESTROY"
   ```
   **Expected**: Succeeds (both TC1 and TC2 pass)

3. **Verify complete cleanup:**
   ```bash
   # No namespace
   kubectl get namespace mongodb
   # Expected: NotFound

   # No Pod Identity associations
   aws eks list-pod-identity-associations \
     --cluster-name oms-dev-eks-cluster \
     --region ap-east-1 \
     --query "associations[?namespace=='mongodb']"
   # Expected: {"associations": []}

   # No PVCs (should be Released, not Bound)
   kubectl get pvc --all-namespaces | grep mongodb
   # Expected: No results OR PVCs in Released state
   ```

4. **Re-provision:**
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   ```

5. **Verify health:**
   ```bash
   kubectl -n mongodb get pod
   kubectl -n mongodb get perconaservermongodb psmdb
   ```

### Expected Results
- ✅ First provision succeeds
- ✅ Destroy completes without manual intervention (TC1 + TC2 pass)
- ✅ Complete cleanup verified (no orphans)
- ✅ Re-provision succeeds without conflicts
- ✅ Re-provisioned MongoDB is healthy

### Pass/Fail Criteria
**PASS** if:
- Complete cycle (provision → destroy → re-provision) succeeds
- No manual cleanup steps required
- Re-provisioned MongoDB is healthy

**FAIL** if:
- Re-provision fails due to leftover resources
- Manual cleanup is needed between destroy and re-provision

---

## Test Case 4: Backward Compatibility (DEV Legacy Path)

**Objective**: Verify fix works with both legacy and unified provisioning paths.

### Test Steps
1. **Provision via legacy path (no --env flag):**
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   ```

2. **Destroy via legacy path (no --env flag):**
   ```bash
   bash scripts/destroy.sh mongodb
   # Type "DESTROY"
   ```

3. **Verify cleanup** (same as TC3 step 3)

### Expected Results
- ✅ Legacy path destroy works (calls `scripts/legacy/dev/destroy.sh` internally)
- ✅ Both TC1 and TC2 pass
- ✅ Complete cleanup verified

### Pass/Fail Criteria
**PASS** if:
- Legacy destroy path correctly invokes updated `destroy_mongodb_k8s()` function
- All cleanup steps execute successfully

**FAIL** if:
- Legacy path doesn't pick up the fix
- Different behavior between legacy and unified paths

---

## Test Case 5: Error Handling (AWS CLI Missing)

**Objective**: Verify graceful degradation if AWS CLI is unavailable.

### Test Steps
1. **Temporarily hide AWS CLI:**
   ```bash
   alias aws='echo "aws: command not found" >&2; false'
   ```

2. **Run destroy:**
   ```bash
   bash scripts/destroy.sh mongodb
   # Type "DESTROY"
   ```

3. **Check console output**

4. **Restore AWS CLI:**
   ```bash
   unalias aws
   ```

### Expected Results
- ✅ Destroy doesn't fail completely
- ✅ Console shows: "Warning: aws CLI not found, skipping Pod Identity association cleanup"
- ✅ Console shows manual cleanup instructions
- ✅ Kubernetes resources still delete successfully
- ⚠️ Pod Identity associations remain (expected behavior - manual cleanup needed)

### Pass/Fail Criteria
**PASS** if:
- Script doesn't crash when AWS CLI is missing
- Warning message is clear
- Kubernetes cleanup still works

**FAIL** if:
- Script crashes or exits with error
- No warning message shown
- Kubernetes cleanup fails

---

## Test Environment

**Cluster**: `oms-dev-eks-cluster` (DEV environment)  
**Region**: `ap-east-1`  
**AWS Account**: `815402439714` (DEV)  
**Namespace**: `mongodb` (legacy naming, no `-dev` suffix)

---

## Test Execution Record

| Test Case | Date | Tester | Result | Notes |
|-----------|------|--------|--------|-------|
| TC1: Pod Identity Cleanup | YYYY-MM-DD | | ⬜ PENDING | |
| TC2: CRD Finalizer Ordering | YYYY-MM-DD | | ⬜ PENDING | |
| TC3: End-to-End Cycle | YYYY-MM-DD | | ⬜ PENDING | |
| TC4: Backward Compatibility | YYYY-MM-DD | | ⬜ PENDING | |
| TC5: Error Handling | YYYY-MM-DD | | ⬜ PENDING | |

---

## Rollback Plan

If tests fail, rollback to previous version:

```bash
# Revert the fix
git checkout main
git checkout scripts/legacy/dev/destroy.sh

# Or restore from backup
cp scripts/legacy/dev/destroy.sh.backup scripts/legacy/dev/destroy.sh
```

Manual cleanup will be required (see issue #63 for procedures).

---

## Sign-Off

**Tested By**: _________________  
**Date**: _________________  
**Result**: ☐ PASS  ☐ FAIL  ☐ CONDITIONAL PASS (see notes)  
**Notes**: 

_______________________________________________________________________

_______________________________________________________________________

_______________________________________________________________________

**Approved for Merge**: ☐ YES  ☐ NO  
**Approver**: _________________  
**Date**: _________________
