# Logging Vocabulary

**Purpose:** Controlled vocabularies for action verbs, resource types, error codes,
and `tpl_message.key` conventions used across MongoDB audit logs and SigNoz
telemetry logs.

**Status:** Registry (architecture-controlled)  
**Effective date:** 2026-08-06  
**Related:** Issue #72, `docs/references/audit-log-contract.md`

---

## Action Vocabulary

Actions follow the format `{resource_type}.{verb}`. The `resource_type` prefix
is mandatory for business actions; the verb comes from the controlled registry
below.

### Business Action Verbs (MongoDB + SigNoz)

These verbs describe completed business milestones and are used in both audit
logs (MongoDB) and telemetry (SigNoz):

| Verb | Meaning | Example Action |
|---|---|---|
| `load` | Load/ingest external data | `boomi.document.load` |
| `transform` | Transform data shape | `boomi.document.transform` |
| `validate` | Validate business rules | `boomi.document.validate` |
| `create` | Create new entity | `orders.order.create` |
| `update` | Update existing entity | `orders.order.update` |
| `confirm` | Confirm/approve entity | `orders.order.confirm` |
| `cancel` | Cancel entity | `orders.order.cancel` |
| `flag` | Flag for attention (warning) | `orders.order.flag` |
| `delete` | Delete entity | `orders.order.delete` |
| `sync_to_d365` | Sync to Dynamics 365 | `orders.order.sync_to_d365` |
| `sync_from_d365` | Sync from Dynamics 365 | `orders.order.sync_from_d365` |
| `sync_from_plm` | Sync from PLM system | `products.artwork.sync_from_plm` |

### Infrastructure Action Format (SigNoz Only)

Infrastructure actions use `{system}.{operation}` format (no resource_type prefix):

| Action | Meaning | When Used |
|---|---|---|
| `audit.write` | Write audit log to MongoDB | Logged by `BoomiAuditLogLibrary` |
| `config.fallback` | Config fallback used | Secret not found, using default |
| `config.reload` | Config reloaded | Dynamic config refreshed |
| `health.check` | Health check performed | Periodic health probe |
| `connection.pool.stats` | Connection pool metrics | Debug/monitoring |

---

## Resource Type Vocabulary

Resource types follow the format `{context}.{scope}`.

### Business Resources (MongoDB + SigNoz)

| Resource Type | Context | Scope | Meaning |
|---|---|---|---|
| `boomi.document` | boomi | document | EDI file or business document |
| `boomi.subprocess` | boomi | subprocess | Boomi subprocess execution |
| `orders.order` | orders | order | Sales order |
| `orders.batch` | orders | batch | Bulk order operation |
| `orders.mo` | orders | mo | Manufacturing order |
| `products.artwork` | products | artwork | Product artwork/design |
| `products.product` | products | product | Product master data |
| `users.user` | users | user | User account |

### Infrastructure Resources (SigNoz Only)

| Resource Type | System | Component | Meaning |
|---|---|---|---|
| `audit.log` | audit | log | Audit log entry itself |
| `config.secret` | config | secret | Kubernetes Secret |
| `config.file` | config | file | Configuration file |
| `database.connection` | database | connection | Database connection |
| `service` | (standalone) | (standalone) | Service instance |

---

## Error Code Vocabulary

Error codes follow the format `{SYSTEM}-{MODULE}-{NNNN}` (all uppercase).

### System Registry

| Code | Full Name |
|---|---|
| `OMS` | Order Management System |
| `ART` | Artwork Center |
| `BOM` | Boomi |
| `365` | Dynamics 365 |
| `IPP` | IPP |

### Module Registry

| Code | Full Name |
|---|---|
| `PD` | Product |
| `OD` | Order |
| `FC` | Format Center |
| `JC` | JCC |
| `UR` | User |
| `PS` | PPS |
| `RP` | Report |
| `IE` | Item Explorer |

### Example Error Codes

**Business errors (MongoDB + SigNoz):**
- `OMS-PD-0001` — Product validation failed
- `OMS-OD-0001` — Order validation failed
- `BOM-OD-0001` — Boomi order document load failed
- `365-RP-0001` — Dynamics 365 report sync failed

**Infrastructure errors (SigNoz only, may use different format):**
- `MONGO_TIMEOUT` — MongoDB connection timeout
- `MONGO_WRITE_FAILED` — MongoDB write operation failed
- `CONFIG_NOT_FOUND` — Config/secret not found
- `NETWORK_ERROR` — Network connectivity issue
- `SERVICE_UNAVAILABLE` — Downstream service unavailable

**Rule:** Once published, an error code is **immutable** (never change its
meaning). Add new codes for new error conditions; never reuse old codes.

---

## tpl_message.key Conventions

`tpl_message.key` is the i18n template lookup key used by the OMS backend to
render localized messages. Keys use dot-separated hierarchical format.

### Business Event Templates (MongoDB + SigNoz)

**Format:** `{context}.{scope}.{verb}_or_{outcome}`

| Key | English Template | Use Case |
|---|---|---|
| `boomi.document.loaded` | `"Loaded {file_name} with {record_count} records"` | Successful EDI load |
| `boomi.document.load_failed` | `"Failed to load {file_name}: {failure_reason}"` | EDI load failure |
| `boomi.document.transformed` | `"Transformed {file_name} from {source_format} to {target_format}"` | Document transformation |
| `orders.order.confirmed` | `"Order {order_no} confirmed by {user_name}"` | Order confirmation |
| `orders.order.cancelled` | `"Order {order_no} cancelled: {cancellation_reason}"` | Order cancellation |
| `orders.batch.confirmed` | `"Bulk confirmation completed: {success_count} succeeded, {failure_count} failed"` | Bulk operation summary |

### Infrastructure Event Templates (SigNoz Only)

| Key | English Template | Use Case |
|---|---|---|
| `mongo.write.failed` | `"MongoDB write failed for {attempted_action}: {failure_reason}"` | Audit write failure |
| `config.secret.not_found` | `"Secret {secret_namespace}/{secret_name} not found, using fallback"` | Config fallback |
| `config.secret.loaded` | `"Loaded configuration from {secret_namespace}/{secret_name}"` | Config success |
| `health.check.passed` | `"Health check passed for {service_name}"` | Health check success |
| `health.check.failed` | `"Health check failed for {service_name}: {failure_reason}"` | Health check failure |

### Key Naming Rules

1. **Hierarchical:** Use dots to separate levels (`boomi.document.loaded`)
2. **Verb-based:** Include the action verb or outcome (`loaded`, `failed`, `confirmed`)
3. **Stable:** Never change a key's meaning; create new key for new meaning
4. **Descriptive:** Key should hint at the template's purpose
5. **Lowercase:** All lowercase with underscores for multi-word parts

**Example progression:**
```
boomi.document.loaded           ← Initial version
boomi.document.loaded_v2        ← Breaking change to template (rare)
boomi.document.loaded.with_warnings  ← New variant (preferred over v2)
```

---

## Field Value Examples (Complete Record)

### Successful Business Event

```json
{
  "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ip": "10.0.1.45",
  "time": "2026-08-06T10:00:00.123Z",
  "action": "boomi.document.load",
  "error_code": null,
  "resource_type": "boomi.document",
  "resource_id": "TCHIBO-0001.csv",
  "user_id": null,
  "message": "EDI file transformed to ELT-ready JSON",
  "tpl_message": {
    "key": "boomi.document.loaded",
    "params": {
      "file_name": "TCHIBO-0001.csv",
      "record_count": 42,
      "file_size_bytes": 15234
    }
  },
  "meta": {
    "boomi_process_id": "EU-TC-0001",
    "main_program_code": "EU",
    "sub_program_code": "TC"
  }
}
```

### Infrastructure Failure Event

```json
{
  "trace_id": "c69de533-0b54-4784-c987-2g4fd6e9b345",
  "ip": "10.0.1.45",
  "time": "2026-08-06T10:10:00.789Z",
  "action": "boomi.document.load",
  "error_code": "MONGO_TIMEOUT",
  "resource_type": "boomi.document",
  "resource_id": "TCHIBO-0003.csv",
  "user_id": null,
  "message": "MongoDB write failed, business event lost",
  "tpl_message": {
    "key": "mongo.write.failed",
    "params": {
      "attempted_action": "boomi.document.load",
      "file_name": "TCHIBO-0003.csv",
      "failure_reason": "Connection timeout after 30s"
    }
  },
  "meta": {
    "boomi_process_id": "EU-TC-0001",
    "attempted_write_count": 3
  }
}
```

---

## Adding New Vocabulary

**To add a new action verb:**
1. Propose in pull request with justification
2. Requires architecture approval
3. Document usage examples
4. Update this file

**To add a new resource type:**
1. Ensure `{context}.{scope}` format
2. Verify context/scope are in registries (or add them first)
3. Pull request with examples
4. Architecture approval required

**To add a new error code:**
1. Pick next available `NNNN` in your `{SYSTEM}-{MODULE}` namespace
2. Document in pull request
3. Add to error code registry (central tracking)
4. Codes are immutable once published

**To add a new tpl_message.key:**
1. Module owner creates key (no central approval needed)
2. Document in module's own template registry
3. Key must be stable once published
4. Update this file with examples (optional)

---

## Related Documentation

- `docs/references/audit-log-contract.md` — Full schema specification
- `docs/guides/architect-reference.md` § Logging Architecture
- Issue #72 — Unified logging schema implementation
