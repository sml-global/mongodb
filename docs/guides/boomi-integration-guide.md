# Boomi Integration Guide

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
| **MongoDB** | Writes immutable audit log records | MongoDB URI (from secret) |
| **SigNoz** | Sends OTLP log/trace telemetry for observability | OTLP endpoint (HTTP) |

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

### Kubernetes Secret

The library reads base64-encoded values from Kubernetes Secrets via `kubectl`.

Expected Secret structure:

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

### AWS Secrets Manager

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

### Accessing SigNoz Dashboard

**Dev:**
```bash
scripts/open-signoz-ui.sh
# Opens http://127.0.0.1:3301
```

**Production:**
```bash
scripts/open-signoz-ui.sh --mode ingress --namespace signoz --ingress signoz
# Prints the ingress URL
```

In the dashboard, navigate to **Logs** to find audit events by `service.name = oms-audit-writer`.

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

## Querying Audit Logs

### From MongoDB directly

```javascript
// Connect via mongosh
db.getSiblingDB('oms_audit').auditlogs.find({
  action: 'orders.order.confirm',
  time: { $gte: '2026-07-01T00:00:00Z' }
}).sort({ time: -1 }).limit(10)
```

### From SigNoz Dashboard

1. Open SigNoz (`scripts/open-signoz-ui.sh`)
2. Navigate to **Logs** tab
3. Filter: `service.name = oms-audit-writer`
4. Search by `trace_id` or `action` attributes
5. Click any log entry to see full attributes

Telemetry in SigNoz correlates with audit records in MongoDB via the shared `trace_id` field.
