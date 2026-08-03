# PostgreSQL Platform Contract

**Date:** 2026-07-27  
**Component:** CloudNativePG (CNPG) Operator  
**Namespaces:** `coredb` (core database), `branddb` (brand database) — one independent CNPG cluster per namespace so each can be provisioned, resized, or destroyed without affecting the other  
**StorageClass:** gp3-postgresql  
**Backup System:** Continuous WAL archival to AWS S3, one bucket per cluster

> **Scope update (2026-07-30):** this contract now applies to **Dev/SIT only**. UAT and
> Prod are migrating from CNPG to AWS Aurora PostgreSQL (managed RDS) per
> [VPC Subnet Allocation and Boomi Networking Design](../superpowers/specs/2026-07-29-vpc-subnet-and-boomi-routing-design.md#database-engine-decision)
> and the Aurora Terraform resources in
> [platform-prerequisites/terraform/postgresql-core/main.tf](../../platform-prerequisites/terraform/postgresql-core/main.tf).

---

## Ownership & Maintenance

- **Platform Component:** CloudNativePG (CNPG) Operator
- **Maintained By:** Infrastructure Team
- **On-Call Contact:** [Define in deployment runbook]
- **Documentation:** This contract (postgresql-platform-contract.md)
- **Related Docs:** 
  - [Architect Reference](../guides/architect-reference.md)
  - [Component Catalog](component-catalog.md)
  - [Recovery Procedures](recovery-procedures.md) — Dev/SIT CNPG restore and PITR
  - [Environment Setup](../guides/environment-setup.md)
  - [Operator Runbook](../guides/operator-runbook.md)

---

## Component Overview

- **Operator:** CloudNativePG (CNPG)
- **Version:** Defined in `config/environment-schema/fragments/40-postgresql.manifest` (POSTGRESQL_VERSION)
- **Namespaces:** `coredb`, `branddb` (created by each cluster's Terraform root via the `cnpg-prereqs` module, not by the operator HelmRelease)
- **StorageClass:** gp3-postgresql (defined in gitops/postgresql/base/storageclass-gp3-postgresql.yaml, shared by both clusters)
- **Backup System:** Continuous WAL archival to AWS S3 with point-in-time recovery (PITR), one bucket per cluster
- **Replica Set:** 3-node configuration per cluster (configurable per environment via schema fragment)

---

## Lifecycle

### Provisioning Phase

#### Step 1: Terraform Prerequisites Provisioning
Each CNPG cluster (core, brand) has its own Terraform root provisioning its namespace, S3 backup bucket, and IAM pod-identity role via the shared `platform-prerequisites/terraform/modules/cnpg-prereqs` module — independent of each other, so either can be provisioned, resized, or destroyed without touching the other:

```bash
cp platform-prerequisites/terraform/postgresql-coredb/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-coredb/terraform.tfvars
# edit terraform.tfvars: set cluster_name, backup_bucket_name
bash scripts/provision-platform-prereq.sh pg-coredb

cp platform-prerequisites/terraform/postgresql-branddb/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-branddb/terraform.tfvars
# edit terraform.tfvars: set cluster_name, backup_bucket_name
bash scripts/provision-platform-prereq.sh pg-branddb
```

**Terraform Artifacts:**
- **Core root:** `platform-prerequisites/terraform/postgresql-coredb/` — namespace `coredb`, IAM role `postgresql-coredb-cnpg-role`, ServiceAccount `oms-postgresql-workload`
- **Brand root:** `platform-prerequisites/terraform/postgresql-branddb/` — namespace `branddb`, IAM role `postgresql-branddb-cnpg-role`, ServiceAccount `oms-postgresql-brand-workload`
- **Shared module:** `platform-prerequisites/terraform/modules/cnpg-prereqs/main.tf`

#### Step 2: GitOps Provisioning
GitOps deploys the shared CloudNativePG Operator once, then each cluster's Cluster custom resource independently:

```bash
cd /Users/frank/sml/oms/mongodb
bash scripts/provision.sh pg               # operator + both core and brand clusters
# or, independently:
bash scripts/provision-k8s-components.sh postgresql-coredb
bash scripts/provision-k8s-components.sh postgresql-branddb
```

**GitOps Artifacts:**
- **Base Configuration (shared operator):** `gitops/postgresql/base/` (kustomization.yaml, helm values, `postgresql-operator` namespace)
- **Core Overlay (Dev/SIT):** `gitops/postgresql-coredb/overlays/dev/` (namespace `coredb` + Cluster CR `oms-postgresql-coredb`)
- **Brand Overlay (Dev/SIT):** `gitops/postgresql-branddb/overlays/dev/` (namespace `branddb` + Cluster CR `oms-postgresql-branddb`)
- **Deployment:** HelmRelease CRD for `cloudnative-pg` chart (one operator instance manages both clusters)
- **Cluster Resources:** `oms-postgresql-coredb` (namespace `coredb`) and `oms-postgresql-branddb` (namespace `branddb`), each with:
  - IRSA enabled via `inheritFromIAMRole: true`
  - ServiceAccount: `oms-postgresql-workload` / `oms-postgresql-brand-workload` respectively (annotated with IRSA role ARN)
  - WAL archival configuration (own S3 bucket path, KMS key reference)
  - 3-node replica set (standard configuration)
  - Point-in-time recovery (PITR) enabled

#### Step 3: Provisioning Verification
```bash
# Check operator pod readiness
kubectl get pods -n postgresql-operator

# Check core cluster status
kubectl -n coredb get cluster oms-postgresql-coredb

# Check brand cluster status
kubectl -n branddb get cluster oms-postgresql-branddb

# Check replica set health (repeat for branddb/oms-postgresql-branddb)
kubectl -n coredb exec -it oms-postgresql-coredb-1 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"

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

Each cluster (core, brand) is destroyed independently, using its own namespace/cluster name pair:

| | Core | Brand |
|---|---|---|
| Namespace | `coredb` | `branddb` |
| Cluster name | `oms-postgresql-coredb` | `oms-postgresql-branddb` |
| ServiceAccount | `oms-postgresql-workload` | `oms-postgresql-brand-workload` |
| Backup bucket | operator-supplied, per `postgresql-coredb/terraform.tfvars` | operator-supplied, per `postgresql-branddb/terraform.tfvars` |

#### Pre-Destroy Guard Execution
Before any destruction, `verify_postgresql_pre_destroy_guard` is automatically executed:

```bash
bash scripts/provision.sh all --destroy
# Internally calls: verify_postgresql_pre_destroy_guard
# If guard fails → destruction is blocked
# If guard passes → destruction proceeds
```

#### Step 1: Guard Validation Protocol (7-Step Seam)

Run once per cluster, substituting the namespace/cluster-name pair from the table above.

**Seam Read:** Extract guard configuration from environment
```bash
POSTGRESQL_NAMESPACE=${POSTGRESQL_NAMESPACE:-"coredb"}       # or "branddb"
POSTGRESQL_CLUSTER_NAME=${POSTGRESQL_CLUSTER_NAME:-"oms-postgresql-coredb"}   # or oms-postgresql-branddb
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
If guard passes, destruction proceeds — core and brand can be destroyed independently:

1. **GitOps Removal (per cluster):**
   ```bash
   bash scripts/destroy.sh postgresql-coredb-overlay   # core only
   bash scripts/destroy.sh postgresql-branddb-overlay  # brand only
   # or bash scripts/destroy.sh postgresql-overlay      # both
   ```
   - Removes the targeted PostgreSQL Cluster custom resource(s)
   - `bash scripts/destroy.sh operators` (run separately, last) removes the shared CloudNativePG Operator HelmRelease — do this only after both overlays are removed, or you orphan the other cluster's StatefulSet/Pods
   - PersistentVolumes and PersistentVolumeClaims are Retained, not removed (see recovery-procedures.md)

2. **Terraform Destruction (per cluster's prerequisites):**
   ```bash
   cd platform-prerequisites/terraform/postgresql-coredb   # or postgresql-branddb
   terraform destroy
   ```
   - Removes the namespace, IAM role/pod-identity association, and S3 backup bucket created by the `cnpg-prereqs` module for that cluster only
   - Does not affect the other cluster's namespace, role, or bucket

#### Step 3: Post-Destruction Verification
```bash
# Verify no PostgreSQL pods remain (repeat for the other namespace)
kubectl get pods -n coredb

# Verify no PersistentVolumeClaims
kubectl get pvc -n coredb

# Verify no Cluster resources anywhere
kubectl get cluster -A

# Verify each cluster's S3 backup bucket is preserved (bucket name from its terraform.tfvars)
aws s3api head-bucket --bucket <backup_bucket_name>
```

**Success Criteria:**
- No PostgreSQL pods in the targeted namespace
- No PVCs in the targeted namespace
- No Cluster custom resources for the targeted cluster
- Its S3 bucket still contains WAL archives (for recovery if needed)

---

## Identities

### Pod Identity (AWS EKS Pod Identity)

Each cluster has its own IAM role and ServiceAccount, created by that cluster's Terraform root via the `cnpg-prereqs` module — not a shared "Phase 2" role.

| | Core | Brand |
|---|---|---|
| IAM role name | `postgresql-coredb-cnpg-role` | `postgresql-branddb-cnpg-role` |
| ServiceAccount | `oms-postgresql-workload` (namespace `coredb`) | `oms-postgresql-brand-workload` (namespace `branddb`) |

**Binding:** EKS Pod Identity association (`aws_eks_pod_identity_association`), not an IRSA OIDC annotation — see `platform-prerequisites/terraform/modules/cnpg-prereqs/main.tf`. The Cluster CR references the ServiceAccount directly via `serviceAccountName`; no `eks.amazonaws.com/role-arn` annotation is needed when Pod Identity is used (`use_pod_identity = true`, the default).

**IRSA fallback:** if `use_pod_identity = false` is set, the module instead annotates the ServiceAccount with `eks.amazonaws.com/role-arn` and binds via OIDC trust — see the module's `oidc_provider_arn`/`oidc_provider_url` variables.

---

### IAM Permissions

**Policy Name:** `<iam_role_name>-policy` (attached by the `cnpg-prereqs` module, one per cluster)

**S3 Permissions:**
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:AbortMultipartUpload",
    "s3:GetBucketLocation",
    "s3:GetObject",
    "s3:ListBucket",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::<backup_bucket_name>",
    "arn:aws:s3:::<backup_bucket_name>/*"
  ]
}
```

**Purpose:**
- `GetObject`: Read WAL archives from S3 (point-in-time recovery)
- `PutObject`: Write new WAL segments to S3
- `DeleteObject`: Clean up old WAL segments per retention policy
- `ListBucket`: Enumerate WAL objects for inventory and recovery

**KMS Permissions (only if `kms_key_arn` is set):**
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:Encrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "<kms_key_arn>"
}
```

**Purpose:**
- `Decrypt`: Decrypt WAL archives during point-in-time recovery
- `GenerateDataKey`/`Encrypt`: Encrypt WAL segments during S3 upload

---

### Kubernetes Secrets

**Native Kubernetes Secrets:** None

All AWS credentials are injected via EKS Pod Identity (or IRSA, if configured). No stored Kubernetes secrets for AWS credentials.

**PostgreSQL Internal Secrets (per cluster):**
- `<cluster-name>-superuser`: PostgreSQL superuser credentials (managed by CNPG operator, NOT exposed to external systems)
- `<cluster-name>-app-user`: Application database user credentials (if configured)

---

## Guard Semantics

### Pre-Destroy Guard: `verify_postgresql_pre_destroy_guard`

**Trigger:** Invoked automatically when `bash scripts/provision.sh all --destroy` is executed

**Purpose:** Prevent accidental destruction of a PostgreSQL cluster by validating:
1. Replica set is healthy and in sync
2. No active backups or WAL archival operations are in progress
3. AWS permissions are intact
4. Authorized operator is performing the destruction

**Protocol (7-Step Seam)**, run per cluster with its own namespace/cluster-name/bucket:

#### Seam Read
Extract configuration from environment:
```bash
POSTGRESQL_NAMESPACE=${POSTGRESQL_NAMESPACE:-"coredb"}       # or "branddb"
POSTGRESQL_CLUSTER_NAME=${POSTGRESQL_CLUSTER_NAME:-"oms-postgresql-coredb"}   # or oms-postgresql-branddb
POSTGRESQL_WAL_BUCKET=${POSTGRESQL_WAL_BUCKET:-"<that cluster's backup_bucket_name>"}
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

### AWS Prerequisites (created by each cluster's Terraform root)

Each cluster's namespace, IAM role, and S3 bucket are created by that cluster's own Terraform root (`postgresql-coredb` or `postgresql-branddb`) via the shared `cnpg-prereqs` module — not by an external "Phase 2" process. Run `bash scripts/provision-platform-prereq.sh pg-coredb` (or `pg-branddb`) before applying the Cluster CR.

#### 1. IAM Role: `postgresql-coredb-cnpg-role` / `postgresql-branddb-cnpg-role`

**Verification:**
```bash
aws iam get-role --role-name postgresql-coredb-cnpg-role   # or postgresql-branddb-cnpg-role
```

**What It Is:** An AWS IAM role with an EKS Pod Identity association (or OIDC trust, if `use_pod_identity=false`), allowing that cluster's pods to authenticate to AWS to archive WAL segments or perform backups.

**Created By:** `platform-prerequisites/terraform/postgresql-coredb` (or `postgresql-branddb`), via `platform-prerequisites/terraform/modules/cnpg-prereqs`.

#### 2. S3 Bucket: operator-supplied `backup_bucket_name`

**Verification:**
```bash
aws s3api head-bucket --bucket <backup_bucket_name>
```

**What It Is:** An S3 bucket for storing that cluster's PostgreSQL WAL (Write-Ahead Logs), created by the `cnpg-prereqs` module.

**Used By:** That cluster's CNPG Cluster CR (`spec.backup.barmanObjectStore.destinationPath`) for continuous WAL archival.

**Why It Matters:** WAL archives are the foundation for point-in-time recovery (PITR). Without this bucket, WAL segments are not archived and data recovery is impossible.

#### 3. AWS KMS Key (optional): operator-supplied `kms_key_arn`

**Verification:**
```bash
aws kms describe-key --key-id <kms_key_arn>
```

**What It Is:** An optional KMS key for encrypting WAL archives and backups in transit and at rest, if the operator sets `kms_key_arn` in that cluster's `terraform.tfvars`.

**Used By:** The `cnpg-prereqs` module's IAM policy, if provided.

**Why It Matters:** If set, WAL data is encrypted using this key; without it, S3 default (AES256) encryption is used instead.

### Kubernetes Prerequisites

#### 1. Namespaces: `coredb`, `branddb`

**Status:** Created by each cluster's Terraform root (`postgresql-coredb`/`postgresql-branddb`) via the `cnpg-prereqs` module — not by the operator HelmRelease.

**Verification:**
```bash
kubectl get namespace coredb branddb
```

#### 2. StorageClass: `gp3-postgresql`

**Status:** Defined in `gitops/postgresql/base/storageclass-gp3-postgresql.yaml`, shared by both clusters

**Verification:**
```bash
kubectl get storageclass gp3-postgresql
# Expected: Storage class with provisioner=ebs.csi.aws.com, parameters include gp3, encrypted=true
```

**Why It Matters:** Both clusters' PersistentVolumes use this storage class for high-performance block storage.

#### 3. Flux Controllers

**Status:** Must be active in cluster (bootstrapped via `--bootstrap-platform-controllers`)

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

#### Verify Each Cluster's Terraform Prerequisites Were Applied
```bash
# Verify IAM role exists (repeat for the other cluster's role name)
aws iam get-role --role-name postgresql-coredb-cnpg-role

# Verify S3 bucket is accessible (bucket name from that cluster's terraform.tfvars)
aws s3api head-bucket --bucket <backup_bucket_name>
```

#### Terraform Validation
```bash
cd platform-prerequisites/terraform/postgresql-coredb    # or postgresql-branddb
terraform fmt -check    # No formatting issues
terraform validate      # Valid HCL configuration
```

---

## Service Dependencies

### Depends On

- **EKS Cluster:** Must be running and accessible before PostgreSQL provisioning
  - Cluster name, endpoint, CA certificate
  - kubeconfig configured in `~/.kube/config`
  - kubectl connectivity verified

- **Per-Cluster IAM Role & Pod Identity Association:** Must exist, created by that cluster's own Terraform root
  - `postgresql-coredb-cnpg-role` / `postgresql-branddb-cnpg-role`

- **Per-Cluster S3 Backup Bucket:** Must exist, created by that cluster's own Terraform root
  - Encryption enabled (SSE-S3 by default, SSE-KMS if `kms_key_arn` is set)

- **Shared Kubernetes Storage:** Must be provisioned first
  - StorageClass `gp3-postgresql` defined in gitops/postgresql/base/

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
  - Uses a different namespace and storage class

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
  `platform-prerequisites/terraform/postgresql-core/variables.tf` and the
  `environments/{uat,prod}/*.tfvars` files are authoritative.
- **Dev/SIT (CNPG):** committed CNPG `Cluster` manifests are at
  `gitops/postgresql-coredb/overlays/dev/cluster.yaml` and
  `gitops/postgresql-branddb/overlays/dev/cluster.yaml`, wired into provisioning
  via `scripts/provision.sh pg` (which calls the `postgresql` scope in
  `scripts/provision-k8s-components.sh`) or independently via the
  `postgresql-coredb`/`postgresql-branddb` scopes.

1. **scripts/verify-platform-health.sh --smoke-test**
   - Verifies PostgreSQL is accessible
   - Validates WAL archival is functioning

---

## Related Documentation

- [Environment Setup Guide](../guides/environment-setup.md) - Step-by-step platform setup
- [Operator Runbook](../guides/operator-runbook.md) - Operational procedures
- [Recovery Procedures](recovery-procedures.md) - Disaster recovery steps
- [Audit Log Contract](audit-log-contract.md) - Audit logging requirements
- [Component Catalog](component-catalog.md) - All platform components
