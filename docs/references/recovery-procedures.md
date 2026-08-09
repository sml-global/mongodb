# Recovery Procedures

Rollback, disaster recovery, credential rotation, and state recovery procedures.

**Who this is for:** Infra Operators (execute) and Infra Architects (design/approve).

**When to use this document:**
- A verification command fails and the component is unhealthy
- A credential is lost, rotated, or compromised
- Terraform state is corrupted or diverged
- A full environment rebuild is required (last resort)

All procedures here are **trigger-based** — run only when an incident or planned maintenance requires it. They are not part of routine recurring checks.

**Related docs:**
- [Glossary](glossary.md) — jargon/acronym lookup (finalizers, taint, split-brain, PITR, and more)
- [Verification Commands](verification-commands.md) — confirm recovery succeeded
- [Operator Runbook](../guides/operator-runbook.md) — normal operating procedures
- [Operator Runbook § Day-2 Operations](../guides/operator-runbook.md#day-2-operations-ongoing-maintenance) — trigger table referencing this doc
- [Component Catalog](component-catalog.md) — component dependencies

---

## Terraform State Recovery

### Symptom: State file corrupted or diverged

**Steps:**

1. Check state bucket versioning:
```bash
aws s3api list-object-versions \
  --bucket sml-oms-dev-tfstate \
  --prefix oms/dev/mongo.tfstate \
  --max-items 5
```

2. Restore previous version:
```bash
# Get the VersionId of the last known-good state
aws s3api get-object \
  --bucket sml-oms-dev-tfstate \
  --key oms/dev/mongo.tfstate \
  --version-id <good-version-id> \
  restored-state.tfstate

# Upload as current
aws s3 cp restored-state.tfstate s3://sml-oms-dev-tfstate/oms/dev/mongo.tfstate
```

3. Verify with plan (should show no changes if state matches reality):
```bash
bash scripts/provision-platform-prereq.sh mongodb
# Review plan — expect minimal or zero changes
```

### Symptom: State bucket accidentally deleted

1. Recreate bucket:
```bash
scripts/bootstrap-terraform-s3-backend.sh \
  --tf-dir platform-prerequisites/terraform/mongodb \
  --bucket sml-oms-dev-tfstate \
  --region ap-east-1 \
  --key oms/dev/mongo.tfstate
```

2. Re-import existing resources into fresh state (requires manual `terraform import` for each resource).

---

## MongoDB Encryption Key Lost

### Severity: CRITICAL — encrypted data may be permanently inaccessible

**Prevention:**
- Keep `.local-dev-encryption-key.txt` in a secure backup (password manager, vault)
- Verify escrow file exists before any cluster secret deletion

**If escrow file exists but cluster secret was deleted:**

```bash
# Recreate secret from escrow
scripts/bootstrap-dev-secrets.sh
# The script detects the escrow file and recreates the secret
```

**If both escrow and cluster secret are lost:**

- Existing encrypted MongoDB data **cannot be decrypted**
- For a fresh dev environment only: delete PVCs, regenerate key, restart from empty database
- For production: this is a data loss event — invoke DR plan

---

## MongoDB Credential Rotation

### Rotate all operator credentials

1. Generate new passwords:
```bash
# Remove old escrow to force regeneration
rm .local-dev-user-passwords.txt

# Delete existing secret
kubectl -n mongodb delete secret psmdb-secrets

# Regenerate
scripts/bootstrap-dev-secrets.sh
```

2. Restart MongoDB pods to pick up new credentials:
```bash
kubectl -n mongodb rollout restart statefulset psmdb-rs0
```

3. Verify replica set health:
```bash
kubectl -n mongodb exec psmdb-rs0-0 -c mongod -- \
  mongosh --quiet --eval "rs.status().members.map(m => m.name + ' ' + m.stateStr)"
```

> **Warning:** In production, coordinate credential rotation with the Percona Operator's built-in rotation mechanism to avoid split-brain.

---

## EBS CSI Driver Recovery

### Symptom: Addon deleted or stuck in CREATING/DEGRADED

This has occurred in this environment. Recovery path:

1. Check current addon state:
```bash
aws eks describe-addon \
  --cluster-name EKS-boomi-runtime-cluster \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.status' \
  --output text
```

2. If stuck, delete and recreate:
```bash
aws eks delete-addon \
  --cluster-name EKS-boomi-runtime-cluster \
  --addon-name aws-ebs-csi-driver

# Wait for deletion
while aws eks describe-addon --cluster-name EKS-boomi-runtime-cluster --addon-name aws-ebs-csi-driver 2>/dev/null; do
  sleep 10
done

# Recreate with Pod Identity
aws eks create-addon \
  --cluster-name EKS-boomi-runtime-cluster \
  --addon-name aws-ebs-csi-driver \
  --addon-version v1.62.0-eksbuild.1 \
  --pod-identity-associations 'serviceAccount=ebs-csi-controller-sa,roleArn=<role-arn>' \
  --resolve-conflicts OVERWRITE
```

3. Or use the automated bootstrap:
```bash
./scripts/provision.sh mongodb --bootstrap-platform-controllers
```

4. Verify:
```bash
kubectl get csidriver ebs.csi.aws.com
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver
```

---

## EKS Node Upgrade with PodDisruptionBudgets

### Symptom: Node group upgrade fails with PodEvictionFailure

When upgrading EKS node instance types while reducing node count (e.g., 4× m6i.large → 2× m6i.xlarge), Terraform may fail with:

```
Error: waiting for EKS Node Group version update: unexpected state 'Failed'
last error: PodEvictionFailure: Reached max retries while trying to evict pods
```

**Root cause**: Multiple overlapping PodDisruptionBudgets (PDBs) prevent pod eviction when there's insufficient capacity. Common with MongoDB clusters where:
- Operator-managed PDB: `psmdb-mongod-rs0` with `maxUnavailable: 1`
- Manual PDB: `psmdb-rs0-pdb` with `minAvailable: 2`

When a pod is Pending (insufficient node resources), the PDB blocks eviction:
- `currentHealthy: 2`, `expectedPods: 3`, `disruptionsAllowed: 0`
- Status: `InsufficientPods` - DisruptionAllowed: False

### Production-safe solution: Add capacity first

**Zero-downtime pattern** — add new nodes before draining old ones:

```bash
# Step 1: Increase desired_size FIRST (adds new nodes without draining)
# eks-platform.tfvars:
#   node_instance_type = "m6i.large"  # keep current type
#   desired_size = 6                  # add capacity
bash scripts/provision.sh --env uat eks-platform --auto-approve

# Step 2: Wait for new nodes and pods to reschedule
kubectl get nodes -w

# Step 3: NOW change instance type and reduce size
# eks-platform.tfvars:
#   node_instance_type = "m6i.xlarge"
#   desired_size = 2
bash scripts/provision.sh --env uat eks-platform --auto-approve
```

This allows all pods to reschedule to new nodes before old nodes drain.

### Emergency solution (UAT/Dev only)

**WARNING**: Direct termination forcibly kills pods without graceful drain. Only use in non-production environments.

When stuck with blocked evictions, manually terminate old nodes to bypass PDB:

```bash
# 1. Identify old nodes by instance type
kubectl get nodes -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type

# 2. For each old node, terminate directly (bypasses PDB)
aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=<node-dns>" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text | \
  xargs -I {} aws ec2 terminate-instances --instance-ids {}

# 3. Retry Terraform after all old nodes are terminated
bash scripts/provision.sh --env uat eks-platform --auto-approve
```

### Checking for PDB issues

```bash
# List all PDBs in a namespace
kubectl get pdb -n <namespace>

# Check PDB status for blocking issues
kubectl get pdb <pdb-name> -n <namespace> -o jsonpath='{.status}' | jq .

# Check for multiple PDBs on same pods
kubectl get pdb -n <namespace> -o yaml | grep -A 10 "selector:"
```

Key indicators of problems:
- `disruptionsAllowed: 0`
- `reason: InsufficientPods`
- Multiple PDBs selecting the same pods

**Prevention best practices:**
1. Always add capacity before draining in production
2. Avoid multiple overlapping PDBs on the same pods
3. Size nodes for workload requirements before provisioning
4. Test node upgrades in UAT first using the zero-downtime pattern

**Related**: Issue #69 — discovered during UAT EKS node upgrade from 4× m6i.large to 2× m6i.xlarge on 2026-08-05.

---

## Orphaned EBS Volume Recovery

Both `gp3-mongodb` and `gp3-postgresql` StorageClasses use
`reclaimPolicy: Retain`. Deleting a PVC (directly, or as a side effect of
`scripts/destroy.sh`) does **not** delete the underlying AWS EBS volume — the
`PersistentVolume` moves to `Released`, and the data survives, but it will
not automatically bind to a new PVC until an operator clears its claim.

This is a Kubernetes-side operation on the `PersistentVolume` object's
`spec.claimRef` field — not an AWS-console action; the EBS volume itself is
untouched throughout.

### Step 1: Identify the released volume

```bash
kubectl get pv | grep Released
# NAME       CAPACITY   ...   RECLAIM POLICY   STATUS     CLAIM
# pvc-abc123 50Gi       ...   Retain           Released   coredb/oms-postgresql-coredb-1
```

### Step 2: Clear the stale claim reference

```bash
kubectl patch pv pvc-abc123 --type=json \
  -p='[{"op": "remove", "path": "/spec/claimRef"}]'
# PV moves from Released -> Available
```

### Step 3: Bind it to a new PVC

Create a PVC with a matching `storageClassName`, `accessModes`, and a
`volumeName` pinning it to the specific released volume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recovered-data
  namespace: coredb
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: gp3-postgresql
  volumeName: pvc-abc123
  resources:
    requests:
      storage: 50Gi
```

### Step 4: Mount and read the data

Attach the PVC to a temporary debug pod to inspect/copy its contents (for
PostgreSQL, this is the raw `PGDATA` directory — do not start a new
PostgreSQL instance directly against it without restoring through CNPG's
normal bootstrap process; treat it as a forensic copy source, not a
drop-in replacement volume).

---

## Flux HelmRelease Stuck

### Symptom: HelmRelease shows Ready=False or suspended

1. Check status:
```bash
kubectl get helmreleases -A
kubectl describe helmrelease <name> -n <namespace>
```

2. Force reconciliation:
```bash
kubectl annotate helmrelease <name> -n <namespace> \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

3. If chart values are invalid, fix in git and wait for Flux to reconcile, or:
```bash
# Suspend and resume
kubectl patch helmrelease <name> -n <namespace> \
  --type merge -p '{"spec":{"suspend":true}}'
# Fix the issue
kubectl patch helmrelease <name> -n <namespace> \
  --type merge -p '{"spec":{"suspend":false}}'
```

---

## MongoDB Pod CrashLooping

### Diagnosis:

```bash
kubectl -n mongodb get pods
kubectl -n mongodb logs psmdb-rs0-0 -c mongod --tail=60
kubectl -n mongodb describe pod psmdb-rs0-0
```

### Common causes and fixes:

| Cause | Log Evidence | Fix |
|---|---|---|
| Encryption key mismatch | `unable to acquire encryption key` | Restore correct key from escrow |
| PVC not bound | `pod has unbound PersistentVolumeClaims` | Check EBS CSI driver and StorageClass |
| Resource exhaustion | `OOMKilled` or CPU throttling | Increase resource limits in overlay |
| Certificate expired | TLS handshake errors | Check cert-manager certificate status |

---

## MongoDB Recovery: Restoring from an on-demand export

If an on-demand backup was taken via
`scripts/export-database-snapshot.sh mongodb` (see the script's own `--help`
for usage), it is written via PBM (Percona Backup for MongoDB) to the same S3
backup prefix as scheduled backups and is restored the same way — PBM does
not distinguish scheduled/continuous backups from on-demand ones at restore
time.

`scripts/dr-drill-mongodb-restore.sh` automates exactly this restore path
(latest PBM backup from the catalog, restored via `pbm restore --wait` into
an isolated namespace) and can be used as a reference for a manual restore,
or run directly for a drill/verification. It never targets the production
namespace.

---

## SigNoz Recovery

### Symptom: SigNoz pods Pending due to PVC issues

1. Check PVC status:
```bash
kubectl -n signoz get pvc
```

2. If PVCs lack StorageClass:
```bash
# Patch PVCs to use correct StorageClass
kubectl -n signoz get pvc -o name | while read pvc; do
  kubectl -n signoz patch "$pvc" -p '{"spec":{"storageClassName":"gp3-mongodb"}}'
done
```

3. Restart:
```bash
kubectl -n signoz rollout restart deployment/signoz
kubectl -n signoz rollout restart statefulset/signoz-clickhouse
```

### Symptom: ClickHouse data corrupted

For dev environment: delete PVCs and let SigNoz recreate (loses historical telemetry):
```bash
kubectl -n signoz delete pvc --all
kubectl -n signoz rollout restart statefulset/signoz-clickhouse
```

---

## Dev/SIT PostgreSQL Recovery (CNPG)

Dev/SIT PostgreSQL runs as a self-managed CloudNativePG (CNPG) cluster (see
[PostgreSQL Platform Contract](postgresql-platform-contract.md)), not Aurora —
use this section for Dev/SIT; see "PostgreSQL Recovery" below for UAT/Prod.

### Restoring into a new cluster from the WAL archive

CNPG restores by bootstrapping a **new** `Cluster` resource that recovers from
an existing backup archive — it does not restore in place onto the original
cluster. Example below is for the core cluster; the brand cluster follows the
same pattern with its own namespace (`branddb`), cluster name
(`oms-postgresql-branddb`), ServiceAccount (`oms-postgresql-brand-workload`),
and backup bucket.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: oms-postgresql-coredb-restored
  namespace: coredb
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4
  serviceAccountName: oms-postgresql-workload
  storage:
    storageClass: gp3-postgresql
    size: 50Gi
  bootstrap:
    recovery:
      source: oms-postgresql-coredb
  externalClusters:
    - name: oms-postgresql-coredb
      barmanObjectStore:
        destinationPath: s3://oms-postgresql-coredb-backup
        s3Credentials:
          inheritFromIAMRole: true
```

### Point-in-time recovery

Add `recoveryTarget.targetTime` under `bootstrap.recovery` to recover to a
specific point in time instead of the latest available WAL:

```yaml
  bootstrap:
    recovery:
      source: oms-postgresql-coredb
      recoveryTarget:
        targetTime: "2026-08-01T09:00:00Z"
```

### Restoring from an on-demand export

If an on-demand backup was taken via
`scripts/export-database-snapshot.sh postgresql` (see the script's own
`--help` for usage), it is stored in the same per-cluster backup bucket
(e.g. `s3://oms-postgresql-coredb-backup`) and is restored the same way —
CNPG does not distinguish scheduled/continuous backups from on-demand ones
at restore time.

**Verify the restore:**
```bash
kubectl -n coredb get cluster oms-postgresql-coredb-restored
# Expect: status=Ready once recovery completes
```

---

## PostgreSQL Recovery

### Aurora automated backups

Aurora automatically maintains backups. To restore:

```bash
# List available snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier pg18-dev \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Restore to new cluster (non-destructive)
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier pg18-dev-restored \
  --snapshot-identifier <snapshot-id> \
  --engine aurora-postgresql \
  --vpc-security-group-ids <sg-id>
```

### Point-in-time recovery

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier pg18-dev \
  --db-cluster-identifier pg18-dev-pitr \
  --restore-to-time "2026-07-06T09:00:00Z"
```

---

## Full Environment Rebuild (Last Resort)

For a complete fresh dev environment:

```bash
# 1. Teardown provisioned components (all-at-once)
# Add --export-first to take an on-demand backup of MongoDB/PostgreSQL data
# before teardown (aborts if the export fails) -- see `scripts/destroy.sh --help`.
bash scripts/destroy.sh all --auto-approve --export-first

# 2. Re-provision from scratch
bash scripts/provision.sh all
scripts/bootstrap-dev-secrets.sh
scripts/create-audit-writer-user.sh
scripts/validate-dev-render.sh

# 3. Re-provision SigNoz + its dashboards/alerts
scripts/create-signoz-root-user-secret.sh
bash scripts/provision.sh signoz
# Service Account + API key are bootstrapped automatically on first run
# (headless browser script) -- see docs/references/signoz-dashboard-import-pack.md
bash scripts/provision.sh signoz-observability --auto-approve

# 4. Verify
scripts/verify-platform-health.sh
scripts/run-audit-telemetry-test.sh

# If MongoDB is reconciling/rolling during verification, wait for settle then re-run:
kubectl -n mongodb rollout status statefulset/psmdb-rs0 --timeout=300s
scripts/verify-platform-health.sh
scripts/run-audit-telemetry-test.sh
```

### Component-by-component teardown

Use these to remove stacks one by one after tests:

```bash
# Remove SigNoz dashboards/alerts Terraform state only (run before 'signoz'
# below so the API is still reachable for a clean delete)
bash scripts/destroy.sh signoz-observability --auto-approve

# Remove MongoDB stack only (k8s workloads + mongodb terraform scope)
# Add --export-first for an on-demand backup before teardown (aborts on export failure)
bash scripts/destroy.sh mongodb --auto-approve --export-first

# Remove PostgreSQL only (k8s workloads + postgresql terraform scope)
# Add --export-first for an on-demand backup before teardown (aborts on export failure)
bash scripts/destroy.sh pg --auto-approve --export-first

# Remove SigNoz only (helmrelease + namespace)
bash scripts/destroy.sh signoz
```

If the signoz namespace is stuck in `Terminating`, clear ClickHouse and namespace finalizers:

```bash
kubectl -n signoz get clickhouseinstallations.clickhouse.altinity.com -o name \
  | xargs -I{} kubectl -n signoz patch {} --type='json' -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl patch namespace signoz --type='json' -p='[{"op":"replace","path":"/spec/finalizers","value":[]}]'
```

> **Warning:** This destroys all MongoDB data and SigNoz telemetry history. Only use for dev environments.
