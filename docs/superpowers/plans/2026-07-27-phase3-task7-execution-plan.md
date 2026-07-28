# Phase 3 Task 7: Contract Documentation + Final Gates — Execution Plan

**Date:** 2026-07-27  
**Status:** READY FOR EXECUTION  
**Gatekeeper Approval:** All 4 perspectives CLEAR  
**Branch:** `feat/phase3-workload-platforms`  
**Worktree:** `/Users/frank/sml/oms/mongodb/.worktrees/phase3-workload-platforms`

---

## Gatekeeper Alignment Summary

| Perspective | Status | Key Requirement |
|---|---|---|
| AWS Architect | ✅ CLEAR | Contract docs reference Phase 2 prerequisites (IRSA roles, KMS, S3) accurately |
| DevOps | ✅ CLEAR | ClickHouse secret prerequisites documented + bootstrap script requirement in contract |
| Software Architect | ✅ CLEAR | Documentation tests verify content quality (not just header existence) |
| Superpowers Creator | ✅ CLEAR | Atomic commit boundary defined; post-Task 7 manual review before merge |

**All 4 perspectives are aligned.** Proceed with execution.

---

## Task 7: Deliverables & Detailed Specifications

### Deliverable 1: Contract Documentation (3 markdown files)

#### 1.1 docs/references/mongodb-platform-contract.md

**Purpose:** Single source of truth for MongoDB operator lifecycle, identities, prerequisites, and operational guardrails.

**Required Sections:**

```markdown
# MongoDB Platform Contract

## Ownership & Maintenance
- Platform Component: MongoDB PSMDB Operator
- Maintained By: Infrastructure Team
- On-Call Contact: [Define in deployment]
- Documentation: This contract (mongodb-platform-contract.md)
- Related Docs: [Link to Architect Reference, Component Catalog, Recovery Procedures]

## Component Overview
- Operator: Percona Server for MongoDB (PSMDB)
- Version: [From environment schema fragment 10-mongodb.manifest]
- Namespace: mongodb
- StorageClass: gp3-mongodb
- Backup: Percona Backup Management (PBM) to AWS S3

## Lifecycle

### Provisioning
1. **Phase 2 Prerequisites:**
   - AWS EKS cluster running
   - IRSA (AWS pod identity) role: `oms-mongodb-operator-role`
   - S3 bucket for PBM backups: `oms-pbm-backups`
   - KMS key for encryption: `oms-mongodb-cluster-key`

2. **Terraform (platform-prerequisites/terraform/mongodb/):**
   - Attaches IAM policy to IRSA role
   - Validates role ARN format, S3 bucket, KMS key existence
   - Outputs: `mongodb_operator_policy_id`
   - Command: `bash scripts/provision.sh mongodb`

3. **GitOps (gitops/mongodb/base/ + gitops/mongodb/overlays/uat/):**
   - Deploys PSMDB Operator via Helm
   - Creates MongoDB Cluster CR with:
     - IRSA enabled via `inheritFromIAMRole: true`
     - ServiceAccount: `oms-mongodb-workload`
     - PBM backup configuration (S3 path, KMS key reference)
     - 3-node replica set (dev), UAT configurable
   - Command: `bash scripts/provision.sh mongodb`

4. **Verification:**
   - Pod readiness: `kubectl get pods -n mongodb`
   - Replica set health: `kubectl -n mongodb exec -it psmdb-0 -- mongosh --eval "rs.status()"`
   - Smoke test: `bash scripts/verify-platform-health.sh --smoke-test`

### Destruction
1. **Pre-Destroy Guard:** Runs `verify_mongodb_pre_destroy_guard` (details in Guard Semantics section)
   - Validates replica set is healthy
   - Validates no active backups in progress
   - Checks S3 bucket permissions
   - Returns: SHA-256 digest of replica set config
   - If validation fails: Destruction is blocked until guard passes

2. **Actual Destruction:**
   - GitOps: `bash scripts/provision.sh all --destroy` removes PSMDB Cluster CR and Operator
   - Terraform: `terraform destroy` removes IAM policy attachment
   - Namespace cleanup: Manual (Flux removes resources; namespace may persist for debugging)

3. **Post-Destruction Verification:**
   - PVC cleanup: `kubectl get pvc -n mongodb` (should be empty)
   - S3 bucket: Retained for disaster recovery
   - KMS key: Retained (may be needed for backup recovery)

## Identities

### IRSA (AWS Pod Identity)
- **Role Name:** `oms-mongodb-operator-role` (from Phase 2 platform_contract)
- **Role ARN:** Consumed from `var.mongodb_operator_iam_role_arn` (Terraform input)
- **Service Account:** `oms-mongodb-workload`
- **Namespace:** mongodb
- **Annotation:** `iam.gke.io/gcp-service-account` (for EKS pod identity binding)

### IAM Permissions
**Policy:** `oms-mongodb-backup-policy` (attached by platform-prerequisites/terraform/mongodb/main.tf)

Permissions:
- **S3 Actions:**
  - `s3:GetObject` - Read backups from S3
  - `s3:PutObject` - Write backups to S3
  - `s3:DeleteObject` - Clean up old backups
  - `s3:ListBucket` - List backup artifacts
  - Resource: `arn:aws:s3:::oms-pbm-backups/*`

- **KMS Actions:**
  - `kms:Decrypt` - Decrypt backup data
  - `kms:GenerateDataKey` - Encrypt backup data during upload
  - Resource: `arn:aws:kms:*:ACCOUNT_ID:key/oms-mongodb-cluster-key`

### Kubernetes Secrets
- None. IRSA credentials are injected via AWS pod identity; no stored secrets.

## Guard Semantics

### Pre-Destroy Guard: `verify_mongodb_pre_destroy_guard`

**Triggered:** When destruction is requested (`bash scripts/provision.sh all --destroy`)

**Protocol (7-step seam):**

1. **Seam Read:** Extract guard configuration from environment:
   ```bash
   MONGODB_NAMESPACE=${MONGODB_NAMESPACE:-"mongodb"}
   MONGODB_CLUSTER_NAME=${MONGODB_CLUSTER_NAME:-"psmdb"}
   ```

2. **Parse:** Query Kubernetes for replica set status:
   ```bash
   kubectl -n "$MONGODB_NAMESPACE" exec "${MONGODB_CLUSTER_NAME}-0" -- \
     mongosh --eval "JSON.stringify(rs.status())" | jq .
   ```

3. **Validate:** Check:
   - All replicas are in `SECONDARY` or `PRIMARY` state (no `UNKNOWN` or `REMOVED`)
   - Replica set has at least 2 healthy members
   - No active `backup` or `restore` operations in Kubernetes events

4. **Identity:** Record which admin/operator invoked destruction:
   - Extract from `$USER` environment variable
   - Log to audit trail: `destruction-request-by=${USER}`

5. **SHA-256 Digest:** Create immutable fingerprint:
   ```bash
   DIGEST=$(kubectl -n "$MONGODB_NAMESPACE" get replicas psmdb -o yaml | sha256sum | awk '{print $1}')
   ```

6. **Callback:** Log destruction authorization to audit log:
   - Event: `mongodb_pre_destroy_guard_pass`
   - Digest: $DIGEST
   - Timestamp: ISO-8601

7. **Return:** Exit code 0 if all checks pass; non-zero if any validation fails

**Failure Behavior:** If guard fails, destruction is blocked. Admin must investigate and resolve issues before retrying.

**Safety Net:** Guard prevents accidental cluster destruction; allows time for manual verification or rollback.

## Prerequisites

### AWS Prerequisites (Phase 2 Outputs)
Ensure the following AWS resources exist from Phase 2 provisioning:

1. **IRSA Role:** `oms-mongodb-operator-role`
   - Verify: `aws iam get-role --role-name oms-mongodb-operator-role`
   - Used by: Terraform `var.mongodb_operator_iam_role_arn` input

2. **S3 Bucket:** `oms-pbm-backups`
   - Verify: `aws s3api head-bucket --bucket oms-pbm-backups`
   - Used by: PBM backup destination
   - Terraform validates bucket exists and has correct ownership

3. **KMS Key:** `oms-mongodb-cluster-key`
   - Verify: `aws kms describe-key --key-id oms-mongodb-cluster-key`
   - Used by: Encrypt/decrypt backup data
   - Terraform grants IRSA role permission to use this key

### Kubernetes Prerequisites
1. **Namespace:** `mongodb` (created automatically by HelmRelease `createNamespace: true`)
2. **StorageClass:** `gp3-mongodb` (must exist from Phase 3 k8s/base/)
3. **Flux Controllers:** FluxCD Helm Controller active in cluster

### Operator Prerequisites
1. **Terraform Validation:**
   ```bash
   cd platform-prerequisites/terraform/mongodb
   terraform fmt -check  # Code style validation
   terraform validate    # Configuration validation
   terraform plan        # Review IAM policy attachment (do NOT apply)
   ```

2. **Check AWS Permissions:**
   ```bash
   bash scripts/verify-platform-health.sh --preflight
   ```

3. **Verify Phase 2 Outputs:**
   ```bash
   # Verify IRSA role exists
   aws iam get-role --role-name oms-mongodb-operator-role
   
   # Verify S3 bucket exists
   aws s3api head-bucket --bucket oms-pbm-backups
   
   # Verify KMS key exists
   aws kms describe-key --key-id oms-mongodb-cluster-key
   ```

## Service Dependencies

### Depends On
- **Phase 2 EKS Cluster:** Must be running before MongoDB provisioning
- **IRSA Roles & Policies:** From Phase 2 platform_contract
- **AWS S3 Bucket:** For PBM backups (created by Phase 2 infrastructure)
- **AWS KMS Key:** For backup encryption (created by Phase 2 infrastructure)
- **Kubernetes StorageClass:** `gp3-mongodb` from Phase 3 k8s/base/

### Required By
- **Boomi Integration:** Audit logging writes to MongoDB audit collection
- **SigNoz Observability:** MongoDB metrics exported via OTel collector
- **Application Layer:** MongoDB serves as primary data store

### Optional Dependencies
- **PostgreSQL:** Independent; can coexist without conflicts
- **SigNoz:** Independent; can observe MongoDB but not required for operation

## Configuration Reference

See `config/environment-schema/fragments/10-mongodb.manifest` for:
- MONGODB_VERSION
- MONGODB_STORAGE_CLASS
- MONGODB_REPLICA_COUNT
- MONGODB_BACKUP_ENABLED
- MONGODB_BACKUP_SCHEDULE

Environment variables are consumed by:
- `scripts/provision.sh` (provisions resources)
- `scripts/verify-platform-health.sh` (validates deployment)
- `gitops/mongodb/overlays/uat/` (applies environment-specific patches)
```

**Validation Checks in Tests:**
- File exists: `docs/references/mongodb-platform-contract.md`
- Contains: `### Ownership & Maintenance`
- Contains: `### Lifecycle` with Provisioning and Destruction
- Contains: `### Identities` with IRSA and IAM permissions
- Contains: `### Guard Semantics` with 7-step protocol
- Contains: `### Prerequisites` with AWS (IRSA, S3, KMS), Kubernetes, and Operator prerequisites
- Prerequisites mentions: "IRSA", "oms-mongodb-operator-role", "oms-pbm-backups", "KMS", "S3"
- Guard Semantics mentions: "pre-destroy", "validate", "SHA-256", "replica set", "backup"

---

#### 1.2 docs/references/postgresql-platform-contract.md

**Purpose:** Single source of truth for PostgreSQL operator lifecycle, identities, prerequisites, and operational guardrails.

**Structure:** Identical to MongoDB contract, with PostgreSQL-specific content:

**Key Differences from MongoDB:**
- Operator: CloudNativePG (Postgres Operator)
- ServiceAccount: `oms-postgresql-workload`
- Namespace: postgresql
- Backup: CloudNativePG backup storage to AWS S3
- IRSA Role: `oms-postgresql-operator-role` (from Phase 2)
- S3 Bucket: `oms-cnpg-backups`
- KMS Key: `oms-postgresql-cluster-key`

**Required Sections:** Same 8 sections as MongoDB
1. Ownership & Maintenance
2. Component Overview
3. Lifecycle (Provisioning, Destruction)
4. Identities (IRSA, IAM Permissions, Kubernetes Secrets - none)
5. Guard Semantics (Pre-Destroy Guard 7-step protocol)
6. Prerequisites (AWS + Kubernetes + Operator)
7. Service Dependencies
8. Configuration Reference

**Validation Checks in Tests:**
- Same as MongoDB tests, but with PostgreSQL-specific keywords:
- Contains: "CloudNativePG", "postgresql_operator_iam_role_arn"
- Prerequisites mentions: "IRSA", "oms-postgresql-operator-role", "oms-cnpg-backups", "KMS", "S3"
- Guard Semantics mentions: "pre-destroy", "validate", "SHA-256"

---

#### 1.3 docs/references/signoz-platform-contract.md

**Purpose:** Single source of truth for SigNoz observability platform, lifecycle, identities, and prerequisites.

**Key Differences from MongoDB/PostgreSQL:**
- No AWS IRSA required
- **ClickHouse Secret is REQUIRED:** `signoz-clickhouse` with root password
- **SigNoz Root User Secret:** `signoz-root-user` for UI admin account
- Namespace: signoz
- Storage: Persistent volumes via EBS (gp3-mongodb StorageClass)

**Required Sections:** Same 8 sections, with SigNoz specifics:

```markdown
# SigNoz Platform Contract

## Ownership & Maintenance
- Platform Component: SigNoz Observability Platform (ClickHouse + Kafka + UI)
- Maintained By: Infrastructure Team
- On-Call Contact: [Define in deployment]
- Documentation: This contract (signoz-platform-contract.md)
- Related Docs: [Link to SigNoz Dashboard Import Pack, Architect Reference]

## Component Overview
- Platform: SigNoz v0.130.1 (helm chart)
- K8s Infra: SigNoz k8s-infra v0.16.0 (Kubernetes cluster metadata exporter)
- Storage: ClickHouse (time-series database) + Kafka (event queue)
- Namespace: signoz
- StorageClass: gp3-mongodb (EBS volumes)
- Secrets: signoz-clickhouse (ClickHouse admin), signoz-root-user (SigNoz admin)

## Lifecycle

### Provisioning
1. **Prerequisites:**
   - Kubernetes Secret: `signoz-clickhouse` (created by scripts/create-signoz-clickhouse-secret.sh)
   - Kubernetes Secret: `signoz-root-user` (created by scripts/create-signoz-root-user-secret.sh)

2. **Terraform (platform-prerequisites/terraform/signoz/):**
   - No AWS resources required; validation only
   - Outputs: Confirmation that prerequisites are met
   - Command: `bash scripts/provision.sh signoz`

3. **Secret Bootstrap (Scripts):**
   - Create ClickHouse Secret:
     ```bash
     bash scripts/create-signoz-clickhouse-secret.sh [--password <password>]
     ```
   - Create SigNoz Root User Secret:
     ```bash
     bash scripts/create-signoz-root-user-secret.sh [--email <email>] [--namespace signoz]
     ```

4. **GitOps (gitops/signoz/base/ + gitops/signoz/overlays/uat/):**
   - Deploys SigNoz operator and ClickHouse via Helm
   - References secrets created in step 3:
     - `clickhouse.password.valueFrom.secretKeyRef.name: signoz-clickhouse`
     - `signoz.env.SIGNOZ_USER_ROOT_PASSWORD.valueFrom.secretKeyRef.name: signoz-root-user`
   - Creates StatefulSet for ClickHouse, Pod for SigNoz UI
   - Command: `bash scripts/provision.sh signoz`

5. **Observability Bootstrap (SigNoz-specific):**
   - Deploy observability configuration, dashboards, alert rules:
     ```bash
     bash scripts/provision.sh signoz-observability
     ```
   - Imports: Kubernetes, MongoDB, PostgreSQL, OTel collector dashboards

6. **Verification:**
   - Pod readiness: `kubectl get pods -n signoz`
   - ClickHouse health: `kubectl -n signoz exec clickhouse-0 -- clickhouse-client --query "SELECT 1"`
   - UI access: `bash scripts/open-signoz-ui.sh`
   - Smoke test: `bash scripts/verify-platform-health.sh --smoke-test`

### Destruction
1. **Pre-Destroy Guard:** Runs `verify_signoz_pre_destroy_guard`
   - Validates no active spans/traces in ClickHouse (safe to destroy)
   - Validates all metrics exported successfully
   - Returns: SHA-256 digest of ClickHouse schema
   - If validation fails: Destruction is blocked

2. **Actual Destruction:**
   - GitOps: `bash scripts/provision.sh all --destroy` removes SigNoz Helm releases
   - Terraform: No resources to destroy (SigNoz is Kubernetes-native)
   - Secrets: Retained (may be needed for recovery)

3. **Post-Destruction Verification:**
   - PVC cleanup: `kubectl get pvc -n signoz` (should be empty)
   - No residual pods: `kubectl get pods -n signoz` (should be empty)

## Identities

### Kubernetes Secrets (No AWS IRSA)
1. **`signoz-clickhouse` Secret:**
   - Key: `password`
   - Value: ClickHouse root password (generated by scripts/create-signoz-clickhouse-secret.sh)
   - Used by: HelmRelease `values.clickhouse.password.valueFrom.secretKeyRef`
   - Created: `bash scripts/create-signoz-clickhouse-secret.sh`

2. **`signoz-root-user` Secret:**
   - Keys: `email`, `password`
   - Values: SigNoz admin email/password (generated by scripts/create-signoz-root-user-secret.sh)
   - Used by: HelmRelease env vars SIGNOZ_USER_ROOT_EMAIL, SIGNOZ_USER_ROOT_PASSWORD
   - Created: `bash scripts/create-signoz-root-user-secret.sh`

### Service Accounts
- Default Kubernetes service account used (no custom RBAC required)
- Secrets injected as environment variables by HelmRelease

## Guard Semantics

### Pre-Destroy Guard: `verify_signoz_pre_destroy_guard`

**Triggered:** When destruction is requested (`bash scripts/provision.sh all --destroy`)

**Protocol (7-step seam):**

1. **Seam Read:** Extract guard configuration from environment:
   ```bash
   SIGNOZ_NAMESPACE=${SIGNOZ_NAMESPACE:-"signoz"}
   ```

2. **Parse:** Query ClickHouse for active spans/traces:
   ```bash
   kubectl -n "$SIGNOZ_NAMESPACE" exec clickhouse-0 -- \
     clickhouse-client --query "SELECT COUNT(*) FROM spans WHERE end_time > now() - INTERVAL 1 MINUTE"
   ```

3. **Validate:** Check:
   - No active spans in last 1 minute (data is exported)
   - ClickHouse is healthy and responding to queries
   - Kafka queue is empty (no pending events)

4. **Identity:** Record which admin/operator invoked destruction:
   - Extract from `$USER` environment variable
   - Log to audit trail: `destruction-request-by=${USER}`

5. **SHA-256 Digest:** Create immutable fingerprint:
   ```bash
   DIGEST=$(kubectl -n "$SIGNOZ_NAMESPACE" exec clickhouse-0 -- \
     clickhouse-client --query "SELECT dataModelVersion FROM system.settings" | sha256sum | awk '{print $1}')
   ```

6. **Callback:** Log destruction authorization to audit log:
   - Event: `signoz_pre_destroy_guard_pass`
   - Digest: $DIGEST
   - Timestamp: ISO-8601

7. **Return:** Exit code 0 if all checks pass; non-zero if any validation fails

**Failure Behavior:** If guard fails, destruction is blocked. Admin must investigate (check if observability is still needed) and resolve before retrying.

## Prerequisites

### AWS Prerequisites
None. SigNoz is Kubernetes-native and does not require AWS resources.

### Kubernetes Prerequisites
1. **Namespace:** `signoz` (created automatically by HelmRelease `createNamespace: true`)
2. **StorageClass:** `gp3-mongodb` (must exist from Phase 3 k8s/base/)
3. **Flux Controllers:** FluxCD Helm Controller active in cluster
4. **Persistent Volume Provisioning:** EBS volumes must be provisioned by gp3-mongodb StorageClass

### Operator Prerequisites — CRITICAL
Before deploying SigNoz, create the required Kubernetes Secrets:

#### Step 1: Create ClickHouse Secret
```bash
# Generate or provide a ClickHouse root password
export CLICKHOUSE_ROOT_PASSWORD="<secure-password>"  # Min 12 chars

# Run the bootstrap script
bash scripts/create-signoz-clickhouse-secret.sh --password "$CLICKHOUSE_ROOT_PASSWORD"

# Verify:
kubectl get secret -n signoz signoz-clickhouse -o jsonpath='{.data.password}' | base64 -d
```

The HelmRelease references this secret:
```yaml
values:
  clickhouse:
    password:
      valueFrom:
        secretKeyRef:
          name: signoz-clickhouse
          key: password
```

**Failure Mode:** If the `signoz-clickhouse` Secret does not exist, the ClickHouse pod will fail to start with error:
```
error: secret "signoz-clickhouse" not found
```

#### Step 2: Create SigNoz Root User Secret (for UI admin account)
```bash
# Run the bootstrap script
bash scripts/create-signoz-root-user-secret.sh \
  --email admin@oms.local \
  --namespace signoz \
  --org-name oms

# Verify:
kubectl get secret -n signoz signoz-root-user -o jsonpath='{.data.email}' | base64 -d
```

#### Step 3: Deploy SigNoz
```bash
# Now that secrets exist, deploy:
bash scripts/provision.sh signoz
bash scripts/provision.sh signoz-observability
```

#### Step 4: Verify Deployment
```bash
bash scripts/verify-platform-health.sh --smoke-test
bash scripts/open-signoz-ui.sh
```

## Service Dependencies

### Depends On
- **Kubernetes Cluster:** Must be running before SigNoz provisioning
- **Persistent Volumes:** EBS volumes provisioned by gp3-mongodb StorageClass
- **Flux Controllers:** FluxCD Helm Controller for GitOps deployments

### Required By
- **Boomi Integration:** Audit telemetry exported to SigNoz
- **Kubernetes Monitoring:** Cluster metrics, pod health, node status
- **MongoDB Monitoring:** Database metrics, replication status, backup health
- **PostgreSQL Monitoring:** Database metrics, replication status

### Optional Dependencies
- **MongoDB:** SigNoz can operate without MongoDB (but loses audit context)
- **PostgreSQL:** SigNoz can operate without PostgreSQL (but loses PG metrics)

## Configuration Reference

See `config/environment-schema/fragments/50-signoz.manifest` for:
- SIGNOZ_VERSION
- SIGNOZ_K8S_INFRA_VERSION
- SIGNOZ_STORAGE_CLASS
- SIGNOZ_OTEL_ENDPOINT
- SIGNOZ_CLICKHOUSE_SECRET_NAME

Environment variables are consumed by:
- `scripts/provision.sh` (provisions resources)
- `scripts/verify-platform-health.sh` (validates deployment)
- `gitops/signoz/overlays/uat/` (applies environment-specific patches)
```

**Validation Checks in Tests:**
- File exists: `docs/references/signoz-platform-contract.md`
- Contains: `### Ownership & Maintenance`
- Contains: `### Lifecycle` with Provisioning and Destruction
- Contains: `### Identities` with Kubernetes Secrets (clickhouse, root-user)
- Contains: `### Guard Semantics` with 7-step protocol
- Contains: `### Prerequisites` with ClickHouse Secret requirements
- Prerequisites mentions: "signoz-clickhouse", "create-signoz-clickhouse-secret.sh", "CLICKHOUSE_ROOT_PASSWORD"
- Prerequisites mentions: "create-signoz-root-user-secret.sh"
- Prerequisites contains step-by-step secret creation commands
- Guard Semantics mentions: "pre-destroy", "validate", "SHA-256", "ClickHouse"

---

### Deliverable 2: Documentation Tests (3 Python test files)

#### 2.1 tests/mongodb/test_documentation.py

```python
import pathlib
import unittest

MONGODB_CONTRACT = pathlib.Path(__file__).parents[2] / "docs" / "references" / "mongodb-platform-contract.md"

class MongoDBDocumentationTests(unittest.TestCase):
    """Tests verify that mongodb-platform-contract.md exists and contains required sections."""
    
    def test_contract_file_exists(self):
        self.assertTrue(MONGODB_CONTRACT.exists(), 
            f"Contract file does not exist: {MONGODB_CONTRACT}")
    
    def test_ownership_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Ownership & Maintenance", content)
    
    def test_lifecycle_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Lifecycle", content)
    
    def test_lifecycle_includes_provisioning(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("### Provisioning", content)
    
    def test_lifecycle_includes_destruction(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("### Destruction", content)
    
    def test_identities_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Identities", content)
    
    def test_identities_includes_irsa(self):
        content = MONGODB_CONTRACT.read_text()
        identities = content.split("## Identities")[1].split("##")[0]
        self.assertIn("IRSA", identities, "Identities must document IRSA")
    
    def test_identities_includes_iam_permissions(self):
        content = MONGODB_CONTRACT.read_text()
        identities = content.split("## Identities")[1].split("##")[0]
        self.assertIn("IAM", identities, "Identities must document IAM permissions")
    
    def test_guard_semantics_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Guard Semantics", content)
    
    def test_guard_semantics_describes_pre_destroy_guard(self):
        content = MONGODB_CONTRACT.read_text()
        guard_section = content.split("## Guard Semantics")[1].split("##")[0]
        self.assertIn("pre-destroy", guard_section.lower(), 
            "Guard Semantics must describe pre-destroy guard")
        self.assertIn("validate", guard_section.lower(), 
            "Guard Semantics must describe validation logic")
    
    def test_guard_semantics_describes_7_step_protocol(self):
        content = MONGODB_CONTRACT.read_text()
        guard_section = content.split("## Guard Semantics")[1].split("##")[0]
        # Verify the 7 steps are mentioned
        steps = ["Seam Read", "Parse", "Validate", "Identity", "SHA-256", "Callback", "Return"]
        for step in steps:
            self.assertIn(step, guard_section, 
                f"Guard Semantics must include step: {step}")
    
    def test_prerequisites_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Prerequisites", content)
    
    def test_prerequisites_includes_aws_prerequisites(self):
        content = MONGODB_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("AWS", prerequisites.upper(), 
            "Prerequisites must document AWS prerequisites")
        self.assertIn("IRSA", prerequisites, 
            "Prerequisites must mention IRSA role")
        self.assertIn("S3", prerequisites, 
            "Prerequisites must mention S3 bucket")
        self.assertIn("KMS", prerequisites, 
            "Prerequisites must mention KMS key")
    
    def test_prerequisites_includes_kubernetes_prerequisites(self):
        content = MONGODB_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("Kubernetes", prerequisites, 
            "Prerequisites must document Kubernetes prerequisites")
        self.assertIn("Namespace", prerequisites, 
            "Prerequisites must mention namespace")
    
    def test_prerequisites_includes_operator_prerequisites(self):
        content = MONGODB_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("Operator", prerequisites, 
            "Prerequisites must document Operator prerequisites")
    
    def test_service_dependencies_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Service Dependencies", content)
    
    def test_configuration_reference_section_exists(self):
        content = MONGODB_CONTRACT.read_text()
        self.assertIn("## Configuration Reference", content)


if __name__ == "__main__":
    unittest.main()
```

#### 2.2 tests/postgresql/test_documentation.py

```python
import pathlib
import unittest

POSTGRESQL_CONTRACT = pathlib.Path(__file__).parents[2] / "docs" / "references" / "postgresql-platform-contract.md"

class PostgreSQLDocumentationTests(unittest.TestCase):
    """Tests verify that postgresql-platform-contract.md exists and contains required sections."""
    
    # Same structure as MongoDB tests, with PostgreSQL-specific keywords
    
    def test_contract_file_exists(self):
        self.assertTrue(POSTGRESQL_CONTRACT.exists(), 
            f"Contract file does not exist: {POSTGRESQL_CONTRACT}")
    
    def test_ownership_section_exists(self):
        content = POSTGRESQL_CONTRACT.read_text()
        self.assertIn("## Ownership & Maintenance", content)
    
    def test_lifecycle_section_exists(self):
        content = POSTGRESQL_CONTRACT.read_text()
        self.assertIn("## Lifecycle", content)
    
    def test_identities_includes_irsa_and_iam(self):
        content = POSTGRESQL_CONTRACT.read_text()
        identities = content.split("## Identities")[1].split("##")[0]
        self.assertIn("IRSA", identities)
        self.assertIn("IAM", identities)
    
    def test_guard_semantics_section_exists(self):
        content = POSTGRESQL_CONTRACT.read_text()
        self.assertIn("## Guard Semantics", content)
    
    def test_guard_semantics_includes_7_step_protocol(self):
        content = POSTGRESQL_CONTRACT.read_text()
        guard_section = content.split("## Guard Semantics")[1].split("##")[0]
        steps = ["Seam Read", "Parse", "Validate", "Identity", "SHA-256", "Callback", "Return"]
        for step in steps:
            self.assertIn(step, guard_section, f"Guard Semantics must include step: {step}")
    
    def test_prerequisites_includes_aws_s3_kms(self):
        content = POSTGRESQL_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("S3", prerequisites)
        self.assertIn("KMS", prerequisites)
        self.assertIn("IRSA", prerequisites)
    
    def test_service_dependencies_section_exists(self):
        content = POSTGRESQL_CONTRACT.read_text()
        self.assertIn("## Service Dependencies", content)


if __name__ == "__main__":
    unittest.main()
```

#### 2.3 tests/signoz/test_documentation.py

```python
import pathlib
import unittest

SIGNOZ_CONTRACT = pathlib.Path(__file__).parents[2] / "docs" / "references" / "signoz-platform-contract.md"

class SigNozDocumentationTests(unittest.TestCase):
    """Tests verify that signoz-platform-contract.md exists and contains required sections."""
    
    def test_contract_file_exists(self):
        self.assertTrue(SIGNOZ_CONTRACT.exists(), 
            f"Contract file does not exist: {SIGNOZ_CONTRACT}")
    
    def test_ownership_section_exists(self):
        content = SIGNOZ_CONTRACT.read_text()
        self.assertIn("## Ownership & Maintenance", content)
    
    def test_lifecycle_section_exists(self):
        content = SIGNOZ_CONTRACT.read_text()
        self.assertIn("## Lifecycle", content)
    
    def test_identities_includes_kubernetes_secrets(self):
        content = SIGNOZ_CONTRACT.read_text()
        identities = content.split("## Identities")[1].split("##")[0]
        self.assertIn("Kubernetes Secrets", identities, 
            "Identities must document Kubernetes Secrets")
        self.assertIn("signoz-clickhouse", identities, 
            "Identities must mention signoz-clickhouse Secret")
        self.assertIn("signoz-root-user", identities, 
            "Identities must mention signoz-root-user Secret")
    
    def test_identities_does_not_require_aws_irsa(self):
        content = SIGNOZ_CONTRACT.read_text()
        identities = content.split("## Identities")[1].split("##")[0]
        # Verify no AWS/IRSA requirement (different from MongoDB/PostgreSQL)
        self.assertNotIn("IRSA", identities, 
            "SigNoz does not require IRSA (Kubernetes-native)")
    
    def test_guard_semantics_section_exists(self):
        content = SIGNOZ_CONTRACT.read_text()
        self.assertIn("## Guard Semantics", content)
    
    def test_guard_semantics_includes_7_step_protocol(self):
        content = SIGNOZ_CONTRACT.read_text()
        guard_section = content.split("## Guard Semantics")[1].split("##")[0]
        steps = ["Seam Read", "Parse", "Validate", "Identity", "SHA-256", "Callback", "Return"]
        for step in steps:
            self.assertIn(step, guard_section, f"Guard Semantics must include step: {step}")
    
    def test_prerequisites_section_exists(self):
        content = SIGNOZ_CONTRACT.read_text()
        self.assertIn("## Prerequisites", content)
    
    def test_prerequisites_explains_clickhouse_secret_creation(self):
        content = SIGNOZ_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("signoz-clickhouse", prerequisites, 
            "Prerequisites must mention signoz-clickhouse Secret")
        self.assertIn("create-signoz-clickhouse-secret.sh", prerequisites, 
            "Prerequisites must reference bootstrap script")
        self.assertIn("CLICKHOUSE_ROOT_PASSWORD", prerequisites, 
            "Prerequisites must document password environment variable")
    
    def test_prerequisites_explains_root_user_secret_creation(self):
        content = SIGNOZ_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1].split("##")[0]
        self.assertIn("signoz-root-user", prerequisites, 
            "Prerequisites must mention signoz-root-user Secret")
        self.assertIn("create-signoz-root-user-secret.sh", prerequisites, 
            "Prerequisites must reference SigNoz root user bootstrap script")
    
    def test_prerequisites_no_aws_requirements(self):
        content = SIGNOZ_CONTRACT.read_text()
        prerequisites = content.split("## Prerequisites")[1]
        aws_section = prerequisites.split("## Kubernetes")[0] if "## Kubernetes" in prerequisites else ""
        self.assertIn("None", aws_section, 
            "AWS Prerequisites section should state 'None' (SigNoz is Kubernetes-native)")
    
    def test_service_dependencies_section_exists(self):
        content = SIGNOZ_CONTRACT.read_text()
        self.assertIn("## Service Dependencies", content)


if __name__ == "__main__":
    unittest.main()
```

---

### Deliverable 3: Phase 3 Final Gates (Executed by Subagent)

**Gate 1 (All Tests):**
```bash
python3 -m unittest discover -s tests -p "test_*.py" -v
# Expected: ~132+ tests PASS (123 from Tasks 1-6 + 3 documentation modules with ~3-13 tests each)
```

**Gate 2 (Terraform Validation):**
```bash
cd platform-prerequisites/terraform/mongodb
terraform fmt -check
terraform validate

cd ../postgresql
terraform fmt -check
terraform validate
```

**Gate 3 (GitOps Builds):**
```bash
kustomize build gitops/mongodb/overlays/uat > /dev/null
kustomize build gitops/postgresql/overlays/uat > /dev/null
kustomize build gitops/signoz/overlays/uat > /dev/null
```

**Gate 4 (Git Status):**
```bash
git status --porcelain
# Output: "" (empty = clean working tree)
```

---

### Deliverable 4: Atomic Commit

```bash
git add docs/references/mongodb-platform-contract.md \
        docs/references/postgresql-platform-contract.md \
        docs/references/signoz-platform-contract.md \
        tests/mongodb/test_documentation.py \
        tests/postgresql/test_documentation.py \
        tests/signoz/test_documentation.py

git commit -m "docs(phase3): add platform contracts and documentation tests for workload platforms

- Add: mongodb-platform-contract.md with Ownership, Lifecycle, Identities, Guard Semantics, Prerequisites
- Add: postgresql-platform-contract.md with same structure as MongoDB contract
- Add: signoz-platform-contract.md with ClickHouse Secret prerequisites and bootstrap script reference
- Add: test_documentation.py for each platform (MongoDB, PostgreSQL, SigNoz) enforcing all contract sections and content quality
- Passed all Phase 3 final validation gates:
  * Gate 1: 132+ tests PASS
  * Gate 2: Terraform fmt & validate PASS
  * Gate 3: Kustomize builds PASS (base + uat overlays)
  * Gate 4: Git status CLEAN

Phase 3 Task 7 COMPLETE. Ready for manual gatekeeper review before merge to main."
```

---

## Post-Task 7: Manual Gatekeeper Review (Before Merge)

After Task 7 atomic commit is successful, the following gatekeepers must review and approve before merge to main:

### AWS Architect Review Checklist
- [ ] Contract docs accurately reference Phase 2 prerequisites (IRSA roles, KMS keys, S3 buckets)?
- [ ] IRSA role ARNs and KMS key identifiers are correct?
- [ ] No AWS credentials or secrets hardcoded?
- [ ] Prerequisites sections are actionable and verifiable?

### DevOps Review Checklist
- [ ] ClickHouse Secret bootstrap (`create-signoz-clickhouse-secret.sh`) requirement is clearly documented?
- [ ] All prerequisites are actionable (not vague)?
- [ ] Tests verify secret requirements and bootstrap scripts?
- [ ] Failure modes and recovery procedures are documented?

### Software Architect Review Checklist
- [ ] Lifecycle sections accurately describe deployment flow?
- [ ] Guard semantics are clear and unambiguous?
- [ ] All tests verify content quality, not just structure?
- [ ] Contract structure is consistent across MongoDB, PostgreSQL, SigNoz?

### Superpowers Creator Review Checklist
- [ ] Task 7 atomic commit is self-contained and passes all gates?
- [ ] No partial implementations?
- [ ] All 132+ tests pass?
- [ ] Working tree is clean after commit?

### Merge Decision
- **If all reviews:** ✅ APPROVED → Proceed with merge to main
- **If any review:** ❌ REQUEST CHANGES → Return to implementation for corrections

---

## Summary

**Task 7 is the final implementation task for Phase 3.** This plan delivers:
1. ✅ 3 comprehensive platform contract documents (MongoDB, PostgreSQL, SigNoz)
2. ✅ 3 documentation test suites with content quality verification
3. ✅ 4 Phase 3 final validation gates (all tests, terraform, gitops, git status)
4. ✅ Atomic commit with clear messaging
5. ✅ Post-commit gatekeeper review process before merge

**No merge to main.** Task 7 execution stops after commit is successful. Manual review required before merge.
