 Boomi Integration Guide

How to use the audit log library and telemetry from Boomi processes.

**Who this is for:** Boomi Admins/Developers who need to write audit logs and send telemetry.

**Related docs:**
- [Component Catalog § MongoDB](../references/component-catalog.md#mongodb-percona-server-for-mongodb) — what MongoDB does in OMS
- [Component Catalog § SigNoz](../references/component-catalog.md#signoz) — what SigNoz does in OMS
- [Verification Commands § End-to-End](../references/verification-commands.md#end-to-end-smoke-test) — validate the full path
- [Environment Setup](environment-setup.md) — workstation setup (if running test harness locally)

---

## System Overview For Boomi

Boomi processes interact with two backend services:

```mermaid
flowchart LR
  BOOMI[Boomi Process] -->|write audit record| MONGO[(MongoDB)]
  BOOMI -->|send OTLP telemetry| SIGNOZ[SigNoz]
  SIGNOZ -->|dashboard| OPERATOR[Operator/Admin]
  MONGO -->|query audit trail| COMPLIANCE[Compliance Team]
```

| Service | What Boomi Does With It | Endpoint |
|---|---|---|
| **MongoDB** | Writes immutable audit log records | MongoDB URI (from K8s Secret — see below) |
| **SigNoz** | Sends OTLP log/trace telemetry for observability | OTLP endpoint (HTTP, cluster-internal or via ingress) |

### Execution Model

The Groovy library runs **inside the Boomi runtime** (or locally for testing), NOT as a Kubernetes pod:

```mermaid
flowchart TD
  subgraph boomi_runtime[Boomi Runtime / Local Workstation]
    LIB[BoomiAuditLogLibrary.groovy]
  end

  subgraph k8s_cluster[EKS Cluster]
    SECRET[K8s Secret: oms-audit-writer]
    MONGO[(MongoDB RS)]
    SIGNOZ[SigNoz OTLP endpoint]
  end

  LIB -->|kubectl read secret| SECRET
  LIB -->|MongoDB driver direct| MONGO
  LIB -->|HTTP POST /v1/logs| SIGNOZ
```

**Key points:**
- The library uses `kubectl` to read the MongoDB URI from a Kubernetes Secret — this requires `kubectl` in PATH and valid kubeconfig
- MongoDB write happens directly via the Java MongoDB driver (not through a K8s service proxy)
- Telemetry is sent via HTTP POST to the SigNoz OTLP endpoint
- In dev, both MongoDB and SigNoz are accessed via local port-forwards
- In production, use cluster-internal service DNS (Boomi runtime must have network access to the cluster)

### Secret Strategy: Kubernetes Secrets (Recommended)

**Use Kubernetes Secrets** — they are free, already provisioned in the cluster, and the library supports them natively.

**Do NOT use AWS Secrets Manager** unless you have a specific requirement — it adds cost and complexity. The AWS path exists in the library for environments where kubectl access is not available.

| Secret Source | Cost | When to Use |
|---|---|---|
| K8s Secret (recommended) | Free | Default for all environments where kubectl is available |
| AWS Secrets Manager | ~$0.40/secret/month + $0.05/10K API calls | Only if Boomi runtime cannot access kubectl |
| Explicit URI (hardcoded) | Free | Local testing only — never in production |

**Create the K8s Secret** (one-time, run by operator):

```bash
scripts/create-audit-writer-secret.sh
```

This creates `oms-audit-writer` in the `mongodb` namespace with a `mongoUri` key containing the full connection string.

## Audit Log Library

### Location

```
scripts/groovy/boomi/BoomiAuditLogLibrary.groovy
```

This is the production library. The file at `scripts/write-auditlog-and-telemetry.groovy` is only a test harness.

### Public API

#### `BoomiAuditLogLibrary.resolveMongoUri(Map options)`

Resolves MongoDB connection URI from multiple sources in priority order.

**Parameters** (all optional — pass as named map):

| Parameter | Type | Description |
|---|---|---|
| `mongoUri` | String | Explicit MongoDB URI (highest priority) |
| `k8sSecretName` | String | Kubernetes Secret name containing the URI |
| `k8sNamespace` | String | Kubernetes namespace (default: `mongodb`) |
| `k8sSecretKey` | String | Key within the Secret (default: `mongoUri`) |
| `awsSecretId` | String | AWS Secrets Manager secret ID |
| `awsRegion` | String | AWS region (default: env `AWS_REGION` or `ap-east-1`) |

**Resolution order:**
1. If `mongoUri` is provided → use it directly
2. If `k8sSecretName` is provided → read from Kubernetes Secret
3. If `awsSecretId` is provided → read from AWS Secrets Manager
4. Fallback → `mongodb://127.0.0.1:27017/?directConnection=true`

**Returns:** `String` — MongoDB connection URI

**Example:**

```groovy
import boomi.BoomiAuditLogLibrary

// From Kubernetes Secret
String uri = BoomiAuditLogLibrary.resolveMongoUri([
  k8sSecretName: 'oms-audit-writer',
  k8sNamespace: 'mongodb',
  k8sSecretKey: 'mongoUri'
])

// From AWS Secrets Manager
String uri = BoomiAuditLogLibrary.resolveMongoUri([
  awsSecretId: '/oms/dev/mongodb/audit-writer',
  awsRegion: 'ap-east-1'
])

// Explicit URI
String uri = BoomiAuditLogLibrary.resolveMongoUri([
  mongoUri: 'mongodb://user:pass@host:27017/auditdb'
])
```

#### `BoomiAuditLogLibrary.writeAuditLog(String mongoUri, String dbName, String collectionName, Map record)`

Writes a single audit log document to MongoDB.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `mongoUri` | String | MongoDB connection URI (from `resolveMongoUri`) |
| `dbName` | String | Target database name |
| `collectionName` | String | Target collection name |
| `record` | Map | Audit log document (see schema below) |

**Returns:** `Map` with keys:
- `insertedId` — hex string of the inserted document `_id`
- `savedDocument` — the full document as saved in MongoDB

**Example:**

```groovy
import boomi.BoomiAuditLogLibrary

String uri = BoomiAuditLogLibrary.resolveMongoUri([
  k8sSecretName: 'oms-audit-writer'
])

Map record = [
  trace_id: 'abc123',
  time: '2026-07-06T10:30:00Z',
  action: 'orders.order.confirm',
  resource_type: 'orders.order',
  resource_id: 'ORD-2024-001',
  user_id: 'user1',
  resource_changes: [status: ['pending', 'confirmed']],
  meta: [method: 'POST', path: '/api/v1/orders/ORD-2024-001/confirm', status: 200]
]

def result = BoomiAuditLogLibrary.writeAuditLog(uri, 'oms_audit', 'auditlogs', record)
println "Inserted: ${result.insertedId}"
```

#### `BoomiAuditLogLibrary.readKubernetesSecretValue(String namespace, String secretName, String secretKey)`

Reads a single value from a Kubernetes Secret (base64-decoded).

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `namespace` | String | Kubernetes namespace |
| `secretName` | String | Secret name |
| `secretKey` | String | Key within the Secret |

**Returns:** `String` — decoded secret value

**Throws:** `RuntimeException` if secret/key not found or kubectl fails.

#### `BoomiAuditLogLibrary.readAwsSecretString(String secretId, String awsRegion)`

Reads a secret string from AWS Secrets Manager.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `secretId` | String | Secret ID or ARN |
| `awsRegion` | String | AWS region |

**Returns:** `String` — secret value (string or decoded binary)

---

## Audit Log Document Schema

The recommended audit log document structure:

| Field | Type | Required | Description |
|---|---|---|---|
| `trace_id` | String | Yes | Unique trace identifier for correlation |
| `time` | String (ISO 8601) | Yes | Event timestamp in UTC |
| `action` | String | Yes | Dot-notation action identifier (e.g., `orders.order.confirm`) |
| `resource_type` | String | Yes | Resource type being acted on |
| `resource_id` | String | Yes | Specific resource identifier |
| `user_id` | String | Yes | Acting user identifier |
| `ip` | String | No | Client IP address |
| `error_code` | String/null | No | Error code if action failed |
| `message` | String/null | No | Human-readable message |
| `tpl_message` | Map | No | Templated message (`key` + `params`) |
| `resource_changes` | Map | No | Before/after values of changed fields |
| `meta` | Map | No | Request metadata (method, path, status, user-agent) |

**Example document:**

```json
{
  "trace_id": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
  "time": "2026-07-06T10:30:00Z",
  "action": "orders.order.confirm",
  "resource_type": "orders.order",
  "resource_id": "ORD-2024-001",
  "user_id": "user1",
  "ip": "192.168.1.122",
  "error_code": null,
  "tpl_message": {
    "key": "orders.order.status.changed",
    "params": {"order_no": "ORD-2024-001", "from": "PENDING", "to": "PROCESSING"}
  },
  "resource_changes": {
    "status": ["pending", "confirmed"]
  },
  "meta": {
    "method": "POST",
    "path": "/api/v1/orders/ORD-2024-001/confirm",
    "status": 200
  }
}
```

---

## Secret Formats

### Kubernetes Secret (Recommended — Free, Already Provisioned)

The library reads base64-encoded values from Kubernetes Secrets via `kubectl`.

**To create the secret** (one-time operator step):

```bash
scripts/create-audit-writer-secret.sh
```

This generates the secret from existing MongoDB credentials. Expected structure:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oms-audit-writer
  namespace: mongodb
type: Opaque
data:
  mongoUri: <base64-encoded MongoDB URI>
```

**Library usage:**

```groovy
String uri = BoomiAuditLogLibrary.resolveMongoUri([
  k8sSecretName: 'oms-audit-writer',
  k8sNamespace: 'mongodb',
  k8sSecretKey: 'mongoUri'
])
```

### AWS Secrets Manager (Optional — NOT Provisioned by Default)

> **Note:** This path is NOT provisioned by the current Terraform stack. Use it only if your Boomi runtime cannot access `kubectl`. You would need to manually create the secret in AWS Secrets Manager.

The library accepts two formats:

**Format 1: Plain URI string**

Secret value is the MongoDB URI directly:
```
mongodb://user:password@host:27017/dbname?authSource=admin
```

**Format 2: JSON object**

Secret value is JSON with one of these keys (checked in order):
```json
{
  "mongoUri": "mongodb://user:password@host:27017/dbname"
}
```

Accepted JSON key names: `mongoUri`, `mongodbUri`, `uri`, `MONGO_URI`

---

## SigNoz Telemetry

### Endpoint Contract

| Environment | Endpoint | Authentication |
|---|---|---|
| Dev (port-forward) | `http://127.0.0.1:3301/v1/logs` | None |
| Production (ingress) | `https://<signoz-ingress-host>/v1/logs` | Network-restricted (SSO/OIDC on dashboard, OTLP open internally) |

### OTLP Log Format

Send OTLP JSON to the `/v1/logs` endpoint:

```json
{
  "resourceLogs": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "oms-audit-writer"}},
        {"key": "deployment.environment", "value": {"stringValue": "dev"}}
      ]
    },
    "scopeLogs": [{
      "scope": {"name": "oms.auditlog.writer", "version": "2.0.0"},
      "logRecords": [{
        "timeUnixNano": "1720263000000000000",
        "severityNumber": 9,
        "severityText": "INFO",
        "body": {"stringValue": "orders.order.confirm"},
        "attributes": [
          {"key": "trace_id", "value": {"stringValue": "abc123"}},
          {"key": "action", "value": {"stringValue": "orders.order.confirm"}},
          {"key": "resource_id", "value": {"stringValue": "ORD-2024-001"}}
        ]
      }]
    }]
  }]
}
```

### Accessing SigNoz Dashboard (Quick)

**Dev:** `scripts/open-signoz-ui.sh` → opens `http://127.0.0.1:3301`

**Production:** `scripts/open-signoz-ui.sh --mode ingress`

In the dashboard, navigate to **Logs** → filter `service.name = oms-audit-writer`.

For first-time login and full navigation guide, see [Accessing SigNoz Dashboard](#accessing-signoz-dashboard) below.

---

## Runtime Dependencies

The Groovy library uses `@Grab` annotations for automatic dependency resolution:

| Dependency | Version | Purpose |
|---|---|---|
| `org.mongodb:mongodb-driver-sync` | 5.1.2 | MongoDB Java driver |
| `software.amazon.awssdk:secretsmanager` | 2.25.48 | AWS Secrets Manager client |

For Boomi deployment, either:
- Include these JARs in the Boomi process classpath, OR
- Use Groovy's `@Grab` for automatic resolution (requires internet access from runtime)

External tools required (for Kubernetes secret resolution only):
- `kubectl` available in PATH

---

## Testing The Library

Run the test harness from the repository root:

```bash
# Requires: groovy installed, MongoDB accessible, SigNoz accessible
scripts/write-auditlog-and-telemetry.sh
```

**Test audit-log write only** (no telemetry dependency):

```bash
scripts/write-auditlog-and-telemetry.sh --otel-endpoint http://localhost:1/noop
```

This validates the MongoDB write path independently of SigNoz availability.

**Test with Kubernetes Secret:**

```bash
scripts/write-auditlog-and-telemetry.sh \
  --mongo-uri-k8s-secret oms-audit-writer \
  --mongo-uri-k8s-namespace mongodb \
  --mongo-uri-k8s-key mongoUri
```

**Test with AWS Secrets Manager:**

```bash
scripts/write-auditlog-and-telemetry.sh \
  --mongo-uri-secret-id /oms/dev/mongodb/audit-writer \
  --aws-region ap-east-1
```

---

## Error Handling

| Error | Cause | Resolution |
|---|---|---|
| `Failed to read Kubernetes secret` | kubectl not available, wrong namespace, or missing RBAC | Verify kubectl access and secret exists |
| `Secret JSON does not contain mongoUri key` | AWS secret payload format mismatch | Use one of: `mongoUri`, `mongodbUri`, `uri`, `MONGO_URI` |
| `MongoTimeoutException` | MongoDB unreachable | Check URI, network access, port-forward if dev |
| `RuntimeException: Secret payload is empty` | Secret exists but has no value | Recreate the secret with valid content |

---

## Accessing SigNoz Dashboard

### First-Time Login (Admin Account Creation)

SigNoz open-source uses a **self-service signup** flow. The first user to access the dashboard becomes the admin.

1. Open the dashboard:
   ```bash
   # Dev (port-forward)
   scripts/open-signoz-ui.sh
   # Then open http://127.0.0.1:3301
   
   # Production (ingress)
   scripts/open-signoz-ui.sh --mode ingress
   ```

2. On first visit, you see a **Sign Up** form. Fill in:
   - Name
   - Email (becomes your login)
   - Password (your choice, min 8 chars)
   - Organization name

3. Click **Get Started** — you are now the admin.

4. To invite additional users: **Settings** → **Organization** → **Invite Members**

### Creating Additional Users

As admin:
1. Go to **Settings** → **Organization** → **Members**
2. Click **Invite Members**
3. Enter email, select role (**Admin**, **Editor**, or **Viewer**)
4. User receives signup link (or navigates to the dashboard URL)

**Role recommendations:**
- Boomi Admin → **Editor** (can create dashboards, alerts)
- Enterprise Architect → **Viewer** (read-only access to all dashboards)
- Compliance reviewer → **Viewer**

### Navigating the Dashboard

After login:

| Tab | What You See | Use Case |
|---|---|---|
| **Logs** | All OTLP log records received | Filter by `service.name`, `trace_id`, `action` |
| **Traces** | Distributed traces across services | End-to-end request flow visualization |
| **Dashboards** | Custom charts and panels | Create operational views |
| **Alerts** | Alert rules and firing status | Set up notifications for anomalies |
| **Services** | Auto-discovered service list | See which services are sending telemetry |

### Finding Audit Events in SigNoz

1. Go to **Logs** tab
2. In the filter bar, type: `service.name = oms-audit-writer`
3. You can further filter by:
   - `trace_id = <specific-trace-id>` — find one specific event
   - `action = orders.order.confirm` — find all events of a type
   - `resource_id = ORD-2024-001` — find events for a specific resource
4. Click any log entry to expand full attributes
5. Copy the `trace_id` to cross-reference with MongoDB audit record

---

## Querying Audit Logs From MongoDB

### Setting Up Read-Only Access

A dedicated read-only user is required to query audit logs without risking writes.

**Create the user** (run once by an operator or architect):

```bash
scripts/create-audit-reader.sh --db oms_audit --username audit_reader
```

This outputs the connection string and password. Save both securely.

**Or with a specific password:**

```bash
scripts/create-audit-reader.sh --db oms_audit --username audit_reader --password 'MySecurePass123!'
```

### Connecting to MongoDB (Dev)

1. Start port-forward to MongoDB:
   ```bash
   kubectl -n mongodb port-forward svc/psmdb-rs0 27017:27017
   ```

2. Connect with mongosh:
   ```bash
   mongosh 'mongodb://audit_reader:<password>@127.0.0.1:27017/oms_audit?authSource=oms_audit&directConnection=true'
   ```

### Common Queries

**Recent audit events:**
```javascript
db.auditlogs.find().sort({ time: -1 }).limit(10)
```

**Events for a specific order:**
```javascript
db.auditlogs.find({ resource_id: 'ORD-2024-001' }).sort({ time: -1 })
```

**Events by action type in a date range:**
```javascript
db.auditlogs.find({
  action: 'orders.order.confirm',
  time: { $gte: '2026-07-01T00:00:00Z', $lte: '2026-07-06T23:59:59Z' }
}).sort({ time: -1 })
```

**Events by user:**
```javascript
db.auditlogs.find({ user_id: 'user1' }).sort({ time: -1 }).limit(20)
```

**Count events by action (aggregation):**
```javascript
db.auditlogs.aggregate([
  { $group: { _id: '$action', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
```

**Find by trace_id (cross-reference with SigNoz):**
```javascript
db.auditlogs.findOne({ trace_id: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6' })
```

---

## Complete Testing Workflow

### Option A: In-Cluster Test Pod (Recommended)

Deploys a test Pod inside the cluster that writes to MongoDB and sends telemetry to SigNoz using internal service endpoints. No port-forwards needed.

```bash
scripts/run-audit-telemetry-test.sh
```

What it does:
1. Creates a temporary Pod in namespace `mongodb`
2. Pod writes a sample audit record to `oms_audit.auditlogs` via internal MongoDB service
3. Pod sends matching OTLP telemetry to SigNoz via internal service
4. Pod reads back the record from MongoDB to verify
5. Shows Pod logs (pass/fail)
6. **Deletes the Pod** automatically

The **audit record stays in MongoDB** (not deleted) — it serves as evidence that the pipeline works.

**Keep the pod for debugging:**
```bash
scripts/run-audit-telemetry-test.sh --keep
```

**Expected output:**
```
Deploying test pod: audit-telemetry-test-1720263000
  Namespace: mongodb
  MongoDB: psmdb-rs0.mongodb.svc.cluster.local / oms_audit.auditlogs
  SigNoz: signoz.signoz.svc.cluster.local:8080
  Trace ID: test-a1b2c3d4

Pod created. Waiting for completion...

─── Pod Logs ───
=== Audit + Telemetry Test Pod ===
[1/3] Writing audit record to MongoDB...
  MongoDB write: OK
[2/3] Sending OTLP telemetry to SigNoz...
  SigNoz telemetry: OK (HTTP 200)
[3/3] Verifying record in MongoDB...
  Read-back: OK (record verified in MongoDB)

=== ALL TESTS PASSED ===
────────────────

Result: PASSED
Deleting test pod...
Pod deleted.
```

### Option B: Local Test (Groovy Library)

Runs the Groovy test harness locally — requires port-forwards and Groovy installed.

**Prerequisites:**
- `groovy` installed (see [Environment Setup](environment-setup.md))
- Port-forwards active:
  ```bash
  kubectl -n mongodb port-forward svc/psmdb-rs0 27017:27017
  kubectl -n signoz port-forward svc/signoz 3301:8080
  ```

**Run:**
```bash
scripts/write-auditlog-and-telemetry.sh
```

This exercises the Boomi Groovy library directly. Useful for testing library code changes.

**Test write-only (no SigNoz dependency):**
```bash
scripts/write-auditlog-and-telemetry.sh --otel-endpoint http://localhost:1/noop
```

### Verifying Results

**In MongoDB** (query the audit record):
```bash
mongosh 'mongodb://audit_reader:<password>@127.0.0.1:27017/oms_audit?authSource=oms_audit&directConnection=true' \
  --eval "db.auditlogs.find({action:'smoke.test.pod'}).sort({time:-1}).limit(1)"
```

**In SigNoz** (find the telemetry):
1. Open SigNoz dashboard (`scripts/open-signoz-ui.sh`)
2. Go to **Logs** tab
3. Filter: `service.name = oms-audit-test-pod`
4. Find the entry with matching trace_id

### Automated Verification

```bash
scripts/verify-platform-health.sh --smoke-test
```

This runs the full write → read-back cycle from within the cluster automatically.
