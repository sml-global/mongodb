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

## Test Case 6: Node Downscale During MongoDB Operation

**Objective**: Verify Pod Identity associations are cleaned up when nodes are scaled down before destroy.

**Why this matters**: When a node is removed, its Pod Identity association may remain in AWS even though the pod moved to another node. This can create orphaned associations.

### Pre-Conditions
1. MongoDB provisioned and healthy:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   kubectl -n mongodb get pod -o wide  # Note which nodes pods are on
   ```
2. EKS node group has 3 nodes:
   ```bash
   kubectl get nodes
   ```

### Test Steps

**Step 1**: Verify Pod Identity associations exist
```bash
aws eks list-pod-identity-associations \
  --cluster-name oms-dev-eks-cluster \
  --region ap-east-1 \
  --query "associations[?namespace=='mongodb'].[associationId,serviceAccount]" \
  --output table
```
**Expected**: 1 association for `psmdb-db` ServiceAccount

**Step 2**: Scale down node group to 2 nodes
```bash
# Get node group name
aws eks list-nodegroups --cluster-name oms-dev-eks-cluster --region ap-east-1

# Scale down (adjust desired/min counts)
aws eks update-nodegroup-config \
  --cluster-name oms-dev-eks-cluster \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 \
  --region ap-east-1
```

**Step 3**: Wait for node to be removed and pods to reschedule
```bash
# Watch nodes
kubectl get nodes -w

# In another terminal, watch pods reschedule
kubectl -n mongodb get pod -o wide -w
```
**Expected**: One node terminates, MongoDB pods reschedule to remaining 2 nodes

**Step 4**: Check for orphaned associations
```bash
aws eks list-pod-identity-associations \
  --cluster-name oms-dev-eks-cluster \
  --region ap-east-1 \
  --query "associations[?namespace=='mongodb'].[associationId,serviceAccount]" \
  --output table
```
**Possible**: May show multiple associations if rescheduling created new ones

**Step 5**: Run destroy
```bash
bash scripts/destroy.sh mongodb
# Type "DESTROY"
```

**Step 6**: Verify all associations cleaned up
```bash
aws eks list-pod-identity-associations \
  --cluster-name oms-dev-eks-cluster \
  --region ap-east-1 \
  --query "associations[?namespace=='mongodb']"
```
**Expected**: `{"associations": []}` (all cleaned up, including orphaned ones)

### Expected Results
- ✅ Destroy completes successfully
- ✅ All Pod Identity associations deleted (including any orphaned during node scale-down)
- ✅ Namespace deletes cleanly
- ✅ No manual cleanup required

### Pass/Fail Criteria
**PASS** if all associations are cleaned up  
**FAIL** if orphaned associations remain after destroy

**Estimated Time**: 15-20 minutes (including node scale-down wait time)

---

## Test Case 7: Node Upscale Before Destroy

**Objective**: Verify cleanup works when there are multiple Pod Identity associations (more than initial count).

**Why this matters**: Multiple associations can exist if pods were rescheduled across nodes multiple times.

### Pre-Conditions
1. MongoDB provisioned with default node count:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   kubectl get nodes  # Note initial count (e.g., 2 nodes)
   ```

### Test Steps

**Step 1**: Scale up node group to 4 nodes
```bash
# Get node group name
aws eks list-nodegroups --cluster-name oms-dev-eks-cluster --region ap-east-1

# Scale up
aws eks update-nodegroup-config \
  --cluster-name oms-dev-eks-cluster \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=4,maxSize=6,desiredSize=4 \
  --region ap-east-1
```

**Step 2**: Wait for new nodes to be ready
```bash
kubectl get nodes -w
```
**Expected**: 4 nodes total in `Ready` state

**Step 3**: Trigger MongoDB pod rescheduling (rolling restart)
```bash
kubectl -n mongodb rollout restart statefulset/psmdb-rs0
kubectl -n mongodb rollout status statefulset/psmdb-rs0
```
**Expected**: Pods restart and may be scheduled on new nodes

**Step 4**: Check Pod Identity associations
```bash
aws eks list-pod-identity-associations \
  --cluster-name oms-dev-eks-cluster \
  --region ap-east-1 \
  --query "associations[?namespace=='mongodb'].[associationId,serviceAccount]" \
  --output table
```
**Possible**: May show multiple associations from rescheduling

**Step 5**: Run destroy
```bash
bash scripts/destroy.sh mongodb
# Type "DESTROY"
```

**Step 6**: Verify all associations cleaned up
```bash
aws eks list-pod-identity-associations \
  --cluster-name oms-dev-eks-cluster \
  --region ap-east-1 \
  --query "associations[?namespace=='mongodb']"
```
**Expected**: `{"associations": []}` (all cleaned up)

### Expected Results
- ✅ Destroy completes successfully
- ✅ All Pod Identity associations deleted (including extras from rescheduling)
- ✅ No manual cleanup required

### Pass/Fail Criteria
**PASS** if all associations are cleaned up  
**FAIL** if any associations remain after destroy

**Estimated Time**: 15-20 minutes (including node scale-up + rolling restart)

---

## Test Case 8: PodDisruptionBudget During Destroy

**Objective**: Verify destroy handles PDBs gracefully (doesn't hang forever waiting for pod eviction).

**Why this matters**: PDBs can prevent pod eviction, which can cascade into stuck namespace deletion if not handled correctly.

### Pre-Conditions
1. MongoDB provisioned with PodDisruptionBudget:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   kubectl -n mongodb get pdb  # Verify PDB exists
   ```

### Test Steps

**Step 1**: Verify PDB is active
```bash
kubectl -n mongodb get pdb -o yaml
```
**Expected**: PDB with `minAvailable: 2` (or similar constraint)

**Step 2**: Run destroy while MongoDB is healthy
```bash
bash scripts/destroy.sh mongodb
# Type "DESTROY"
```

**Step 3**: Monitor destroy progress (with timer)
```bash
# In another terminal
time kubectl -n mongodb get pod -w
```

**Step 4**: Check namespace status after destroy completes
```bash
kubectl get namespace mongodb
```

### Expected Results
- ✅ Destroy completes within 5 minutes (not hanging indefinitely)
- ✅ Console shows CRD deletion order (CRs → operator → namespace)
- ✅ Namespace deletes successfully
- ✅ PDB does not block namespace deletion

### Pass/Fail Criteria
**PASS** if destroy completes in <5 minutes without manual intervention  
**FAIL** if destroy hangs >5 minutes waiting for voluntary pod eviction

**Estimated Time**: 5-7 minutes

---

## Test Case 9: Destroy During MongoDB Rolling Restart

**Objective**: Verify destroy is safe even when MongoDB StatefulSet is in flux.

**Why this matters**: Real-world destroys may happen during maintenance windows when pods are already in flux.

### Pre-Conditions
1. MongoDB provisioned and healthy:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   ```

### Test Steps

**Step 1**: Trigger rolling restart
```bash
# Change MongoDB config or image to trigger restart
kubectl -n mongodb patch perconaservermongodb psmdb --type=merge -p '{"spec":{"image":"percona/percona-server-mongodb:7.0.8-5"}}'
```

**Step 2**: Immediately check pod status (restart should be starting)
```bash
kubectl -n mongodb get pod -w
```
**Expected**: Some pods in `Terminating`, some in `Running`, some in `ContainerCreating`

**Step 3**: Run destroy while restart is in progress
```bash
# Open new terminal
bash scripts/destroy.sh mongodb
# Type "DESTROY"
```

**Step 4**: Monitor destroy progress
```bash
# Watch console output for deletion order
# Watch pods: kubectl -n mongodb get pod -w
```

### Expected Results
- ✅ Destroy completes successfully (doesn't fail due to in-flux pods)
- ✅ Console shows CRD deletion order (CRs → operator → namespace)
- ✅ No stuck pods in `Terminating` state
- ✅ All resources cleaned up

### Pass/Fail Criteria
**PASS** if destroy completes successfully despite in-flux StatefulSet  
**FAIL** if destroy hangs or leaves resources in stuck state

**Estimated Time**: 8-10 minutes

---

## Test Case 10: Destroy with Failed Pods (Crash Loop)

**Objective**: Verify destroy works even when MongoDB pods are failing.

**Why this matters**: Destroy is often used to recover from failed deployments.

### Pre-Conditions
1. MongoDB provisioned:
   ```bash
   bash scripts/provision.sh mongodb --auto-approve
   ```

### Test Steps

**Step 1**: Break MongoDB configuration to trigger crash loop
```bash
# Corrupt the MongoDB secret (break the connection string)
kubectl -n mongodb patch secret psmdb-secrets --type=json -p='[{"op": "replace", "path": "/data/MONGODB_DATABASE_ADMIN_PASSWORD", "value": "aW52YWxpZA=="}]'

# Delete pods to force re-read of corrupted secret
kubectl -n mongodb delete pod -l app.kubernetes.io/name=percona-server-mongodb
```

**Step 2**: Wait for pods to enter CrashLoopBackOff
```bash
kubectl -n mongodb get pod -w
```
**Expected**: Pods in `CrashLoopBackOff` or `Error` state

**Step 3**: Run destroy while pods are crashing
```bash
bash scripts/destroy.sh mongodb
# Type "DESTROY"
```

**Step 4**: Monitor destroy progress
```bash
# Watch console output
# Watch namespace: kubectl get namespace mongodb -w
```

### Expected Results
- ✅ Destroy completes successfully (doesn't wait for unhealthy pods)
- ✅ Console shows CRD deletion order (CRs → operator → namespace)
- ✅ Namespace deletes cleanly
- ✅ All resources cleaned up

### Pass/Fail Criteria
**PASS** if destroy completes successfully despite crashing pods  
**FAIL** if destroy hangs waiting for pods to become healthy

**Estimated Time**: 5-7 minutes

---

## Test Environment

**Cluster**: `oms-dev-eks-cluster` (DEV environment)  
**Region**: `ap-east-1`  
**AWS Account**: `815402439714` (DEV)  
**Namespace**: `mongodb` (legacy naming, no `-dev` suffix)

---

## Test Execution Record

### Core Test Cases (Required for Merge)

| Test Case | Date | Tester | Result | Notes |
|-----------|------|--------|--------|-------|
| TC1: Pod Identity Cleanup | YYYY-MM-DD | | ⬜ PENDING | |
| TC2: CRD Finalizer Ordering | YYYY-MM-DD | | ⬜ PENDING | |
| TC3: End-to-End Cycle | YYYY-MM-DD | | ⬜ PENDING | |
| TC4: Backward Compatibility | YYYY-MM-DD | | ⬜ PENDING | |
| TC5: Error Handling | YYYY-MM-DD | | ⬜ PENDING | |

### Enhanced Test Cases (Optional, from Issue #81)

| Test Case | Date | Tester | Result | Notes |
|-----------|------|--------|--------|-------|
| TC6: Node Downscale | YYYY-MM-DD | | ⬜ OPTIONAL | Validates cleanup of orphaned associations |
| TC7: Node Upscale | YYYY-MM-DD | | ⬜ OPTIONAL | Validates cleanup of multiple associations |
| TC8: PodDisruptionBudget | YYYY-MM-DD | | ⬜ OPTIONAL | Validates PDB doesn't block destroy |
| TC9: Rolling Restart | YYYY-MM-DD | | ⬜ OPTIONAL | Validates destroy during in-flux StatefulSet |
| TC10: Crash Loop | YYYY-MM-DD | | ⬜ OPTIONAL | Validates destroy with unhealthy pods |

**Note**: Core test cases (TC1-TC5) are required for PR #77 merge. Enhanced test cases (TC6-TC10) are optional and can be executed post-merge for additional confidence.

---

## Full Test Suite Summary

**Total Test Cases**: 10 (5 core + 5 enhanced)

**Core Test Cases (Required for Merge)**: TC1-TC5
- Estimated time: 30-45 minutes
- Focus: Pod Identity cleanup, CRD ordering, backward compatibility

**Enhanced Test Cases (Optional)**: TC6-TC10
- Estimated time: 48-64 minutes
- Focus: Node scaling, PDB handling, in-flux destroy scenarios

**Total Estimated Time**: 78-109 minutes for full suite

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
