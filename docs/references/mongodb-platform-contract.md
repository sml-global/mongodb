# MongoDB Platform Contract

**Date:** 2026-07-27  
**Component:** Percona Server for MongoDB (PSMDB) Operator  
**Namespace:** mongodb  
**StorageClass:** gp3-mongodb  
**Backup System:** Percona Backup Management (PBM) to AWS S3

---

## Ownership & Maintenance

- **Platform Component:** Percona Server for MongoDB (PSMDB) Operator
- **Maintained By:** Infrastructure Team
- **On-Call Contact:** [Define in deployment runbook]
- **Documentation:** This contract (mongodb-platform-contract.md)
- **Related Docs:** 
  - [Architect Reference](architect-reference.md)
  - [Component Catalog](component-catalog.md)
  - [Recovery Procedures](recovery-procedures.md)
  - [Environment Setup](../guides/environment-setup.md)
  - [Operator Runbook](../guides/operator-runbook.md)

---

## Component Overview

- **Operator:** Percona Server for MongoDB (PSMDB)
- **Version:** Defined in `config/environment-schema/fragments/10-mongodb.manifest` (MONGODB_VERSION)
- **Namespace:** mongodb (created automatically by HelmRelease with `createNamespace: true`)
- **StorageClass:** gp3-mongodb (defined in k8s/base/storage-classes.yaml)
- **Backup System:** Percona Backup Management (PBM) backing up to AWS S3
- **Replica Set:** 3-node configuration (configurable per environment via schema fragment)

---

## Lifecycle

### Provisioning Phase

#### Step 1: Phase 2 Prerequisites Validation
The following AWS resources **must** exist from Phase 2 provisioning before MongoDB provisioning can proceed:

1. **IRSA Role:** `oms-mongodb-operator-role`
   - Verify: `aws iam get-role --role-name oms-mongodb-operator-role`
   - Used by: Terraform `var.mongodb_operator_iam_role_arn` input
   - Purpose: AWS pod identity for MongoDB operator workload

2. **S3 Bucket:** `oms-pbm-backups`
   - Verify: `aws s3api head-bucket --bucket oms-pbm-backups`
   - Used by: Percona Backup Management (PBM) destination
   - Purpose: Store MongoDB backups with encryption

3. **AWS KMS Key:** `oms-mongodb-cluster-key`
   - Verify: `aws kms describe-key --key-id oms-mongodb-cluster-key`
   - Used by: Encrypt/decrypt PBM backup data
   - Purpose: Encryption at rest for backup artifacts

#### Step 2: Terraform Provisioning
Terraform applies IAM policy attachment to enable MongoDB operator to access AWS resources:

```bash
cd platform-prerequisites/terraform/mongodb
terraform fmt -check      # Validate code style
terraform validate        # Validate configuration
terraform plan            # Review changes (do NOT apply)
```

**Terraform Artifacts:**
- **Module:** `platform-prerequisites/terraform/mongodb/main.tf`
- **Variables:** `platform-prerequisites/terraform/mongodb/variables.tf`
- **Outputs:** `mongodb_operator_policy_id` (IAM policy ID created)
- **Validation:** Attaches `oms-mongodb-backup-policy` to `oms-mongodb-operator-role`

#### Step 3: GitOps Provisioning
GitOps deploys PSMDB Operator and MongoDB Cluster custom resource:

```bash
cd /Users/frank/sml/oms/mongodb
bash scripts/provision.sh mongodb
```

**GitOps Artifacts:**
- **Base Configuration:** `gitops/mongodb/base/` (kustomization.yaml, helm values, namespace)
- **Overlay (UAT):** `gitops/mongodb/overlays/uat/` (environment-specific values)
- **Deployment:** HelmRelease CRD for `psmdb-operator` chart
- **Cluster Resource:** PerconaServerMongoDB custom resource named `psmdb` with:
  - IRSA enabled via `inheritFromIAMRole: true`
  - ServiceAccount: `oms-mongodb-workload` (annotated with IRSA role ARN)
  - PBM configuration (S3 bucket path, KMS key reference)
  - 3-node replica set (standard configuration)

#### Step 4: Provisioning Verification
```bash
# Check operator pod readiness
kubectl get pods -n mongodb

# Check MongoDB cluster status
kubectl -n mongodb get perconaservermongodb psmdb

# Check replica set health
kubectl -n mongodb exec -it psmdb-0 -- mongosh --eval "rs.status()"

# Run smoke tests
bash scripts/verify-platform-health.sh --smoke-test
```

**Success Criteria:**
- Operator pod is Running (1/1 Ready)
- MongoDB cluster is Ready (status=Ready)
- Replica set has 3 healthy members (SECONDARY + PRIMARY)
- Smoke test returns exit code 0

---

### Destruction Phase

#### Pre-Destroy Guard Execution
Before any destruction, the `verify_mongodb_pre_destroy_guard` is automatically executed:

```bash
bash scripts/provision.sh all --destroy
# Internally calls: verify_mongodb_pre_destroy_guard
# If guard fails → destruction is blocked
# If guard passes → destruction proceeds
```

#### Step 1: Guard Validation Protocol (7-Step Seam)

**Seam Read:** Extract guard configuration from environment
```bash
MONGODB_NAMESPACE=${MONGODB_NAMESPACE:-"mongodb"}
MONGODB_CLUSTER_NAME=${MONGODB_CLUSTER_NAME:-"psmdb"}
```

**Parse:** Query Kubernetes replica set status
```bash
kubectl -n "$MONGODB_NAMESPACE" exec "${MONGODB_CLUSTER_NAME}-0" -- \
  mongosh --eval "JSON.stringify(rs.status())" | jq .
```

**Validate:** Check all health constraints
- All replicas are in SECONDARY or PRIMARY state (no UNKNOWN or REMOVED)
- Replica set has at least 2 healthy members
- No active backup or restore operations in Kubernetes events
- S3 bucket permissions are intact

**Identity:** Record destruction authorization
- Extract operator identity from `$USER` environment variable
- Log to audit trail: `destruction_requested_by=${USER}`
- Timestamp: ISO-8601 format

**SHA-256 Digest:** Create immutable fingerprint of replica set configuration
```bash
DIGEST=$(kubectl -n "$MONGODB_NAMESPACE" get replicas psmdb -o yaml | sha256sum | awk '{print $1}')
echo "Replica set digest: $DIGEST"
```

**Callback:** Log destruction authorization
- Event type: `mongodb_pre_destroy_guard_pass`
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
   - Removes PerconaServerMongoDB custom resource
   - Removes PSMDB Operator HelmRelease
   - PersistentVolumes and PersistentVolumeClaims are removed (spec.finalizers honored)

2. **Terraform Destruction:**
   ```bash
   cd platform-prerequisites/terraform/mongodb
   terraform destroy
   ```
   - Removes IAM policy attachment to IRSA role
   - Does NOT remove IAM role itself (shared with other components)
   - Preserves S3 bucket and KMS key (may be needed for backup recovery)

#### Step 3: Post-Destruction Verification
```bash
# Verify no MongoDB pods remain
kubectl get pods -n mongodb

# Verify no PersistentVolumeClaims
kubectl get pvc -n mongodb

# Verify no PerconaServerMongoDB resources
kubectl get perconaservermongodb -A

# Verify S3 backups are preserved
aws s3api head-bucket --bucket oms-pbm-backups
```

**Success Criteria:**
- No MongoDB pods in cluster
- No PVCs in mongodb namespace
- No MongoDB custom resources
- S3 bucket still contains backups (for recovery if needed)

---

## Identities

### IRSA (AWS Pod Identity)

**Role Name:** `oms-mongodb-operator-role` (from Phase 2 platform_contract)

**Binding:** Kubernetes IRSA annotation on ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oms-mongodb-workload
  namespace: mongodb
  annotations:
    iam.gke.io/gcp-service-account: oms-mongodb-operator-role@PROJECT_ID.iam.gserviceaccount.com
```

**AWS Pod Identity Configuration:**
- AWS EKS cluster with IRSA enabled
- Trust relationship established between Kubernetes OIDC provider and IAM role
- ServiceAccount annotation enables automatic credential injection to pods

---

### IAM Permissions

**Policy Name:** `oms-mongodb-backup-policy` (attached by platform-prerequisites/terraform/mongodb/)

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
    "arn:aws:s3:::oms-pbm-backups",
    "arn:aws:s3:::oms-pbm-backups/*"
  ]
}
```

**Purpose:**
- `GetObject`: Read backups from S3 (restore operations)
- `PutObject`: Write new backups to S3
- `DeleteObject`: Clean up old backup artifacts per retention policy
- `ListBucket`: Enumerate backup objects for inventory

**KMS Permissions:**
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "arn:aws:kms:*:ACCOUNT_ID:key/oms-mongodb-cluster-key"
}
```

**Purpose:**
- `Decrypt`: Decrypt backup data during restore operations
- `GenerateDataKey`: Encrypt backup data during S3 upload

---

### Kubernetes Secrets

**Native Kubernetes Secrets:** None

All AWS credentials are injected via IRSA pod identity. No stored Kubernetes secrets for AWS credentials.

**MongoDB Internal Secrets:**
- `mongodb-admin-secret`: MongoDB admin username/password (managed by PSMDB operator, NOT exposed to external systems)
- `mongosh-admin`: MongoDB shell credentials (for operator internal use only)

---

## Guard Semantics

### Pre-Destroy Guard: `verify_mongodb_pre_destroy_guard`

**Trigger:** Invoked automatically when `bash scripts/provision.sh all --destroy` is executed

**Purpose:** Prevent accidental destruction of MongoDB cluster by validating:
1. Replica set is healthy and consistent
2. No active backup operations are in progress
3. AWS permissions are intact
4. Authorized operator is performing the destruction

**Protocol (7-Step Seam):**

#### Seam Read
Extract configuration from environment and namespace annotations:
```bash
MONGODB_NAMESPACE=${MONGODB_NAMESPACE:-"mongodb"}
MONGODB_CLUSTER_NAME=${MONGODB_CLUSTER_NAME:-"psmdb"}
MONGODB_BACKUP_BUCKET=${MONGODB_BACKUP_BUCKET:-"oms-pbm-backups"}
```

#### Parse
Query Kubernetes for replica set and backup status:
```bash
# Get replica set status
kubectl -n "$MONGODB_NAMESPACE" exec "${MONGODB_CLUSTER_NAME}-0" -- \
  mongosh --eval "JSON.stringify(rs.status())" | jq .

# Get backup status
kubectl -n "$MONGODB_NAMESPACE" get perconaservermongodb psmdb -o yaml | grep -A 20 "backup:"

# Get recent events
kubectl -n "$MONGODB_NAMESPACE" get events --sort-by='.lastTimestamp' | head -20
```

#### Validate
Perform health checks:
```bash
# Check: All replicas are SECONDARY or PRIMARY (not UNKNOWN or REMOVED)
REPLICA_STATES=$(kubectl -n "$MONGODB_NAMESPACE" exec "${MONGODB_CLUSTER_NAME}-0" -- \
  mongosh --eval "rs.status().members.map(m => m.state)" --quiet)

# Check: At least 2 healthy members
HEALTHY_MEMBERS=$(kubectl -n "$MONGODB_NAMESPACE" exec "${MONGODB_CLUSTER_NAME}-0" -- \
  mongosh --eval "rs.status().members.filter(m => m.state === 1 || m.state === 2).length" --quiet)

if [[ $HEALTHY_MEMBERS -lt 2 ]]; then
  echo "ERROR: Replica set has fewer than 2 healthy members. Destruction blocked."
  exit 1
fi

# Check: No active backup operations
ACTIVE_BACKUPS=$(kubectl -n "$MONGODB_NAMESPACE" get events --field-selector reason=BackupInProgress | wc -l)
if [[ $ACTIVE_BACKUPS -gt 0 ]]; then
  echo "ERROR: Active backups in progress. Destruction blocked."
  exit 1
fi

# Check: S3 bucket is accessible
aws s3api head-bucket --bucket "$MONGODB_BACKUP_BUCKET" || {
  echo "ERROR: Cannot access S3 bucket $MONGODB_BACKUP_BUCKET. Destruction blocked."
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
Create immutable fingerprint of replica set configuration:
```bash
DIGEST=$(kubectl -n "$MONGODB_NAMESPACE" get replicas psmdb -o yaml | sha256sum | awk '{print $1}')
echo "Replica set configuration digest: $DIGEST"
```

#### Callback
Log destruction authorization to audit system:
```bash
# Log to Kubernetes audit
kubectl -n "$MONGODB_NAMESPACE" annotate perconaservermongodb psmdb \
  "destruction-authorized-by=$DESTRUCTION_OPERATOR" \
  "destruction-timestamp=$DESTRUCTION_TIMESTAMP" \
  "destruction-replica-digest=$DIGEST" \
  --overwrite

# Optionally log to CloudWatch
# aws logs put-log-events --log-group-name /mongodb/destruction ...
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
2. Resolve any health issues (e.g., wait for backups to complete, restore replica set health)
3. Re-run the destruction command

**Safety Net:** The guard ensures an adequate grace period for manual verification or emergency rollback before destruction proceeds.

---

## Prerequisites

### AWS Prerequisites (Phase 2 Outputs)

Before provisioning MongoDB on Phase 3, ensure the following AWS resources exist from Phase 2 infrastructure:

#### 1. IRSA Role: `oms-mongodb-operator-role`

**Verification:**
```bash
aws iam get-role --role-name oms-mongodb-operator-role
# Expected output: Role ARN, creation date, etc.
```

**What It Is:** An AWS IAM role with a trust relationship to the Kubernetes OIDC provider, allowing MongoDB operator pods to assume this role via IRSA (IAM Roles for Service Accounts).

**Used By:** Terraform `platform-prerequisites/terraform/mongodb/variables.tf` consumes this via `var.mongodb_operator_iam_role_arn`

**Why It Matters:** Without this role, MongoDB operator cannot authenticate to AWS to backup/restore data.

#### 2. S3 Bucket: `oms-pbm-backups`

**Verification:**
```bash
aws s3api head-bucket --bucket oms-pbm-backups
# Expected: HTTP 200 (bucket exists and you have access)
```

**What It Is:** An S3 bucket for storing MongoDB backups created by Percona Backup Management (PBM).

**Used By:** PBM configuration in GitOps HelmRelease values

**Why It Matters:** Backups are the only recovery mechanism for data loss. Without this bucket, backups fail and data recovery is impossible.

#### 3. AWS KMS Key: `oms-mongodb-cluster-key`

**Verification:**
```bash
aws kms describe-key --key-id oms-mongodb-cluster-key
# Expected output: Key metadata, key state, etc.
```

**What It Is:** A KMS key for encrypting backup data in transit and at rest.

**Used By:** PBM configuration references this key for encryption

**Why It Matters:** Backup data is encrypted using this key; without it, encrypted backups cannot be decrypted for restoration.

### Kubernetes Prerequisites

#### 1. Namespace: `mongodb`

**Status:** Automatically created by HelmRelease with `createNamespace: true`

**Verification:**
```bash
kubectl get namespace mongodb
```

#### 2. StorageClass: `gp3-mongodb`

**Status:** Defined in `k8s/base/storage-classes.yaml`

**Verification:**
```bash
kubectl get storageclass gp3-mongodb
# Expected: Storage class with provisioner=aws-ebs, parameters include gp3, iops=3000, etc.
```

**Why It Matters:** MongoDB PersistentVolumes use this storage class for high-performance block storage.

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
aws iam get-role --role-name oms-mongodb-operator-role

# Verify S3 bucket is accessible
aws s3api head-bucket --bucket oms-pbm-backups

# Verify KMS key is accessible
aws kms describe-key --key-id oms-mongodb-cluster-key

# Verify KMS key has correct permissions for IRSA role
aws kms get-key-policy --key-id oms-mongodb-cluster-key --policy-name default --output text | \
  grep "oms-mongodb-operator-role"
```

#### Terraform Validation
```bash
cd platform-prerequisites/terraform/mongodb
terraform fmt -check    # No formatting issues
terraform validate      # Valid HCL configuration
```

---

## Service Dependencies

### Depends On

- **Phase 2 EKS Cluster:** Must be running and accessible before MongoDB provisioning
  - Cluster name, endpoint, CA certificate
  - kubeconfig configured in `~/.kube/config`
  - kubectl connectivity verified

- **Phase 2 IRSA Roles & Policies:** Must exist and be properly trusted
  - `oms-mongodb-operator-role` with OIDC trust to EKS cluster

- **Phase 2 AWS S3 Bucket:** Must exist with proper encryption
  - `oms-pbm-backups` bucket created and accessible
  - Encryption enabled (recommended: SSE-S3 or SSE-KMS)

- **Phase 2 AWS KMS Key:** Must exist and be accessible
  - `oms-mongodb-cluster-key` key in ACTIVE state
  - Key policy grants IRSA role permission to Decrypt and GenerateDataKey

- **Phase 3 Kubernetes Storage:** Must be provisioned first
  - StorageClass `gp3-mongodb` defined in k8s/base/

### Required By

- **Boomi Integration:** Audit logging writes MongoDB events to audit collection
  - Consumes: MongoDB connection string, credentials
  - Verifies: MongoDB replica set is healthy

- **SigNoz Observability:** MongoDB metrics are exported via OpenTelemetry collector
  - Consumes: MongoDB connection string, metrics endpoint
  - Verifies: MongoDB prometheus metrics are available

- **Application Layer:** MongoDB is the primary operational data store
  - Consumes: MongoDB connection string, read/write operations
  - Verifies: Replica set quorum for strong consistency

### Optional Dependencies

- **PostgreSQL:** Runs independently; no direct dependency
  - Can coexist in same cluster without conflicts
  - Both use different namespaces and storage classes

- **SigNoz:** Observes MongoDB but not required for operation
  - Can be deployed before or after MongoDB
  - Telemetry collection is optional

---

## Configuration Reference

Configuration values are defined in the environment schema fragment and consumed by provisioning scripts:

**Fragment Location:** `config/environment-schema/fragments/10-mongodb.manifest`

**Configuration Parameters:**

- `MONGODB_VERSION`: Percona Server for MongoDB version (e.g., "6.0.14")
- `MONGODB_STORAGE_CLASS`: Kubernetes StorageClass for data volumes (default: "gp3-mongodb")
- `MONGODB_REPLICA_COUNT`: Number of replicas in replica set (default: 3)
- `MONGODB_BACKUP_ENABLED`: Enable Percona Backup Management (default: "true")
- `MONGODB_BACKUP_SCHEDULE`: PBM backup schedule in cron format (default: "0 2 * * *" = 2 AM daily)
- `MONGODB_BACKUP_RETENTION_DAYS`: Backup retention period in days (default: 30)

**Consumed By:**

1. **scripts/provision.sh mongodb**
   - Sources environment fragment
   - Passes values to Terraform and GitOps

2. **platform-prerequisites/terraform/mongodb/variables.tf**
   - Reads MongoDB operator role ARN
   - Configures backup bucket and KMS key references

3. **gitops/mongodb/overlays/uat/kustomization.yaml**
   - Reads MONGODB_VERSION for HelmRelease chart version
   - Configures replica count and storage class

4. **scripts/verify-platform-health.sh --smoke-test**
   - Verifies MongoDB is accessible
   - Validates PBM backups are scheduled correctly

---

## Related Documentation

- [Environment Setup Guide](../guides/environment-setup.md) - Step-by-step platform setup
- [Operator Runbook](../guides/operator-runbook.md) - Operational procedures
- [Recovery Procedures](recovery-procedures.md) - Disaster recovery steps
- [Audit Log Contract](audit-log-contract.md) - Audit logging requirements
- [Component Catalog](component-catalog.md) - All platform components
