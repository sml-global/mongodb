# UAT Architecture Issues: Namespace and Logging Inconsistencies

**Identified by:** User  
**Date:** 2026-08-06  
**Status:** Requires architectural decision + remediation

---

## Issue 1: Inconsistent Namespace Naming Convention

### Problem Statement

UAT environment has **inconsistent namespace naming** — some include environment suffix (`-uat`), others don't:

| Namespace | Has `-uat` Suffix? | Correct? |
|---|---|---|
| `mongodb-uat` | ✅ Yes | ✅ Consistent with convention |
| `signoz` | ❌ No | ❌ **Should be `signoz-uat`** |
| `test-audit` | ❌ No | ❌ **Should be `test-audit-uat`** |
| `cert-manager` | ❌ No | ⚠️ Debatable (platform service) |
| `kyverno` | ❌ No | ⚠️ Debatable (platform service) |
| `flux-system` | ❌ No | ⚠️ Debatable (platform service) |

### Root Cause

Different components were provisioned at different times with different assumptions:
- **MongoDB:** Provisioned early, correctly used `mongodb-uat` (from `k8s/overlays/uat/kustomization.yaml`)
- **SigNoz:** Provisioned later, incorrectly used `signoz` (hardcoded in `gitops/signoz/overlays/uat/kustomization.yaml`)
- **Test pod:** Created ad-hoc, didn't follow convention

### User's Valid Question

> "Why namespace sometimes mixed with environment like `mongodb-uat`? We already split environment using AWS account."

**User is correct that:**
- UAT is isolated by AWS account (`672172129937`)
- Dev is isolated by different account (`815402439714`)
- **So environment suffix is technically redundant for security isolation**

### Decision

**✅ Approved:** Option A — Always Include Environment Suffix

**Convention:**
```
# Application workloads (always with -uat suffix)
mongodb-uat
signoz-uat
boomi-uat
test-audit-uat

# Platform services (no environment suffix - shared cluster infrastructure)
cert-manager
kyverno
flux-system
```

**Rationale:**
- ✅ **Multi-tenancy ready** — if we ever need dev+uat in same cluster (cost optimization)
- ✅ **Visual clarity** — `kubectl get pods -A` immediately shows environment
- ✅ **RBAC/network policies** — easier to write rules like "all `-uat` namespaces share X"
- ✅ **Prevents accidents** — harder to run dev script against UAT by mistake
- ✅ **Consistent with GitOps best practices** (ArgoCD, Flux recommend environment in namespace)

### Proposed Remediation

**Phase 1: Document the standard**
1. Add to `docs/references/component-catalog.md`: "All application namespaces MUST include environment suffix (`-uat`, `-dev`). Platform services (cert-manager, kyverno, flux-system) do not."
2. Add validation to CI/CD: script that checks all Kustomize overlays follow the convention

**Phase 2: Fix existing inconsistencies**
1. Rename `signoz` → `signoz-uat`
   - Update `gitops/signoz/overlays/uat/kustomization.yaml`
   - Update `scripts/create-signoz-*.sh` scripts
   - Update `scripts/provision-signoz-observability.sh`
   - Redeploy SigNoz
2. Rename `test-audit` → `test-audit-uat` (or delete — it's just a test)
3. Update all documentation references

**Phase 3: Prevent future drift**
- Add pre-commit hook that validates namespace names
- Update issue #28 certification checklist to include namespace convention check

---

## Issue 2: Inconsistent Log Format (Multiple Formats in Logs)

### Problem Statement

**Logs in SigNoz show multiple formats, making search/filtering difficult:**

1. **Bash debug** (from `set -x` in test pod):
   ```
   + echo 'Attempt 2: Connection failed'
   + sleep 10
   ```

2. **Plain text** (unstructured):
   ```
   Attempt 2: Connection failed (expected)
   Writing failure telemetry to stdout (captured by OTEL agent)...
   ```

3. **JSON structured** (what we want!):
   ```json
   {"level":"ERROR","msg":"MongoDB connection failed","service":"audit-writer","attempt":2,"error":"connection refused"}
   ```

4. **MongoDB client errors** (multi-line, unstructured):
   ```
   MongoNetworkError: getaddrinfo ENOTFOUND nonexistent-mongodb.mongodb-uat.svc.cluster.local
   ```

5. **Java/Groovy exceptions** (stack traces):
   ```
   java.lang.RuntimeException: MongoDB write failed
       at BoomiAuditLogLibrary.writeAuditLog(BoomiAuditLogLibrary.groovy:123)
       at ...
   ```

6. **System warnings** (from Groovy library):
   ```
   WARNING: BoomiAuditLogLibrary could not read Secret mongodb/oms-audit-writer (connection refused); falling back to local dev default
   ```

### User's Valid Question

> "Inside the audit log, there are lots of message in different format which is hard to search, shall we better fix a single format? I guess my groovy library is using json? what about other? can we also fix them to use json? a predefined template?"

**User is correct that:**
- ✅ Groovy library uses **OpenTelemetry structured logging** (converts to JSON in SigNoz)
- ❌ But it also has **plain text fallback** (`System.err.println`)
- ❌ Test pod uses **mixed formats** (bash debug + plain text + JSON)
- ❌ No enforced template across the system

### Current Logging Sources

#### ✅ Already Structured (Good)

**Groovy BoomiOtelLibrary** (`emitCriticalFailure`):
```groovy
otelLogger.logRecordBuilder()
  .setSeverity(Severity.ERROR)
  .setSeverityText('ERROR')
  .setBody("${serviceName} failure: ${failureType}" as String)
  .setAllAttributes(attrs.build())  // Structured key-value pairs!
  .emit()
```

**Shows in SigNoz as:**
- `severity`: ERROR
- `body`: "oms-audit-writer failure: mongo_write"
- `failure.type`: "mongo_write"
- `failure.message`: "Connection timeout"
- `exception.type`: "com.mongodb.MongoTimeoutException"
- `exception.message`: "..."
- `exception.stacktrace`: "..."

**This is perfect!** ✅

#### ❌ Needs Fixing (Unstructured)

**1. Groovy library WARNING messages:**

**Current (plain text):**
```groovy
System.err.println(
  "WARNING: BoomiAuditLogLibrary could not read Secret ${namespace}/${secretName} " +
  "(${e.message}); falling back to local dev default"
)
```

**Proposed fix:**
```groovy
// Replace System.err.println with structured OTEL log
Logger logger = getOrCreateLogger(resolveEndpoint(), SERVICE_NAME)
logger.logRecordBuilder()
  .setSeverity(Severity.WARN)
  .setSeverityText('WARN')
  .setBody('Secret read failed, using fallback')
  .setAllAttributes(Attributes.builder()
    .put('secret.namespace', namespace)
    .put('secret.name', secretName)
    .put('fallback.uri', 'mongodb://127.0.0.1:27017')
    .put('error.message', e.message ?: '')
    .build())
  .emit()
```

**2. MongoDB driver errors** (unavoidable, but can wrap):

The MongoDB Java driver logs plain text errors. We **cannot change the driver**, but we can:
- **Catch** MongoDB exceptions
- **Extract** key details (host, port, error type)
- **Emit** as structured OTEL log via `BoomiOtelLibrary.emitCriticalFailure()`

**Current:** Raw driver error goes to stdout/stderr  
**Proposed:** Groovy library already does this via `emitFailureTelemetry()` ✅

**3. Test pods / ad-hoc scripts:**

**Current mess:**
```bash
echo "Attempt 2: Connection failed"  # Plain text
echo '{"level":"ERROR",...}'         # JSON
set -x                                # Bash debug
```

**Proposed standard:**
```bash
# ALL application pods must log ONLY structured JSON to stdout
echo '{"timestamp":"2026-08-06T09:41:31Z","level":"ERROR","msg":"MongoDB connection failed","service":"audit-writer","attempt":2,"error":"connection refused"}'

# No bash debug (remove 'set -x')
# No plain text status messages
```

### Recommended Logging Standard

#### Two Types of Logs (Different Purposes)

**1. Business Audit Logs** (MongoDB `oms_audit.auditlogs` collection)
- **Purpose:** Compliance, immutable business event records
- **Format:** Follow `docs/references/audit-log-contract.md`
- **Required fields:** `time`, `action`, `resource_type`, `meta`
- **Written by:** `BoomiAuditLogLibrary.groovy`
- **Example:**
  ```json
  {
    "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
    "ip": "10.0.1.45",
    "time": "2026-07-13T10:30:00.123Z",
    "action": "load",
    "error_code": null,
    "resource_type": "boomi.document",
    "resource_id": "TCHIBO-0001.csv",
    "message": "EDI file transformed to ELT-ready JSON",
    "meta": {
      "boomi_process_id": "EU-TC-0001",
      "main_program_code": "EU",
      "sub_program_code": "TC"
    }
  }
  ```

**2. Operational Telemetry Logs** (SigNoz via OpenTelemetry)
- **Purpose:** Debugging, monitoring, alerting, performance analysis
- **Format:** OpenTelemetry structured logs (attributes + body)
- **Written by:** `BoomiOtelLibrary.groovy` `emitCriticalFailure()`
- **How it appears in SigNoz:**
  ```json
  {
    "timestamp": "2026-08-06T09:41:31.084Z",
    "severity": "ERROR",
    "body": "oms-audit-writer failure: mongo_write",
    "service.name": "oms-audit-writer",
    "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
    "failure.type": "mongo_write",
    "failure.message": "Connection timeout after 30s",
    "exception.type": "com.mongodb.MongoTimeoutException",
    "exception.message": "Timed out after 30000 ms...",
    "exception.stacktrace": "..."
  }
  ```

#### Universal Telemetry Schema (For Operational Logs to SigNoz)

**All application telemetry logs MUST follow the OpenTelemetry format used by `BoomiOtelLibrary`:**

**Required attributes:**
- `service.name` — identifies the component (e.g., `oms-audit-writer`, `boomi-edi-loader`)
- `severity` — `ERROR` | `WARN` | `INFO` | `DEBUG`
- `body` — short human-readable message
- `trace_id` — correlation ID (from active OTEL span or generated UUID)

**Optional attributes** (application-specific):
- `failure.type` — category like `validation`, `mongo_write`, `configuration`
- `failure.message` — sanitized error summary
- `exception.type` — Java/Groovy exception class name
- `exception.message` — exception message
- `exception.stacktrace` — full stack trace (for debugging)
- Any domain-specific fields (e.g., `attempt`, `resource_id`, `user_id`)

#### Severity Levels (Aligned with OpenTelemetry)

| Level | When to Use | SigNoz Filter |
|---|---|---|
| `ERROR` | Failures that prevent operation (MongoDB write failed, validation error) | `level:ERROR` |
| `WARN` | Degraded state but operation continues (fallback used, retry attempted) | `level:WARN` |
| `INFO` | Normal operation milestones (audit log written, process started) | `level:INFO` |
| `DEBUG` | Detailed troubleshooting (connection pool stats, query details) | `level:DEBUG` |

#### Language-Specific Implementations

**Groovy (BoomiOtelLibrary):** ✅ Already correct

Current implementation in `scripts/groovy/boomi/BoomiOtelLibrary.groovy`:
```groovy
static void emitCriticalFailure(String serviceName, String failureType, String message, String traceId, Throwable cause = null) {
  Logger otelLogger = getOrCreateLogger(resolveEndpoint(), serviceName ?: 'unknown-service')
  
  AttributesBuilder attrs = Attributes.builder()
    .put('failure.type', failureType ?: '')
    .put('failure.message', message ?: '')
    .put('trace_id', traceId ?: '')
  
  if (cause != null) {
    attrs.put('exception.type', cause.getClass().name)
    attrs.put('exception.message', cause.message ?: '')
    attrs.put('exception.stacktrace', stackTraceToString(cause))
  }
  
  otelLogger.logRecordBuilder()
    .setSeverity(Severity.ERROR)
    .setSeverityText('ERROR')
    .setBody("${serviceName} failure: ${failureType}" as String)
    .setAllAttributes(attrs.build())
    .emit()
}
```

**This is the gold standard** — all other implementations should follow this pattern.

**Bash/Shell scripts:**

For simple operational logs (not business audit), create a helper that sends JSON to stdout (captured by OTEL agent):

```bash
# Helper function (add to scripts/lib/logging-helpers.sh)
log_telemetry() {
  local severity="$1"    # ERROR | WARN | INFO | DEBUG
  local body="$2"        # Human-readable message
  local service="${SERVICE_NAME:-unknown}"
  local trace_id="${TRACE_ID:-$(uuidgen)}"
  local timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  
  # Structured JSON matching OTEL format
  cat <<EOF
{
  "timestamp": "$timestamp",
  "severity": "$severity",
  "body": "$body",
  "service.name": "$service",
  "trace_id": "$trace_id"
}
EOF
}

# Usage:
SERVICE_NAME="mongodb-backup" log_telemetry "ERROR" "Backup failed: disk full"
SERVICE_NAME="mongodb-backup" log_telemetry "INFO" "Backup completed successfully"
```

**Python (for future services):**

Use OpenTelemetry Python SDK (same pattern as Groovy):

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

def emit_telemetry(severity, body, service_name, **attributes):
    """
    Emit structured telemetry log matching Groovy BoomiOtelLibrary pattern.
    
    Args:
        severity: ERROR | WARN | INFO | DEBUG
        body: Human-readable message
        service_name: Service identifier
        **attributes: Additional structured attributes (failure_type, trace_id, etc.)
    """
    logger_provider = LoggerProvider(
        resource=Resource.create({"service.name": service_name})
    )
    set_logger_provider(logger_provider)
    
    exporter = OTLPLogExporter(endpoint="http://signoz-otel-collector.signoz.svc:4318/v1/logs")
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
    
    logger = logger_provider.get_logger(__name__)
    
    logger.emit(
        severity=severity,
        body=body,
        attributes=attributes
    )

# Usage:
emit_telemetry(
    severity="ERROR",
    body="oms-audit-writer failure: mongo_write",
    service_name="oms-audit-writer",
    failure_type="mongo_write",
    failure_message="Connection timeout",
    trace_id="abc123..."
)
```

### Proposed Remediation

**Phase 1: Document the standard**
1. Create `docs/references/logging-standard.md`
2. Define two log types: Business Audit (MongoDB) vs Operational Telemetry (SigNoz)
3. Document that all operational telemetry must follow the `BoomiOtelLibrary` pattern
4. Add to `docs/references/component-catalog.md`: namespace naming convention
5. Add to operator-runbook.md: logging requirements

**Phase 2: Fix namespace inconsistencies**
1. Rename `signoz` → `signoz-uat`
   - Update `gitops/signoz/overlays/uat/kustomization.yaml`
   - Update `scripts/create-signoz-*.sh` scripts
   - Update `scripts/provision-signoz-observability.sh`
   - Redeploy SigNoz
2. Rename `test-audit` → `test-audit-uat` (or delete — it's just a test)
3. Update all documentation references

**Phase 3: Fix Groovy library plain text logging**
1. Replace `System.err.println` in `BoomiAuditLogLibrary.groovy` with `BoomiOtelLibrary.emitCriticalFailure()`
2. Add `log_telemetry()` helper function to `scripts/lib/logging-helpers.sh` (for bash scripts)
3. Update `scripts/write-auditlog-and-telemetry.sh` to use structured logging

**Phase 4: Fix test pods**
1. Remove `set -x` from test pod script
2. Replace plain text `echo` with `log_telemetry` JSON format
3. Update `docs/guides/signoz-access-guide.md` examples to show correct format

### Benefits of Standardization

1. **Easier filtering** — SigNoz queries like `severity:ERROR AND service.name:audit-writer` work consistently
2. **Better alerting** — can alert on structured attributes (e.g., `failure.type = "mongo_write"`)
3. **Simplified parsing** — downstream tools (data warehouse, analytics) get clean structured data
4. **Consistent experience** — all services look the same in SigNoz
5. **Machine-readable** — can build automated remediation (if `failure.type:connection_timeout` then check network)
6. **Clear separation** — business audit (MongoDB) vs operational telemetry (SigNoz) with no confusion

---

## Recommended Actions

### Immediate (This Week)

1. **Document the decisions:**
   - Namespace naming: always include environment suffix (`-uat`) for application workloads
   - Logging standard: follow `BoomiOtelLibrary` pattern for all operational telemetry

2. **Update documentation:**
   - `docs/references/component-catalog.md` — add namespace convention
   - Create `docs/references/logging-standard.md` — two log types (audit vs telemetry)

### Short-term (Next Sprint)

3. **Fix namespace inconsistencies:**
   - Rename `signoz` → `signoz-uat`
   - Update all references in scripts and documentation

4. **Fix Groovy library:**
   - Replace `System.err.println` with `BoomiOtelLibrary.emitCriticalFailure()`
   - Add bash helper for structured telemetry logs

5. **Fix test pods:**
   - Remove bash debug (`set -x`)
   - Use only structured telemetry format

### Long-term (Future Sprints)

6. **Add to issue #28 certification checklist:**
   - ✅ All namespaces follow naming convention
   - ✅ All operational logs use OpenTelemetry structured format
   - ✅ Business audit logs follow audit-log-contract.md
   - ✅ No plain text logs in production

---

## Related Issues

- **Issue #28** — UAT user journey certification (needs namespace/logging checks)
- **Issue #63** — Incomplete destroy (related: namespace cleanup)
- **Future:** Create separate issues for:
  - "Standardize namespace naming across all environments"
  - "Enforce structured JSON logging for all applications"

---

## Questions for User (Answered)

1. **Namespace convention:** ✅ **APPROVED** — Option A (always include `-uat` suffix for application workloads)
2. **Platform services:** ✅ **DECIDED** — Keep without suffix (`cert-manager`, `kyverno`, `flux-system` are shared cluster infrastructure)
3. **Logging standard:** ✅ **APPROVED** — Follow existing `BoomiOtelLibrary` OpenTelemetry pattern for operational telemetry; separate business audit logs follow `audit-log-contract.md`
4. **Remediation priority:** Fix namespaces and document standards first, then fix logging implementations
