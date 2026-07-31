# PostgreSQL Platform Contract

**Date:** 2026-07-27  
**Component:** CloudNativePG (CNPG) Operator  
**Namespace:** postgresql  
**StorageClass:** gp3-postgresql  
**Backup System:** Continuous WAL archival to AWS S3

> **Scope update (2026-07-30):** this contract now applies to **Dev/SIT only**. UAT and
> Prod are migrating from CNPG to AWS Aurora PostgreSQL (managed RDS) per
> [VPC Subnet Allocation and Boomi Networking Design](superpowers/specs/2026-07-29-vpc-subnet-and-boomi-routing-design.md#database-engine-decision)
> and the Aurora Terraform resources in
> [platform-prerequisites/terraform/postgresql/main.tf](../../platform-prerequisites/terraform/postgresql/main.tf).
> The existing `gitops/postgresql/overlays/uat/` CNPG deployment for UAT is superseded and
> requires a manual decommission step (not yet performed as of this date) before Aurora
> becomes UAT's live database — this is a real infrastructure change, not a docs-only update,
> and should follow the same explicit-confirmation pattern as
> [sandbox-teardown-runbook.md](sandbox-teardown-runbook.md).

---

## Ownership & Maintenance

- **Platform Component:** CloudNativePG (CNPG) Operator
- **Maintained By:** Infrastructure Team
- **On-Call Contact:** [Define in deployment runbook]
- **Documentation:** This contract (postgresql-platform-contract.md)
- **Related Docs:** 
  - [Architect Reference](architect-reference.md)
  - [Component Catalog](component-catalog.md)
  - [Recovery Procedures](recovery-procedures.md)
  - [Environment Setup](../guides/environment-setup.md)
  - [Operator Runbook](../guides/operator-runbook.md)

---

## Component Overview

- **Operator:** CloudNativePG (CNPG)
- **Version:** Defined in `config/environment-schema/fragments/40-postgresql.manifest` (POSTGRESQL_VERSION)
- **Namespace:** postgresql (created automatically by HelmRelease with `createNamespace: true`)
- **StorageClass:** gp3-postgresql (defined in k8s/base/storage-classes.yaml)
- **Backup System:** Continuous WAL archival to AWS S3 with point-in-time recovery (PITR)
- **Replica Set:** 3-node configuration (configurable per environment via schema fragment)

---

## Lifecycle

### Provisioning Phase

#### Step 1: Phase 2 Prerequisites Validation
The following AWS resources **must** exist from Phase 2 provisioning before PostgreSQL provisioning can proceed:

1. **IRSA Role:** `oms-postgresql-operator-role`
   - Verify: `aws iam get-role --role-name oms-postgresql-operator-role`
   - Used by: Terraform `var.postgresql_operator_iam_role_arn` input
   - Purpose: AWS pod identity for PostgreSQL operator workload

2. **S3 Bucket:** `oms-cnpg-wal-archive`
   - Verify: `aws s3api head-bucket --bucket oms-cnpg-wal-archive`
   - Used by: CloudNativePG WAL archival destination
   - Purpose: Store PostgreSQL WAL (Write-Ahead Logs) for continuous backup and PITR

3. **AWS KMS Key:** `oms-postgresql-cluster-key`
   - Verify: `aws kms describe-key --key-id oms-postgresql-cluster-key`
   - Used by: Encrypt/decrypt WAL archives and backups
   - Purpose: Encryption at rest for backup artifacts

#### Step 2: Terraform Provisioning
Terraform applies IAM policy attachment to enable PostgreSQL operator to access AWS resources:

```bash
cd platform-prerequisites/terraform/postgresql
terraform fmt -check      # Validate code style
terraform validate        # Validate configuration
terraform plan            # Review changes (do NOT apply)
```

**Terraform Artifacts:**
- **Module:** `platform-prerequisites/terraform/postgresql/main.tf`
- **Variables:** `platform-prerequisites/terraform/postgresql/variables.tf`
- **Outputs:** `postgresql_operator_policy_id` (IAM policy ID created)
- **Validation:** Attaches `oms-postgresql-wal-archive-policy` to `oms-postgresql-operator-role`

#### Step 3: GitOps Provisioning
GitOps deploys CloudNativePG Operator and PostgreSQL Cluster custom resource:

```bash
cd /Users/frank/sml/oms/mongodb
bash scripts/provision.sh postgresql
```

**GitOps Artifacts:**
- **Base Configuration:** `gitops/postgresql/base/` (kustomization.yaml, helm values, namespace)
- **Overlay (UAT):** `gitops/postgresql/overlays/uat/` (environment-specific values)
- **Deployment:** HelmRelease CRD for `cloudnative-pg` chart
- **Cluster Resource:** Cluster custom resource named `postgresql` with:
  - IRSA enabled via `inheritFromIAMRole: true`
  - ServiceAccount: `oms-postgresql-workload` (annotated with IRSA role ARN)
  - WAL archival configuration (S3 bucket path, KMS key reference)
  - 3-node replica set (standard configuration)
  - Point-in-time recovery (PITR) enabled

#### Step 4: Provisioning Verification
```bash
# Check operator pod readiness
kubectl get pods -n postgresql

# Check PostgreSQL cluster status
kubectl -n postgresql get cluster postgresql

# Check replica set health
kubectl -n postgresql exec -it postgresql-1 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Run smoke tests
bash scripts/verify-platform-health.sh --smoke-test
```

**Success Criteria:**
- Operator pod is Running (1/1 Ready)
- PostgreSQL cluster is Ready (status=Ready)
- Replica set has 3 healthy members (1 primary + 2 secondaries)
- Smoke test returns exit code 0

---

### Destruction Phase

#### Pre-Destroy Guard Execution
Before any destruction, the `verify_postgresql_pre_destroy_guard` is automatically executed:

```bash
bash scripts/provision.sh all --destroy
# Internally calls: verify_postgresql_pre_destroy_guard
# If guard fails → destruction is blocked
# If guard passes → destruction proceeds
```

#### Step 1: Guard Validation Protocol (7-Step Seam)

**Seam Read:** Extract guard configuration from environment
```bash
POSTGRESQL_NAMESPACE=${POSTGRESQL_NAMESPACE:-"postgresql"}
POSTGRESQL_CLUSTER_NAME=${POSTGRESQL_CLUSTER_NAME:-"postgresql"}
```

**Parse:** Query Kubernetes and PostgreSQL status
```bash
# Get cluster status
kubectl -n "$POSTGRESQL_NAMESPACE" get cluster "$POSTGRESQL_CLUSTER_NAME" -o yaml

# Get replica health
kubectl -n "$POSTGRESQL_NAMESPACE" exec "${POSTGRESQL_CLUSTER_NAME}-1" -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;" 

# Get recent events
kubectl -n "$POSTGRESQL_NAMESPACE" get events --sort-by='.lastTimestamp' | head -20
```

**Validate:** Check all health constraints
- Primary pod is Running and Ready
- All replica pods are Running and Ready
- At least 2 replicas are connected and streaming WAL
- No active backups in progress
- WAL archive status is healthy
- S3 bucket permissions are intact

**Identity:** Record destruction authorization
- Extract operator identity from `$USER` environment variable
- Log to audit trail: `destruction_requested_by=${USER}`
- Timestamp: ISO-8601 format

**SHA-256 Digest:** Create immutable fingerprint of cluster configuration
```bash
DIGEST=$(kubectl -n "$POSTGRESQL_NAMESPACE" get cluster "$POSTGRESQL_CLUSTER_NAME" -o yaml | sha256sum | awk '{print $1}')
echo "Cluster configuration digest: $DIGEST"
```

**Callback:** Log destruction authorization
- Event type: `postgresql_pre_destroy_guard_pass`
- Recorded digest: $DIGEST
- Timestamp: ISO-8601
- Audit destination: Kubernetes audit log + CloudWatch

**Return:** Exit code 0 if all validations pass; non-zero if any check fails

#### Step 2: Actual Destruction
If guard passes, destruction proceeds:

1. **GitOps Removal:**
   ```bash
   bash scripts/provision.sh all --destroy
   ```
   - Removes PostgreSQL Cluster custom resource
   - Removes CloudNativePG Operator HelmRelease
   - PersistentVolumes and PersistentVolumeClaims are removed

2. **Terraform Destruction:**
   ```bash
   cd platform-prerequisites/terraform/postgresql
   terraform destroy
   ```
   - Removes IAM policy attachment to IRSA role
   - Does NOT remove IAM role itself (shared with other components)
   - Preserves S3 bucket and KMS key (may be needed for WAL recovery)

#### Step 3: Post-Destruction Verification
```bash
# Verify no PostgreSQL pods remain
kubectl get pods -n postgresql

# Verify no PersistentVolumeClaims
kubectl get pvc -n postgresql

# Verify no Cluster resources
kubectl get cluster -A

# Verify S3 WAL archives are preserved
aws s3api head-bucket --bucket oms-cnpg-wal-archive
```

**Success Criteria:**
- No PostgreSQL pods in cluster
- No PVCs in postgresql namespace
- No Cluster custom resources
- S3 bucket still contains WAL archives (for recovery if needed)

---

## Identities

### IRSA (AWS Pod Identity)

**Role Name:** `oms-postgresql-operator-role` (from Phase 2 platform_contract)

**Binding:** Kubernetes IRSA annotation on ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oms-postgresql-workload
  namespace: postgresql
  annotations:
    iam.gke.io/gcp-service-account: oms-postgresql-operator-role@PROJECT_ID.iam.gserviceaccount.com
```

**AWS Pod Identity Configuration:**
- AWS EKS cluster with IRSA enabled
- Trust relationship established between Kubernetes OIDC provider and IAM role
- ServiceAccount annotation enables automatic credential injection to pods

---

### IAM Permissions

**Policy Name:** `oms-postgresql-wal-archive-policy` (attached by platform-prerequisites/terraform/postgresql/)

**S3 Permissions:**
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::oms-cnpg-wal-archive",
    "arn:aws:s3:::oms-cnpg-wal-archive/*"
  ]
}
```

**Purpose:**
- `GetObject`: Read WAL archives from S3 (point-in-time recovery)
- `PutObject`: Write new WAL segments to S3
- `DeleteObject`: Clean up old WAL segments per retention policy
- `ListBucket`: Enumerate WAL objects for inventory and recovery

**KMS Permissions:**
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "arn:aws:kms:*:ACCOUNT_ID:key/oms-postgresql-cluster-key"
}
```

**Purpose:**
- `Decrypt`: Decrypt WAL archives during point-in-time recovery
- `GenerateDataKey`: Encrypt WAL segments during S3 upload

---

### Kubernetes Secrets

**Native Kubernetes Secrets:** None

All AWS credentials are injected via IRSA pod identity. No stored Kubernetes secrets for AWS credentials.

**PostgreSQL Internal Secrets:**
- `postgresql-superuser`: PostgreSQL superuser credentials (managed by CNPG operator, NOT exposed to external systems)
- `postgresql-app-user`: Application database user credentials (if configured)

---

## Guard Semantics

### Pre-Destroy Guard: `verify_postgresql_pre_destroy_guard`

**Trigger:** Invoked automatically when `bash scripts/provision.sh all --destroy` is executed

**Purpose:** Prevent accidental destruction of PostgreSQL cluster by validating:
1. Replica set is healthy and in sync
2. No active backups or WAL archival operations are in progress
3. AWS permissions are intact
4. Authorized operator is performing the destruction

**Protocol (7-Step Seam):**

#### Seam Read
Extract configuration from environment:
```bash
POSTGRESQL_NAMESPACE=${POSTGRESQL_NAMESPACE:-"postgresql"}
POSTGRESQL_CLUSTER_NAME=${POSTGRESQL_CLUSTER_NAME:-"postgresql"}
POSTGRESQL_WAL_BUCKET=${POSTGRESQL_WAL_BUCKET:-"oms-cnpg-wal-archive"}
```

#### Parse
Query Kubernetes and PostgreSQL for health status:
```bash
# Get cluster status
kubectl -n "$POSTGRESQL_NAMESPACE" get cluster "$POSTGRESQL_CLUSTER_NAME" -o yaml

# Get replication status
kubectl -n "$POSTGRESQL_NAMESPACE" exec "${POSTGRESQL_CLUSTER_NAME}-1" -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;" -o JSON

# Get WAL archival status
kubectl -n "$POSTGRESQL_NAMESPACE" exec "${POSTGRESQL_CLUSTER_NAME}-1" -- \
  psql -U postgres -c "SELECT * FROM pg_stat_archiver;"

# Get recent events
kubectl -n "$POSTGRESQL_NAMESPACE" get events --sort-by='.lastTimestamp' | head -20
```

#### Validate
Perform health checks:
```bash
# Check: Primary pod is Running and Ready
PRIMARY_POD=$(kubectl -n "$POSTGRESQL_NAMESPACE" get pods -l "cnpg.io/cluster=$POSTGRESQL_CLUSTER_NAME" \
  -o jsonpath='{.items[?(@.metadata.labels.cnpg\.io/role=="primary")].metadata.name}')
if ! kubectl -n "$POSTGRESQL_NAMESPACE" get pod "$PRIMARY_POD" --no-headers | grep -q "Running"; then
  echo "ERROR: Primary pod is not Running. Destruction blocked."
  exit 1
fi

# Check: At least 2 replicas are connected
CONNECTED_REPLICAS=$(kubectl -n "$POSTGRESQL_NAMESPACE" exec "${POSTGRESQL_CLUSTER_NAME}-1" -- \
  psql -U postgres -c "SELECT COUNT(*) FROM pg_stat_replication WHERE state='streaming';" --tuples-only)
if [[ $CONNECTED_REPLICAS -lt 2 ]]; then
  echo "ERROR: Fewer than 2 replicas connected. Destruction blocked."
  exit 1
fi

# Check: No active WAL archival failures
ARCHIVAL_FAILED=$(kubectl -n "$POSTGRESQL_NAMESPACE" exec "${POSTGRESQL_CLUSTER_NAME}-1" -- \
  psql -U postgres -c "SELECT failed_count FROM pg_stat_archiver WHERE failed_count > 0;" --tuples-only | wc -l)
if [[ $ARCHIVAL_FAILED -gt 0 ]]; then
  echo "ERROR: Active WAL archival failures detected. Destruction blocked."
  exit 1
fi

# Check: S3 bucket is accessible
aws s3api head-bucket --bucket "$POSTGRESQL_WAL_BUCKET" || {
  echo "ERROR: Cannot access S3 bucket $POSTGRESQL_WAL_BUCKET. Destruction blocked."
  exit 1
}
```

#### Identity
Record the operator performing destruction:
```bash
DESTRUCTION_OPERATOR=${USER:-"unknown"}
DESTRUCTION_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Destruction requested by: $DESTRUCTION_OPERATOR"
echo "Timestamp: $DESTRUCTION_TIMESTAMP"
```

#### SHA-256 Digest
Create immutable fingerprint of cluster configuration:
```bash
DIGEST=$(kubectl -n "$POSTGRESQL_NAMESPACE" get cluster "$POSTGRESQL_CLUSTER_NAME" -o yaml | sha256sum | awk '{print $1}')
echo "Cluster configuration digest: $DIGEST"
```

#### Callback
Log destruction authorization to audit system:
```bash
# Log to Kubernetes audit
kubectl -n "$POSTGRESQL_NAMESPACE" annotate cluster "$POSTGRESQL_CLUSTER_NAME" \
  "destruction-authorized-by=$DESTRUCTION_OPERATOR" \
  "destruction-timestamp=$DESTRUCTION_TIMESTAMP" \
  "destruction-cluster-digest=$DIGEST" \
  --overwrite

# Optionally log to CloudWatch
# aws logs put-log-events --log-group-name /postgresql/destruction ...
```

#### Return
Exit with appropriate code:
```bash
# If all validations passed
echo "All pre-destruction checks passed. Proceeding with destruction."
exit 0

# If any validation failed
exit 1
```

**Failure Behavior:** If any validation fails, destruction is blocked. The operator must:
1. Investigate the failure reason
2. Resolve any health issues (e.g., restore replica connectivity, fix WAL archival)
3. Re-run the destruction command

**Safety Net:** The guard ensures an adequate grace period for manual verification or emergency rollback before destruction proceeds.

---

## Prerequisites

### AWS Prerequisites (Phase 2 Outputs)

Before provisioning PostgreSQL on Phase 3, ensure the following AWS resources exist from Phase 2 infrastructure:

#### 1. IRSA Role: `oms-postgresql-operator-role`

**Verification:**
```bash
aws iam get-role --role-name oms-postgresql-operator-role
# Expected output: Role ARN, creation date, etc.
```

**What It Is:** An AWS IAM role with a trust relationship to the Kubernetes OIDC provider, allowing PostgreSQL operator pods to assume this role via IRSA.

**Used By:** Terraform `platform-prerequisites/terraform/postgresql/variables.tf` consumes this via `var.postgresql_operator_iam_role_arn`

**Why It Matters:** Without this role, PostgreSQL operator cannot authenticate to AWS to archive WAL segments or perform backups.

#### 2. S3 Bucket: `oms-cnpg-wal-archive`

**Verification:**
```bash
aws s3api head-bucket --bucket oms-cnpg-wal-archive
# Expected: HTTP 200 (bucket exists and you have access)
```

**What It Is:** An S3 bucket for storing PostgreSQL WAL (Write-Ahead Logs) created by CloudNativePG WAL archival.

**Used By:** CNPG cluster configuration for continuous WAL archival

**Why It Matters:** WAL archives are the foundation for point-in-time recovery (PITR). Without this bucket, WAL segments are not archived and data recovery is impossible.

#### 3. AWS KMS Key: `oms-postgresql-cluster-key`

**Verification:**
```bash
aws kms describe-key --key-id oms-postgresql-cluster-key
# Expected output: Key metadata, key state, etc.
```

**What It Is:** A KMS key for encrypting WAL archives and backups in transit and at rest.

**Used By:** CNPG cluster configuration references this key for encryption

**Why It Matters:** WAL data is encrypted using this key; without it, encrypted WAL archives cannot be decrypted for point-in-time recovery.

### Kubernetes Prerequisites

#### 1. Namespace: `postgresql`

**Status:** Automatically created by HelmRelease with `createNamespace: true`

**Verification:**
```bash
kubectl get namespace postgresql
```

#### 2. StorageClass: `gp3-postgresql`

**Status:** Defined in `k8s/base/storage-classes.yaml`

**Verification:**
```bash
kubectl get storageclass gp3-postgresql
# Expected: Storage class with provisioner=aws-ebs, parameters include gp3, iops=3000, etc.
```

**Why It Matters:** PostgreSQL PersistentVolumes use this storage class for high-performance block storage.

#### 3. Flux Controllers

**Status:** Must be active in cluster from Phase 2 EKS deployment

**Verification:**
```bash
kubectl get deployment -n flux-system
# Expected: 2 deployments (source-controller, helm-controller)
```

### Operator Prerequisites

Before running provisioning scripts, validate:

#### Pre-Flight Check
```bash
bash scripts/verify-platform-health.sh --preflight
# Checks: AWS credentials, EKS cluster access, Kubernetes connectivity
```

#### Verify Phase 2 AWS Outputs
```bash
# Verify IRSA role exists
aws iam get-role --role-name oms-postgresql-operator-role

# Verify S3 bucket is accessible
aws s3api head-bucket --bucket oms-cnpg-wal-archive

# Verify KMS key is accessible
aws kms describe-key --key-id oms-postgresql-cluster-key

# Verify KMS key has correct permissions for IRSA role
aws kms get-key-policy --key-id oms-postgresql-cluster-key --policy-name default --output text | \
  grep "oms-postgresql-operator-role"
```

#### Terraform Validation
```bash
cd platform-prerequisites/terraform/postgresql
terraform fmt -check    # No formatting issues
terraform validate      # Valid HCL configuration
```

---

## Service Dependencies

### Depends On

- **Phase 2 EKS Cluster:** Must be running and accessible before PostgreSQL provisioning
  - Cluster name, endpoint, CA certificate
  - kubeconfig configured in `~/.kube/config`
  - kubectl connectivity verified

- **Phase 2 IRSA Roles & Policies:** Must exist and be properly trusted
  - `oms-postgresql-operator-role` with OIDC trust to EKS cluster

- **Phase 2 AWS S3 Bucket:** Must exist with proper encryption
  - `oms-cnpg-wal-archive` bucket created and accessible
  - Encryption enabled (recommended: SSE-S3 or SSE-KMS)

- **Phase 2 AWS KMS Key:** Must exist and be accessible
  - `oms-postgresql-cluster-key` key in ACTIVE state
  - Key policy grants IRSA role permission to Decrypt and GenerateDataKey

- **Phase 3 Kubernetes Storage:** Must be provisioned first
  - StorageClass `gp3-postgresql` defined in k8s/base/

### Required By

- **Boomi Integration:** Application data and audit log storage
  - Consumes: PostgreSQL connection string, write operations
  - Verifies: PostgreSQL cluster is healthy and accepting connections

- **SigNoz Observability:** PostgreSQL metrics are exported via OpenTelemetry collector
  - Consumes: PostgreSQL connection string, metrics endpoint
  - Verifies: PostgreSQL postgres_exporter metrics are available

- **Application Layer:** PostgreSQL is the primary transactional data store
  - Consumes: PostgreSQL connection string, ACID transactions
  - Verifies: Replica set quorum for data consistency

### Optional Dependencies

- **MongoDB:** Runs independently; no direct dependency
  - Can coexist in same cluster without conflicts
  - Both use different namespaces and storage classes

- **SigNoz:** Observes PostgreSQL but not required for operation
  - Can be deployed before or after PostgreSQL
  - Telemetry collection is optional

---

## Configuration Reference

**Update (2026-07-31, Issue #4):** the environment-schema keys previously
listed here (`POSTGRESQL_VERSION`, `POSTGRESQL_STORAGE_CLASS`,
`POSTGRESQL_REPLICA_COUNT`, `POSTGRESQL_IMAGE_REPO`,
`POSTGRESQL_OPERATOR_VERSION`, `POSTGRESQL_BACKUP_ENABLED`,
`POSTGRESQL_BACKUP_SCHEDULE`, `POSTGRESQL_WAL_ARCHIVAL_ENABLED`,
`POSTGRESQL_WAL_RETENTION_DAYS`, `POSTGRESQL_PITR_ENABLED`) were never
actually consumed by any script, Terraform module, or Kubernetes manifest --
verified via repo-wide search, including `scripts/lib/packages/40-postgresql/`.
They were removed from `config/environment-schema/fragments/40-postgresql.manifest`.

Per the Dev/SIT-vs-UAT/Prod split (see the Scope Update above and
`docs/references/component-catalog.md`):

- **UAT/Prod (Aurora):** real configuration is Terraform-managed --
  `platform-prerequisites/terraform/postgresql/variables.tf` and the
  `environments/{uat,prod}/*.tfvars` files are authoritative.
- **Dev/SIT (CNPG):** **no committed CNPG `Cluster` manifest for a live
  Dev/SIT deployment was found anywhere in this repository** at the time of
  this cleanup -- the only `postgresql.cnpg.io` `Cluster` manifest that
  exists is the throwaway restore-target created inline by
  `scripts/dr-drill-postgresql-restore.sh` for DR drills, which is not the
  same thing as a live Dev/SIT database. If a real Dev/SIT CNPG deployment
  exists, it is not tracked as IaC in this repo and this section cannot
  document its actual hardcoded values; this is flagged as a follow-up to
  verify separately, not assumed away.

3. **gitops/postgresql/overlays/uat/kustomization.yaml**
   - Reads POSTGRESQL_VERSION for HelmRelease chart version
   - Configures replica count and storage class

4. **scripts/verify-platform-health.sh --smoke-test**
   - Verifies PostgreSQL is accessible
   - Validates WAL archival is functioning

---

## Related Documentation

- [Environment Setup Guide](../guides/environment-setup.md) - Step-by-step platform setup
- [Operator Runbook](../guides/operator-runbook.md) - Operational procedures
- [Recovery Procedures](recovery-procedures.md) - Disaster recovery steps
- [Audit Log Contract](audit-log-contract.md) - Audit logging requirements
- [Component Catalog](component-catalog.md) - All platform components
