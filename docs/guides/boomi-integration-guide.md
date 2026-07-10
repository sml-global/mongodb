 Boomi Integration Guide

How to use the audit log library and telemetry from Boomi processes.

**Who this is for:** Boomi Admins/Developers who need to write audit logs and send telemetry.

**Related docs:**
- [Glossary](../references/glossary.md) — jargon/acronym lookup (OTLP, trace ID, audit trail, and more)
- [Component Catalog § MongoDB](../references/component-catalog.md#mongodb-percona-server-for-mongodb) — what MongoDB does in OMS
- [Component Catalog § SigNoz](../references/component-catalog.md#signoz) — what SigNoz does in OMS
- [Verification Commands § End-to-End](../references/verification-commands.md#end-to-end-smoke-test) — validate the full path
- [Environment Setup](environment-setup.md) — workstation setup (if running test harness locally)

## Quick Start: First Audit Log And Telemetry Flow

Use this path when you want a fast confidence check before deep customization.

Why this path is the default:
1. It uses the existing Kubernetes Secret workflow already provisioned by operators.
2. It avoids extra cost and moving parts from AWS Secrets Manager in dev.
3. It validates both audit-write and telemetry paths together in one run.

1. Confirm your role access.
  - Write/integration testing: Boomi Admin (Editor)
  - Read-only reporting: Viewer
2. Ensure prerequisites:
  - `scripts/create-audit-writer-secret.sh` already run by operator
  - SigNoz is reachable (`scripts/open-signoz-ui.sh` in dev)
3. Run the end-to-end test:

```bash
scripts/run-audit-telemetry-test.sh
```

4. Validate outputs:
  - Test reports successful write/read-back from MongoDB
  - In SigNoz Logs, filter `service.name = oms-audit-test-pod`
5. Then continue with this guide for schema, API usage, and production integration patterns.

### MongoDB Account Mapping (Important)

Use the right account for the right task. Using the wrong one usually looks like a successful connection but fails with `Unauthorized` on `oms_audit` queries.

| Use Case | Account Source | Intended Privilege | Notes |
|---|---|---|---|
| Boomi audit write URI secret (`scripts/create-audit-writer-secret.sh`) | `MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD` in `psmdb-secrets` | Application data read/write | This is the account used to build `oms-audit-writer` secret. |
| In-cluster smoke writer (`scripts/run-audit-telemetry-test.sh`) | `MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD` in `psmdb-secrets` | Application data read/write | Writes and reads `oms_audit.auditlogs` for verification. |
| Human read-only querying (Compass/mongosh) | `audit_reader` created by `scripts/create-audit-reader.sh` | Read-only on `oms_audit` | Recommended for dashboards, audit review, and analyst access. |
| Cluster administration | `MONGODB_CLUSTER_ADMIN_USER` / `MONGODB_CLUSTER_ADMIN_PASSWORD` | Cluster management operations | Not the recommended account for app-level audit log queries. |

If Compass shell shows `authenticatedUsers: [{ user: 'clusterAdmin', db: 'admin' }]` and query fails on `oms_audit`, reconnect with `audit_reader` (or database-admin for operator-only debugging).

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

Use AWS Secrets Manager path only when at least one is true:
1. The Boomi runtime cannot access kubeconfig/kubectl.
2. Organization policy requires centralized secret governance outside the cluster.
3. You need cross-cluster secret reuse managed by AWS controls.

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

The script uses database-admin credentials from `psmdb-secrets` (`MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD`), not `clusterAdmin`.

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

### Boomi Admin View-Only Path (No Editor Permissions)

If your account is intentionally restricted to **Viewer**:

1. Open SigNoz with `scripts/open-signoz-ui.sh` (or ingress mode).
2. Go to **Logs** and apply filter `service.name = oms-audit-writer`.
3. Save links/queries for operational reporting.
4. Request an Editor account only when dashboard authoring or alert changes are required.

This path supports separation-of-duties for teams where telemetry authorship is controlled by platform operations.

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

In this repo, the SigNoz admin account is normally **already bootstrapped
automatically** by an Infra Operator/Architect (SigNoz's root-user feature --
no self-service "first to sign up" race). As a Boomi Admin, you should
receive an **Editor**-role invite from that admin rather than performing
first-time signup yourself.

> **Fallback:** only if you are personally standing up a brand-new
> environment and the automated bootstrap hasn't been run yet, SigNoz falls
> back to a **self-service signup** flow -- the first user to access the
> dashboard becomes the admin. See
> [Operator Runbook § Step 7A](operator-runbook.md#step-7a-signoz-admin-account-bootstrap-automated-no-manual-signup)
> for the recommended automated path, or use the manual **Sign Up** steps
> further down this section if you must do it by hand.

### First-Login Action Checklist (What To Do In Dashboard)

After logging in (whether via automated bootstrap + invite, or manual first
signup), use this order:

1. **Add your first data source**
  - Optional in this repo. OTLP ingestion path is already part of platform setup.
2. **Send logs / traces / metrics**
  - Logs and traces are validated by:
    - `scripts/verify-platform-health.sh --smoke-test`
    - `scripts/run-audit-telemetry-test.sh`
  - Metrics are optional for the current audit-log integration path.
3. **Setup alerts**
  - Automated: `bash scripts/provision.sh signoz-observability --auto-approve`
    already creates 5 baseline alerts (MongoDB, PostgreSQL, K8s, OTel
    Collector, app telemetry). Add more by hand only for cases the baseline
    set doesn't cover. See [SigNoz Dashboard Import Pack](../references/signoz-dashboard-import-pack.md).
4. **Setup saved views**
  - Recommended. Save baseline filters (for example `service.name = oms-audit-writer`).
5. **Setup dashboards**
  - Automated by the same `signoz-observability` command as alerts above.

Minimum requirement to operate safely: validate ingestion + create role-based users.
Saved views should still be treated as a day-2 hardening task; alerts and dashboards are already automated.

### Notifications (SMTP And Alternatives)

You only need SMTP if you want **email** alert notifications from SigNoz.

- If email is required: configure SMTP in SigNoz deployment values and test a notification channel.
- If email is not required: use Slack/webhook/PagerDuty channels instead (no SMTP needed).
- For dev/local-only environments: you can defer notification channel setup until shared usage begins.

### Recommended Account Model (Minimum)

Use at least three user accounts per environment:

1. **Platform Admin account** (for example `omsadmin@sml.com`)
  - Persona: Infra Architect/Admin
  - Role: **Admin**
  - Purpose: workspace setup, user invitations, role management

2. **Infra Backup Admin account** (for example `infraadmin@sml.com`)
  - Persona: Infra Architect/Admin
  - Role: **Admin**
  - Purpose: escalation owner and continuity if primary admin is unavailable

3. **Report Viewer account** (general telemetry consumer)
  - Persona: Enterprise Architect, stakeholder, compliance reviewer
  - Role: **Viewer**
  - Purpose: open dashboards/reports, inspect traces/logs, no configuration changes

For integration operations, add this account pattern:

4. **Boomi Admin account**
  - Persona: Boomi Admin
  - Role: **Editor**
  - Purpose: build and maintain operational dashboards/alerts for integration flows

1. Open the dashboard:
   ```bash
   # Dev (port-forward)
   scripts/open-signoz-ui.sh
   # Then open http://127.0.0.1:3301
   
   # Production (ingress)
   scripts/open-signoz-ui.sh --mode ingress
   ```

2. If the admin account was already bootstrapped automatically, log in with
   the credentials from `kubectl -n signoz get secret signoz-root-user ...`
   (see Operator Runbook Step 7A) or your invited Editor/Viewer account.
   Otherwise (manual fallback only), you see a **Sign Up** form. Fill in:
   - Name
   - Email (becomes your login)
   - Password (your choice, min 8 chars)
   - Organization name

3. Click **Get Started** — you are now the admin (manual fallback only).

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
| **Infrastructure Monitoring → Hosts** | EKS node CPU/memory/disk/network | Cluster-level capacity and health (see [Architect Reference § Infrastructure Monitoring](architect-reference.md#infrastructure-and-database-monitoring)) |

### Visualizing `run-audit-telemetry-test.sh` Output (Beginner Walkthrough)

If you have never used SigNoz before, this is the fastest way to see real data end to end.

1. Run the smoke test and keep the trace ID it prints:
   ```bash
   scripts/run-audit-telemetry-test.sh
   ```
   Note the line `Trace ID: test-xxxxxxxxxxxxxxxx` in the output.
2. Open the dashboard: `scripts/open-signoz-ui.sh`, then browse to `http://127.0.0.1:3301`.
3. Go to the **Logs** tab (left sidebar).
4. In the search bar, filter by the test pod's service name (this script uses a
   different service name than the production Boomi library — see note below):
   ```
   service.name = oms-audit-test-pod
   ```
5. You should see one log line with `body = "smoke.test.pod"`. Click it to expand
   attributes — you will see `trace_id`, `action`, and `pod_name` matching what
   the script printed.
6. Go to the **Services** tab — `oms-audit-test-pod` should now be listed as a
   service that has sent telemetry (it may take up to ~1 minute to appear).

> **Note:** `scripts/run-audit-telemetry-test.sh` only sends a **log** record (via
> `/v1/logs`), not a trace span, so the **Traces** tab will stay empty for this
> script. It also uses `service.name = oms-audit-test-pod`, distinct from the
> production Boomi library's `service.name = oms-audit-writer` used in real audit
> writes (see [Finding Audit Events](#finding-audit-events-in-signoz) below).

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

Recommended cadence:
- After integration code changes: run Option A or Option B before release
- Weekly confidence check in active environments: run Option A
- Incident follow-up: rerun test immediately after remediation

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
