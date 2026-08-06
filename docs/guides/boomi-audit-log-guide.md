# Boomi Developer Guide: Finding Audit Logs in SigNoz

**Audience:** Boomi developers, process owners, operations team  
**Purpose:** How to find and troubleshoot Boomi process audit logs in SigNoz  
**Related:** `docs/references/audit-log-contract.md`, `docs/references/logging-vocabulary.md`

---

## Overview

Every Boomi process execution emits structured audit logs to two systems:

1. **MongoDB** (`oms_audit.audit_log` collection) — Primary audit trail, 7-year retention
2. **SigNoz** (telemetry/disaster recovery backup) — 90-day retention

**When to use SigNoz:**
- MongoDB is unavailable or slow
- Need real-time monitoring/alerting
- Debugging in-flight process executions
- Correlating multiple systems (Boomi + OMS backend + MongoDB)

---

## Quick Start: Finding Your Logs

### 1. Access SigNoz UI

**UAT Environment:**
```bash
kubectl port-forward -n signoz-uat svc/signoz 3302:8080
```

Open: http://localhost:3302  
Login: `admin@oms.local` / (get password from ops team)

### 2. Navigate to Logs Explorer

Click **Logs** → **Explorer** in the left sidebar.

### 3. Apply Filter

In the filter box at the top, enter:

```
meta.boomi_process_id = 'YOUR-PROCESS-ID'
```

**Example:** To find all logs for Tchibo integration:
```
meta.boomi_process_id = 'EU-TC-0001'
```

Click **Run Query** or press Enter.

---

## Common Search Scenarios

### Scenario 1: Find all logs for a specific Boomi process

**Use case:** You want to see all activity for your Boomi process (all executions).

**Query:**
```
meta.boomi_process_id = 'EU-TC-0001'
```

**Tip:** Add time range filter (top-right) to narrow results.

---

### Scenario 2: Find logs for a single process execution

**Use case:** A specific Boomi execution failed. You have the execution ID from the Boomi console.

**Query:**
```
meta.boomi_execution_id = 'af28d68a-962f-41c7-83d8-57fb06c04d0d'
```

**Where to find execution ID:**
- Boomi AtomSphere → Process Reporting → Execution ID
- Or in the audit log: `meta.boomi_execution_id` field

---

### Scenario 3: Find all errors for your process

**Use case:** Your Boomi process is failing intermittently. You want to see all errors.

**Query:**
```
meta.boomi_process_id = 'EU-TC-0001' AND severity_text = 'ERROR'
```

**Severity levels:**
- `INFO` — Normal operations
- `WARN` — Warnings (e.g., config fallback)
- `ERROR` — Business failures (e.g., validation errors, MongoDB write failures)
- `FATAL` — Critical failures (e.g., retry exhausted, data loss imminent)

---

### Scenario 4: Find MongoDB write failures

**Use case:** MongoDB is slow or unavailable. You want to know which audit records were lost.

**Query:**
```
error_code = 'MONGO-WRITE-FAILED' AND meta.boomi_process_id = 'EU-TC-0001'
```

**What to check:**
- `resource_id` — Which document failed to write?
- `meta.retry_count` — How many retries occurred?
- `meta.failure_type` — Why did it fail? (`mongo_write_error`, `connection_timeout`, etc.)

---

### Scenario 5: Trace end-to-end flow (Boomi → OMS → MongoDB)

**Use case:** A customer order failed. You want to trace it across all systems.

**Query:**
```
trace_id = 'test-mongo-da79ee87-9155-4ac1-bba3-de5df3047e9f'
```

**Where to find trace_id:**
- Boomi process logs: `trace_id` field
- OMS backend logs: `trace_id` header
- MongoDB audit log: `trace_id` field

**Result:** All logs with same `trace_id` = complete request journey.

---

### Scenario 6: Find all Boomi-related logs (wildcard)

**Use case:** You want to see ALL Boomi activity, not just one process.

**Query:**
```
resource_type LIKE 'boomi.%'
```

**Explanation:** 
- `resource_type` identifies the business entity (e.g., `boomi.document`, `orders.order`)
- `LIKE 'boomi.%'` matches anything starting with `boomi.` (wildcard)

---

## Understanding the Log Structure

When you click a log entry, you'll see these fields:

### Core Fields (always present)

| Field | Example | Description |
|-------|---------|-------------|
| `body` | "MongoDB write failed..." | Human-readable message |
| `timestamp` | `2026-08-06T07:02:34Z` | When the event occurred (UTC) |
| `severity_text` | `ERROR` | Log level |
| `trace_id` | `test-mongo-...` | Unique ID for entire request flow |

### Business Context Fields

| Field | Example | Description |
|-------|---------|-------------|
| `action` | `boomi.document.load` | What operation was attempted |
| `resource_type` | `boomi.document` | What type of entity |
| `resource_id` | `TCHIBO-ORDER-001.csv` | Specific document/order ID |
| `error_code` | `MONGO-WRITE-FAILED` | Error code (see vocabulary doc) |

### Boomi Metadata Fields

| Field | Example | Description |
|-------|---------|-------------|
| `meta.boomi_process_id` | `EU-TC-0001` | Your Boomi process ID |
| `meta.boomi_execution_id` | `af28d68a-962f-...` | Single execution ID (from Boomi) |
| `meta.failure_type` | `mongo_write_error` | Failure category |
| `meta.retry_count` | `3` | How many retries occurred |

### Internationalization (i18n) Fields

| Field | Example | Description |
|-------|---------|-------------|
| `tpl_message.key` | `boomi.document.loaded` | Template key for i18n lookup |
| `tpl_message.params.*` | `document_name: "..."` | Template parameters |

---

## Troubleshooting Tips

### Problem: No logs found for my process ID

**Check:**
1. Is the process ID correct? (case-sensitive)
2. Did the process actually run? (check Boomi AtomSphere)
3. Are you searching the right time range? (expand to last 24h)
4. Is the Boomi process configured to emit audit logs? (check process library calls)

**Solution:** 
- Search by `service.name = 'mongo-audit-test'` first (broader)
- Then narrow down with `meta.boomi_process_id`

---

### Problem: Logs are missing fields

**Check:**
- Is the Boomi process using the latest `BoomiAuditLogLibrary.groovy`?
- Are all required fields passed to `writeAuditLog()`?

**Solution:**
- Update Boomi process to use unified schema (v2.3)
- See `docs/references/audit-log-contract.md` for required fields

---

### Problem: MongoDB write failures not showing up

**Check:**
- Are you searching with `error_code = 'MONGO-WRITE-FAILED'`?
- Did the failure occur within the 90-day SigNoz retention window?

**Note:** If MongoDB write fails, the audit record ONLY exists in SigNoz (disaster recovery). It will NOT be in MongoDB.

---

## Building Custom Dashboards

### Dashboard 1: Boomi Process Health

**Widgets:**
1. **Error Rate** (Time Series): Count of `severity_text = 'ERROR'` grouped by hour
2. **Top Errors** (Table): Group by `error_code`, sorted by count (descending)
3. **MongoDB Failures** (Gauge): Count of `error_code = 'MONGO-WRITE-FAILED'` (last 1h)

**Filter variable:** `meta.boomi_process_id` (dropdown: EU-TC-0001, EU-MC-0001, etc.)

---

### Dashboard 2: Document Processing Pipeline

**Widgets:**
1. **Pipeline Stages** (Sankey): Flow from `boomi.document.load` → `transform` → `validate` → `store`
2. **Processing Volume** (Bar Chart): Count by `action` (last 24h)
3. **Failed Documents** (Table): List of `resource_id` where `severity_text = 'ERROR'`

---

## Advanced Queries

### Find all logs with retry attempts

```
meta.retry_count > 0
```

### Find logs with specific exception type

```
meta.exception = 'MongoTimeoutException'
```

### Find all critical failures (data loss risk)

```
error_code = 'MONGO-RETRY-EXHAUSTED' AND meta.will_retry = false
```

### Group by Boomi process to see which is failing most

```
resource_type LIKE 'boomi.%' AND severity_text = 'ERROR'
```
Group by: `meta.boomi_process_id`

---

## Best Practices

### 1. Always emit trace_id from Boomi

In your Boomi process, generate a `trace_id` at the start and pass it to all downstream calls:

```groovy
def traceId = UUID.randomUUID().toString()
// Pass traceId to writeAuditLog(), REST API calls, etc.
```

**Why:** Enables end-to-end tracing across Boomi + OMS + MongoDB.

---

### 2. Use structured metadata

Don't put business data in the `message` field. Use `meta.*` instead:

**Bad:**
```groovy
message: "Order ORD-001 failed validation - missing customer_id"
```

**Good:**
```groovy
message: "Order validation failed - missing required field"
meta: [
  order_id: "ORD-001",
  missing_field: "customer_id"
]
```

**Why:** Structured metadata is queryable. Free-text messages are not.

---

### 3. Use error codes, not error messages

**Bad:**
```groovy
error_code: "Connection timeout after 5 seconds"
```

**Good:**
```groovy
error_code: "MONGO-CONN-0001"
message: "Connection timeout after 5 seconds"
```

**Why:** Error codes are stable. Messages change. See `docs/references/logging-vocabulary.md` for standard codes.

---

## Getting Help

**Documentation:**
- `docs/references/audit-log-contract.md` — Unified schema definition
- `docs/references/logging-vocabulary.md` — Action/error code vocabulary
- `docs/guides/architect-reference.md` — Logging architecture

**Operations:**
- SigNoz not accessible? Contact ops team for port-forward/credentials
- MongoDB unavailable? SigNoz is your disaster recovery backup — use it!
- Need new error code? Submit PR to `logging-vocabulary.md`

---

## Summary

**Quick checklist for finding your logs:**

1. ✅ Port-forward to SigNoz UI
2. ✅ Go to Logs → Explorer
3. ✅ Filter by `meta.boomi_process_id = 'YOUR-ID'`
4. ✅ Add time range / severity filters as needed
5. ✅ Click log entry to see full context

**Key insight:** 
If MongoDB is down, SigNoz has ALL the business context you need for disaster recovery. The unified 10-field schema ensures audit records are NEVER lost, even when MongoDB is unavailable.
