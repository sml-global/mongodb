# Recovery Procedures

Rollback, disaster recovery, credential rotation, and state recovery procedures.

**Who this is for:** Infra Operators (execute) and Infra Architects (design/approve).

**Related docs:**
- [Verification Commands](verification-commands.md) — confirm recovery succeeded
- [Operator Runbook](../guides/operator-runbook.md) — normal operating procedures
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
# 1. Delete workloads
kubectl delete -k k8s/overlays/dev
kubectl -n signoz delete helmrelease signoz

# 2. Delete secrets and escrow
kubectl -n mongodb delete secret psmdb-encryption-key psmdb-secrets
rm -f .local-dev-encryption-key.txt .local-dev-user-passwords.txt

# 3. Re-provision from scratch
bash scripts/provision.sh all
scripts/bootstrap-dev-secrets.sh
scripts/validate-dev-render.sh

# 4. Verify
scripts/verify-platform-health.sh
```

> **Warning:** This destroys all MongoDB data and SigNoz telemetry history. Only use for dev environments.
