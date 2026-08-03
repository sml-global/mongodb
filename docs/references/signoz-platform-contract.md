# SigNoz Platform Contract

**Date:** 2026-07-27  
**Component:** SigNoz Observability Platform  
**Namespace:** signoz  
**StorageClass:** gp3-observability  
**Backend:** ClickHouse (time-series database)  
**AWS Prerequisites:** None. SigNoz is Kubernetes-native.

---

## Ownership & Maintenance

- **Platform Component:** SigNoz Observability Platform
- **Maintained By:** Infrastructure Team
- **On-Call Contact:** [Define in deployment runbook]
- **Documentation:** This contract (signoz-platform-contract.md)
- **Related Docs:** 
  - [Architect Reference](../guides/architect-reference.md)
  - [Component Catalog](component-catalog.md)
  - [Dashboard Import Pack](signoz-dashboard-import-pack.md)
  - [Environment Setup](../guides/environment-setup.md)
  - [Operator Runbook](../guides/operator-runbook.md)

---

## Component Overview

- **Platform:** SigNoz (open-source observability stack)
- **Version:** Chart `signoz` version `0.130.1`, hardcoded in `gitops/signoz/base/helmreleases.yaml` (see Configuration Reference below; not sourced from an environment variable)
- **Namespace:** signoz (created by deployment script)
- **StorageClass:** `gp3-mongodb` (shared with MongoDB; defined in `k8s/base/storageclass-gp3-mongodb.yaml`, set via `storageClass: gp3-mongodb` in the HelmRelease)
- **Backend Database:** ClickHouse (columnar time-series database)
- **UI Server:** SigNoz frontend (Grafana-like dashboard)
- **API Server:** SigNoz API (telemetry ingestion and query API)
- **Alertmanager:** Alert routing and notification engine

---

## Lifecycle

### Provisioning Phase

#### Step 1: Phase 3 Prerequisites Validation

**AWS Prerequisites:** None. SigNoz is Kubernetes-native with no AWS dependencies.

SigNoz does not require any AWS resources. All data is stored within Kubernetes PersistentVolumes using ClickHouse.

#### Step 2: Kubernetes Prerequisites

Before deploying SigNoz, verify:

1. **Namespace Creation:** Ensure the signoz namespace exists cleanly
   ```bash
   kubectl get namespace signoz >/dev/null 2>&1 || kubectl create namespace signoz
   ```

2. **StorageClass:** `gp3-observability` must be defined
   ```bash
   kubectl get storageclass gp3-observability
   ```

3. **ClickHouse Secret:** Create the ClickHouse root user secret
   ```bash
   bash scripts/create-signoz-clickhouse-secret.sh
   ```

**Step 2a: Create ClickHouse Secret (CRITICAL)**

The SigNoz deployment requires a ClickHouse root user password stored as a Kubernetes secret. This MUST be created before GitOps deployment.

**Method 1: Using Bootstrap Script (Recommended)**
```bash
bash scripts/create-signoz-clickhouse-secret.sh
```

This script:
- ✅ Ensures namespace exists (idempotent): `kubectl get namespace signoz >/dev/null 2>&1 || kubectl create namespace signoz`
- ✅ Checks if secret already exists (idempotent)
- ✅ Accepts `CLICKHOUSE_ROOT_PASSWORD` env var or generates a secure 16-char password
- ✅ Creates Kubernetes secret `signoz-clickhouse` in `signoz` namespace with key `password`

**Method 2: Manual Secret Creation**
```bash
# Ensure namespace exists
kubectl get namespace signoz >/dev/null 2>&1 || kubectl create namespace signoz

# Create secret (only if not already present)
if ! kubectl -n signoz get secret signoz-clickhouse >/dev/null 2>&1; then
  kubectl -n signoz create secret generic signoz-clickhouse \
    --from-literal=password="your-secure-password-here"
fi
```

**Method 3: Environment Variable with Bootstrap Script**
```bash
# Generate or provide a secure password
export CLICKHOUSE_ROOT_PASSWORD="your-secure-password-here"
bash scripts/create-signoz-clickhouse-secret.sh
# Bootstrap script uses the provided password
```

**Password Requirements:**
- Minimum 12 characters (16+ recommended)
- Alphanumeric (avoid special characters for shell compatibility)
- Must be URL-safe (no spaces, quotes, or backslashes)

#### Step 3: GitOps Provisioning
GitOps deploys SigNoz platform with ClickHouse backend:

```bash
cd /Users/frank/sml/oms/mongodb
bash scripts/provision.sh signoz
bash scripts/provision.sh signoz-observability
```

**GitOps Artifacts:**
- **Base Configuration:** `gitops/signoz/base/` (kustomization.yaml, helm values)
- **Deployment:** HelmRelease CRD for SigNoz Helm chart
- **ClickHouse:** ClickHouse StatefulSet configured to use `signoz-clickhouse` secret
- **Components:** SigNoz UI, API Server, Alert Manager deployed

**Important:** The `scripts/create-signoz-clickhouse-secret.sh` must be executed BEFORE GitOps provisioning, as ClickHouse will fail to start without the password secret.

#### Step 4: Provisioning Verification
```bash
# Check SigNoz pod readiness
kubectl get pods -n signoz

# Check ClickHouse pod readiness
kubectl get statefulset -n signoz

# Access SigNoz UI
bash scripts/open-signoz-ui.sh
# UI typically runs on: http://localhost:3301 (after port-forward)

# Verify telemetry ingestion
curl -X GET http://localhost:4318/metrics | head -20  # OTEL metrics endpoint

# Run smoke tests
bash scripts/verify-platform-health.sh --smoke-test
```

**Success Criteria:**
- SigNoz UI pod is Running (1/1 Ready)
- ClickHouse StatefulSet is Running (replicas ready)
- API Server is accessible on port 4318 (OTEL HTTP receiver)
- Dashboard is accessible via UI (typically port 3301 via port-forward)
- Smoke test returns exit code 0

---

### Destruction Phase

#### Pre-Destroy Guard Execution
Before any destruction, the `verify_signoz_pre_destroy_guard` is automatically executed:

```bash
bash scripts/provision.sh all --destroy
# Internally calls: verify_signoz_pre_destroy_guard
# If guard fails → destruction is blocked
# If guard passes → destruction proceeds
```

#### Step 1: Guard Validation Protocol (7-Step Seam)

**Seam Read:** Extract guard configuration from environment
```bash
SIGNOZ_NAMESPACE=${SIGNOZ_NAMESPACE:-"signoz"}
SIGNOZ_RELEASE_NAME=${SIGNOZ_RELEASE_NAME:-"signoz"}
CLICKHOUSE_POD=${CLICKHOUSE_POD:-"chi-signoz-clickhouse-cluster-0-0"}
```

**Parse:** Query Kubernetes and ClickHouse status
```bash
# Get SigNoz deployment status
kubectl -n "$SIGNOZ_NAMESPACE" get deployment,statefulset,daemonset

# Get ClickHouse cluster status
kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT * FROM system.clusters;"

# Get recent events
kubectl -n "$SIGNOZ_NAMESPACE" get events --sort-by='.lastTimestamp' | head -20
```

**Validate:** Check all health constraints
- All ClickHouse nodes are online and responding
- All SigNoz components are healthy (no pod crash loops)
- No active data export or backup operations
- Database connections are idle (no active queries)

**Identity:** Record destruction authorization
- Extract operator identity from `$USER` environment variable
- Log to audit trail: `destruction_requested_by=${USER}`
- Timestamp: ISO-8601 format

**SHA-256 Digest:** Create immutable fingerprint of platform configuration
```bash
DIGEST=$(kubectl -n "$SIGNOZ_NAMESPACE" get all -o yaml | sha256sum | awk '{print $1}')
echo "Platform configuration digest: $DIGEST"
```

**Callback:** Log destruction authorization
- Event type: `signoz_pre_destroy_guard_pass`
- Recorded digest: $DIGEST
- Timestamp: ISO-8601
- Audit destination: Kubernetes audit log

**Return:** Exit code 0 if all validations pass; non-zero if any check fails

#### Step 2: Actual Destruction
If guard passes, destruction proceeds:

1. **GitOps Removal:**
   ```bash
   bash scripts/provision.sh all --destroy
   ```
   - Removes SigNoz HelmRelease
   - Removes ClickHouse StatefulSets
   - PersistentVolumes are retained (for optional data recovery)

2. **Namespace Cleanup:**
   - SigNoz namespace is retained (optional for debugging)
   - Can be manually deleted if needed: `kubectl delete namespace signoz`

#### Step 3: Post-Destruction Verification
```bash
# Verify no SigNoz pods remain
kubectl get pods -n signoz

# Verify no PersistentVolumeClaims
kubectl get pvc -n signoz

# Verify namespace can be deleted (optional)
kubectl delete namespace signoz
```

**Success Criteria:**
- No SigNoz pods in cluster
- No PVCs in signoz namespace
- Namespace can be safely deleted

---

## Identities

### AWS Pod Identity

**AWS Prerequisites:** None

SigNoz does not use AWS pod identity (IRSA) or AWS credentials. All data is stored within Kubernetes and does not require AWS access.

---

### Kubernetes Secrets

**ClickHouse Root User Secret:** `signoz-clickhouse`

**Location:** `signoz` namespace

**Contents:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: signoz-clickhouse
  namespace: signoz
type: Opaque
data:
  password: <base64-encoded-password>
```

**Key:** `password` (value is the ClickHouse root user password)

**Creation Method:** Use bootstrap script
```bash
bash scripts/create-signoz-clickhouse-secret.sh
# Or provide password via env var
export CLICKHOUSE_ROOT_PASSWORD="secure-password"
bash scripts/create-signoz-clickhouse-secret.sh
```

**Consumption:** ClickHouse pods reference this secret for initialization
```yaml
env:
  - name: CLICKHOUSE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: signoz-clickhouse
        key: password
```

---

## Guard Semantics

### Pre-Destroy Guard: `verify_signoz_pre_destroy_guard`

**Trigger:** Invoked automatically when `bash scripts/provision.sh all --destroy` is executed

**Purpose:** Prevent accidental destruction of SigNoz platform by validating:
1. All ClickHouse nodes are online and healthy
2. No active data operations are in progress
3. Authorized operator is performing the destruction

**Protocol (7-Step Seam):**

#### Seam Read
Extract configuration from environment:
```bash
SIGNOZ_NAMESPACE=${SIGNOZ_NAMESPACE:-"signoz"}
CLICKHOUSE_POD=${CLICKHOUSE_POD:-"chi-signoz-clickhouse-cluster-0-0"}
CLICKHOUSE_PORT=${CLICKHOUSE_PORT:-"9000"}
```

#### Parse
Query ClickHouse and Kubernetes status:
```bash
# Get ClickHouse cluster health
kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT cluster, shard_num, replica_num, host_name, port, database FROM system.clusters;"

# Get ClickHouse disk usage
kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT path, formatReadableSize(sum(bytes)) FROM system.parts GROUP BY path;"

# Get running queries
kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT query_id, query, elapsed FROM system.processes;" 

# Get pod status
kubectl -n "$SIGNOZ_NAMESPACE" get pods -o wide
```

#### Validate
Perform health checks:
```bash
# Check: All ClickHouse replicas are online
OFFLINE_REPLICAS=$(kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT COUNT(*) FROM system.clusters WHERE is_local = 0;" --format Tab)
if [[ $OFFLINE_REPLICAS -gt 0 ]]; then
  echo "ERROR: $OFFLINE_REPLICAS ClickHouse replicas are offline. Destruction blocked."
  exit 1
fi

# Check: No active queries (allow up to 1 for system queries)
ACTIVE_QUERIES=$(kubectl -n "$SIGNOZ_NAMESPACE" exec "$CLICKHOUSE_POD" -- \
  clickhouse-client --query "SELECT COUNT(*) FROM system.processes WHERE query NOT LIKE '%system%';" --format Tab)
if [[ $ACTIVE_QUERIES -gt 0 ]]; then
  echo "ERROR: $ACTIVE_QUERIES active queries detected. Destruction blocked."
  exit 1
fi

# Check: All SigNoz components are Running (not Pending or CrashLoopBackOff)
UNHEALTHY_PODS=$(kubectl -n "$SIGNOZ_NAMESPACE" get pods -o json | \
  jq '.items[] | select(.status.phase != "Running") | .metadata.name' | wc -l)
if [[ $UNHEALTHY_PODS -gt 0 ]]; then
  echo "ERROR: $UNHEALTHY_PODS unhealthy pods detected. Destruction blocked."
  exit 1
fi
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
Create immutable fingerprint of platform configuration:
```bash
DIGEST=$(kubectl -n "$SIGNOZ_NAMESPACE" get all -o yaml | sha256sum | awk '{print $1}')
echo "Platform configuration digest: $DIGEST"
```

#### Callback
Log destruction authorization to audit system:
```bash
# Annotate namespace
kubectl -n "$SIGNOZ_NAMESPACE" annotate namespace signoz \
  "destruction-authorized-by=$DESTRUCTION_OPERATOR" \
  "destruction-timestamp=$DESTRUCTION_TIMESTAMP" \
  "destruction-platform-digest=$DIGEST" \
  --overwrite
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
2. Resolve any health issues (e.g., wait for queries to complete, restore pod health)
3. Re-run the destruction command

**Safety Net:** The guard ensures an adequate grace period for manual verification or emergency rollback before destruction proceeds.

---

## Prerequisites

### AWS Prerequisites

**None. SigNoz is Kubernetes-native.**

SigNoz does not require any AWS resources. All data is stored within Kubernetes PersistentVolumes using ClickHouse.

### Kubernetes Prerequisites

#### 1. Namespace: `signoz`

**Status:** Created by deployment script (or manual `kubectl create namespace signoz`)

**Verification:**
```bash
kubectl get namespace signoz
```

#### 2. StorageClass: `gp3-observability`

**Status:** Defined in `k8s/base/storage-classes.yaml`

**Verification:**
```bash
kubectl get storageclass gp3-observability
# Expected: Storage class with provisioner=aws-ebs, parameters include gp3, iops=3000, etc.
```

**Why It Matters:** SigNoz and ClickHouse PersistentVolumes use this storage class for time-series data storage with high IOPS.

#### 3. ClickHouse Root User Secret: `signoz-clickhouse`

**Status:** MUST be created before GitOps deployment

**Creation:**
```bash
# Bootstrap script (idempotent, recommended)
bash scripts/create-signoz-clickhouse-secret.sh

# Or manually
kubectl -n signoz create secret generic signoz-clickhouse \
  --from-literal=password="secure-password"
```

**Verification:**
```bash
kubectl -n signoz get secret signoz-clickhouse
# Expected: Secret with key "password"
```

**Why It Matters:** ClickHouse requires a root user password. Without this secret, ClickHouse pod initialization fails.

**Password Guidelines:**
- Minimum 12 characters (16+ recommended for production)
- Alphanumeric characters (avoid special characters)
- URL-safe (no spaces, quotes, or backslashes)
- Examples of valid passwords:
  - `SecurePassword123`
  - `ClickHouse1234567890`
  - `ObservabilityStack99`

#### 4. Flux Controllers

**Status:** Must be active in cluster from Phase 2 EKS deployment

**Verification:**
```bash
kubectl get deployment -n flux-system
# Expected: 2 deployments (source-controller, helm-controller)
```

### Platform Prerequisites

#### 1. Bootstrap Script Execution (REQUIRED)

Before running GitOps provisioning:

```bash
# Make script executable (if not already)
chmod +x scripts/create-signoz-clickhouse-secret.sh

# Run bootstrap script
bash scripts/create-signoz-clickhouse-secret.sh
# Script output:
#   Created secret: signoz/signoz-clickhouse
#   Password: <generated-or-provided-password>

# Verify secret was created
kubectl -n signoz get secret signoz-clickhouse
# Expected: KEY password
```

**Critical Note:** If this secret is not created before GitOps deployment, ClickHouse will fail to initialize with an error like:
```
ClickHouse failed to start: CLICKHOUSE_PASSWORD environment variable not set
```

#### 2. Pre-Flight Check

```bash
bash scripts/verify-platform-health.sh --preflight
# Checks: Kubernetes connectivity, StorageClass availability
```

#### 3. GitOps Availability

```bash
# Verify Flux controllers are running
kubectl get deployment -n flux-system
# Expected: source-controller and helm-controller both Running

# Verify HelmRelease resources are available
kubectl api-resources | grep helmrelease
# Expected: helmrelease listed as an available API resource
```

---

## Service Dependencies

### Depends On

- **Phase 2 EKS Cluster:** Must be running and accessible before SigNoz provisioning
  - Cluster name, endpoint, CA certificate
  - kubeconfig configured in `~/.kube/config`
  - kubectl connectivity verified

- **Phase 3 Kubernetes Storage:** Must be provisioned first
  - StorageClass `gp3-observability` defined in k8s/base/

- **ClickHouse Root User Secret:** Must be created before GitOps provisioning
  - `signoz-clickhouse` secret with `password` key
  - Created via `scripts/create-signoz-clickhouse-secret.sh`

### Required By

- **OpenTelemetry Collector:** Sends traces, metrics, and logs to SigNoz
  - Consumes: SigNoz API endpoint (port 4318 for OTEL HTTP receiver)
  - Verifies: Telemetry ingestion is working

- **MongoDB Operator:** Sends MongoDB metrics to SigNoz (optional)
  - Consumes: SigNoz metrics ingestion API
  - Verifies: MongoDB observability dashboard

- **PostgreSQL Operator:** Sends PostgreSQL metrics to SigNoz (optional)
  - Consumes: SigNoz metrics ingestion API
  - Verifies: PostgreSQL observability dashboard

- **Application Layer:** Sends application traces to SigNoz (optional)
  - Consumes: SigNoz trace ingestion API
  - Verifies: Application observability dashboard

### Optional Dependencies

- **MongoDB:** Can send metrics to SigNoz but not required for operation
  - SigNoz runs independently without MongoDB

- **PostgreSQL:** Can send metrics to SigNoz but not required for operation
  - SigNoz runs independently without PostgreSQL

---

## Configuration Reference

**Update (2026-07-31, Issue #4):** the environment-schema keys previously listed
here (`SIGNOZ_VERSION`, `SIGNOZ_K8S_INFRA_VERSION`, `SIGNOZ_STORAGE_CLASS`,
`SIGNOZ_OTEL_ENDPOINT`, `SIGNOZ_CLICKHOUSE_SECRET_NAME`, plus the
never-implemented `SIGNOZ_REPLICA_COUNT`/`SIGNOZ_RETENTION_DAYS`) were never
actually consumed by any script, Terraform module, or Kubernetes manifest --
verified via repo-wide search, including `scripts/lib/packages/50-signoz/`.
They were removed from `config/environment-schema/fragments/50-signoz.manifest`.
The real, authoritative configuration is hardcoded directly in the live
manifest:

**Manifest Location:** `gitops/signoz/base/helmreleases.yaml`

**Actual Configuration:**

- Chart: `signoz` version `0.130.1`
- ClickHouse root password: sourced from the `signoz-clickhouse` Kubernetes
  Secret (see `scripts/create-signoz-root-user-secret.sh`), not an env var
- `clickhouse-backup` sidecar: writes to the dedicated
  `oms-signoz-clickhouse-backups` S3 bucket (see
  `docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md`, D1/D15)

**Consumed By:**

1. **scripts/create-signoz-root-user-secret.sh**
   - Creates the Kubernetes secret consumed by the HelmRelease

2. **scripts/provision-signoz-observability.sh**
   - Configures dashboards and alert rules
   - Verifies observability setup

3. **scripts/verify-platform-health.sh --smoke-test**
   - Verifies SigNoz is accessible
   - Validates telemetry ingestion is working

To change the chart version or storage configuration, edit
`gitops/signoz/base/helmreleases.yaml` directly and let Flux/GitOps reconcile
it -- there is no environment-variable indirection.

---

## Related Documentation

- [Environment Setup Guide](../guides/environment-setup.md) - Step-by-step platform setup
- [Operator Runbook](../guides/operator-runbook.md) - Operational procedures
- [SigNoz Dashboard Import Pack](signoz-dashboard-import-pack.md) - Pre-built dashboards and alerts
- [Component Catalog](component-catalog.md) - All platform components
