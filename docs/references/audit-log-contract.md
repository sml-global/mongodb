# Audit Log Contract

Canonical document contract for business audit events written by OMS services,
Boomi processes, and other integration modules. Aligned with the production
`AuditLogEntry` Pydantic model in `oms-backend` (`apps/core/schemas.py`) — that
model is the source of truth for the field set; this document explains how to
use it and adds producer-side conventions on top where the model itself is
permissive.

**Who this is for:** Developers and architects who produce or validate audit
records. If you are a Boomi process owner, read
[Boomi Audit Log Guide (Process Owner Edition)](../guides/boomi-audit-log-owner-guide.md)
instead — it explains the same ideas in plain language, with no coding or IT
background needed.

| Field | Value |
|---|---|
| **Contract version** | 2.2 |
| **Status** | Required for new audit-log integrations |
| **Effective date** | 2026-07-16 |
| **Owner / approver** | OMS Architecture |
| **Supersedes** | 2.1 (2026-07-14) |
| **Source of truth** | `oms-backend` `apps/core/schemas.py` — `AuditLogEntry`, `TplMessage`, `AuditLogMeta` |
| **Per-record marker** | `tpl_message.params.contract_version: "2.2"` (optional; see [Reserved Params](#reserved-params)) |

**Related docs:**
- [Boomi Integration Guide](../guides/boomi-integration-guide.md) — how Boomi calls the audit writer
- [Enterprise Architecture](../guides/enterprise-architecture.md) — immutability, retention, PII, and platform boundaries
- [Glossary](glossary.md) — audit and telemetry terminology

---

## TL;DR — The Minimal Happy Path

> **Audience:** Developer. If you read only one section, read this one.

Only four things are strictly required: `time`, `action`, `resource_type`, and
`meta` (with `meta.boomi_process_id`/`meta.main_program_code`/`meta.sub_program_code`). Everything else —
`trace_id`, `ip`, `error_code`, `resource_id`, `user_id`, `impersonator_id`,
`message`, `tpl_message`, `resource_changes` — is optional. Supply a field
whenever you have the information; do not invent a placeholder value just to
fill it in.

```json
{
  "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ip": "10.0.1.45",
  "time": "2026-07-13T10:30:00.123Z",
  "action": "load",
  "error_code": null,
  "resource_type": "boomi.document",
  "resource_id": "TCHIBO-0001.csv",
  "user_id": null,
  "message": "EDI file transformed to ELT-ready JSON",
  "tpl_message": {
    "key": "boomi.document.loaded",
    "params": { "file_name": "TCHIBO-0001.csv" }
  },
  "meta": {
    "boomi_process_id": "EU-TC-0001",
    "main_program_code": "EU",
    "sub_program_code": "TC"
  }
}
```

**The five golden rules:**

1. **Only `time`, `action`, `resource_type`, and `meta` are required.** Every other field is optional — supply it when known, omit it (or use `null`) otherwise.
2. **`action` is a verb from the controlled registry** (for example `confirm`, `cancel`, `load`, `receive`).
3. **`error_code` decides the outcome** (`null` = succeeded, non-null = failed). Do not encode the outcome anywhere else — not in `action`, not in `tpl_message.key`.
4. **Audit completed business facts, not timing or progress.** Duration, "started", "running", and retries go to SigNoz, not here.
5. **No secrets, no raw payloads.** Prefer pseudonymous identifiers and keep message params minimal.

---

## Non-Goals — What This Collection Is NOT For

> **Audience:** Developer, DBA, Compliance.

| Do not use it for | Use instead | Why |
|---|---|---|
| Timing, duration, SLA, "is it still running" | SigNoz spans/metrics | Timing is telemetry; it would bloat an immutable compliance store. |
| Read/access logging ("who viewed this order") | A dedicated high-volume access-log pipeline | View traffic dwarfs write traffic and would overwhelm the audit store. |
| Debug logs, stack traces, retry diagnostics | SigNoz logs | Operational detail is not compliance evidence. |
| Application state or a message bus | The owning service / queue | Audit is an append-only record of facts, not live state. |

---

## Purpose

This contract documents the canonical shape of an audit record shared by every
producer — OMS backend services, Boomi processes, and other integration
modules — so a record written by any one of them means the same thing and is
queryable the same way. It mirrors the production `AuditLogEntry` model in
`oms-backend`; **this document and that model must be updated together.** Do
not add a new top-level field here without also adding it to the Pydantic
model, and vice versa. Module-specific flexibility exists inside
`tpl_message.params`, subject to the common rules in this document.

## Terminology

| Term | Definition |
|---|---|
| **Module** | A producing bounded context that owns one or more `tpl_message.key` templates and their module params — for example the OMS orders service or the Boomi EDI loader. Boomi as a platform is not a module; each producing process/domain is. |
| **Event origin** | The code that first knows a business event occurred and mints its identifiers and correlation context. |
| **Trusted edge** | The first trusted system boundary (API gateway, OMS request handler, job launcher, Boomi listener) that creates `trace_id`. |
| **Entity event** | An audit record for a single business resource (for example one order). |
| **Execution summary** | A supplementary audit record describing a batch/job that coordinated many entity events. |

## Conformance Status

> **Audience:** DBA, Compliance. This separates what the current library
> enforces from what the target architecture requires. Do not assume a rule is
> enforced just because it appears in this contract.

| Rule | Status |
|---|---|
| Required fields enforced: `time`, `action`, `resource_type`, `meta` (with `boomi_process_id`/`main_program_code`/`sub_program_code`) | Enforced by library |
| `time` auto-generated/parsed as a native BSON Date when absent or supplied as an ISO-8601 string, with strict (non-lenient) parsing | Enforced by library |
| `trace_id` reused from an active OpenTelemetry span context when one exists, otherwise auto-generated (UUID) and returned to the caller | Enforced by library |
| `meta` validation requires all three Boomi identity fields (`boomi_process_id`, `main_program_code`, `sub_program_code`) | Enforced by library |
| MongoDB URI, database, and collection resolved internally (caller never supplies them) | Enforced by library |
| Emit critical telemetry via the OpenTelemetry Logs SDK (OTLP/HTTP to SigNoz) and record the exception on the active span if one exists, then throw on any write failure (no fail-soft variant) | Enforced by library |
| `impersonator_id` populated for delegated/impersonated actions | Target — no current producer sets this |

Operational enforcement (insert-only role, retention/legal-hold, payload
lifecycle, KMS, clock discipline) is owned by
[Enterprise Architecture](../guides/enterprise-architecture.md).

## Fixed Document Structure

An audit producer supplies these fields, mirroring `oms-backend`'s
`AuditLogEntry`. Only `time`, `action`, `resource_type`, and `meta` are
required; everything else is optional and may be omitted or `null`. MongoDB
adds its own `_id` storage field when the document is inserted; producers must
not set `_id` themselves.

```json
{
  "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ip": "10.0.1.45",
  "time": "2026-07-13T10:30:00.123Z",
  "action": "load",
  "error_code": null,
  "resource_type": "boomi.document",
  "resource_id": "TCHIBO-0001.csv",
  "user_id": null,
  "impersonator_id": null,
  "message": "EDI file transformed to ELT-ready JSON",
  "tpl_message": {
    "key": "boomi.document.loaded",
    "params": { "file_name": "TCHIBO-0001.csv" }
  },
  "meta": {
    "boomi_process_id": "EU-TC-0001",
    "main_program_code": "EU",
    "sub_program_code": "TC"
  }
}
```

No other top-level fields are part of this contract. Extend via
`tpl_message.params`, not by
inventing new top-level keys — a new top-level field requires updating the
Pydantic model and this document together.

## Top-Level Field Definitions

| Field | Type | Required | Contract |
|---|---|---|---|
| `trace_id` | String/null | No | Correlates records/telemetry for one logical cross-system operation. The library reuses an active OpenTelemetry span's trace ID when one exists, otherwise auto-generates a UUID. It is shared, not unique per record — not a value the caller needs to construct. |
| `ip` | String/null | No | Trusted originating actor/client IP. Behind proxies, use only an ingress-normalized value or a validated forwarding header. Use `null` when it can't be established reliably. |
| `time` | Date (BSON) | Yes | Business event time, stored as a native MongoDB Date. Supply an ISO-8601 UTC string (with milliseconds) or omit it; the library parses/generates the Date itself. |
| `action` | String | Yes | `{resource_type}.{verb}`, for example `orders.order.confirm`. The verb comes from the registry; the full string equals `resource_type` + `.` + verb. |
| `error_code` | String/null | No | `null` means succeeded. A failure must use the canonical non-null format documented in [Success And Failure](#success-and-failure). Never store exception text or a stack trace here; keep human detail in `message`/`tpl_message.params` and technical exception detail in SigNoz. |
| `resource_type` | String | Yes | Namespaced business noun `{context}.{scope}`, for example `orders.order` or `boomi.document`. |
| `resource_id` | String/null | No | Identifier of the resource. Recommended: a UUID for an internally-generated OMS entity; for an external entity (an EDI interchange, a D365/PLM record) use that system's own stable identifier rather than inventing a UUID. |
| `user_id` | String/null | No | Actor identifier. Use `null` when there is no human actor (for example Boomi cron-driven process writes). |
| `impersonator_id` | String/null | No | ID of a user acting on behalf of another (for example an admin impersonating a customer). |
| `message` | String/null | No | Short, human-readable, sanitized summary. Not a raw payload or exception dump. |
| `tpl_message` | Object/null | No | `{key: string, params: object}` for structured, i18n-friendly messaging. Omit entirely when there's nothing structured to say. |
| `resource_changes` | Object/null | No | `{field_name: [old_value, new_value]}` for a state transition. Prefer this over inventing `old_status`/`new_status` params. For Boomi EDI load/transform flows, this is typically omitted (`null`) because no canonical source-of-record field transition is expected at the integration step. |
| `meta` | Object | Yes | `{boomi_process_id: string, main_program_code: string, sub_program_code: string}` — Boomi process identity context for audit filtering and reporting. |

Empty strings do not satisfy a required field. A nullable field being absent
and a nullable field explicitly set to JSON `null` are both acceptable.

### `meta` For Boomi Producers

`meta` is required and must include:

- `boomi_process_id`
- `main_program_code`
- `sub_program_code`

These fields identify which Boomi process emitted the audit event and are used
for filtering and reporting.

## Naming Rules

### Resource Type: Noun

`resource_type` identifies what was acted on. It must:

- use exactly two lowercase `snake_case` segments separated by a period;
- use a bounded context as the first segment and a resource noun as the second;
- be chosen from the controlled `context.scope` registry, not invented inline;
- remain stable when the implementation or source system changes.

The `context` and `scope` vocabularies are closed enums in the Git registry, for
example:

- `context`: `orders`, `products`, `users`, `fcs`, `jccs`, `elt`, `boomi`, `rfid`
- `scope`: `order`, `product`, `user`, `fc`, `jcc`, `process`, `subprocess`,
  `artwork`, `image`, `document`, `batch`, `prozip`, `mo`

Valid examples:

```text
orders.order
products.artwork
elt.process
boomi.subprocess
```

`batch` is an execution scope used only for a bulk execution summary
(`orders.batch`), never for a business entity. `mo` (manufacturing order) is
its own business entity distinct from `order` — use `orders.mo` for an MO's
own lifecycle (for example `orders.mo.create`, `orders.mo.flag`), and reserve
`orders.order` for the sales order itself; do not fold MO events into the
order's `resource_type` just because the two are related. Invalid examples
include `confirm_order` (verb included), `BoomiProcess` (wrong format), and
`process` (no context).

### Action: Verb From Registry

`action` is a verb chosen from the controlled registry. Keep it simple and
stable so dashboards and filters can aggregate behavior consistently.

Registry examples: `create`, `confirm`, `cancel`, `validate`, `load`, `receive`,
`rollback`, `upload`, `approve`, `promote`, `demote`, `activate`, `deactivate`,
`group`, `ungroup`, `associate`, `tag`, `generate`, `serialize`, `start`,
`complete`, `compress`, `uncompress`, `copy`, `delete`, `update`, `merge`,
`sync_to_d365`, `sync_from_d365`, `sync_from_plm`, `flag`.

`start`/`complete` are lifecycle verbs, not a general substitute for a
completed milestone. Prefer a milestone verb (`receive`, `load`) when only the
completed fact matters. Use `start`/`complete` only when a process's lifecycle
boundaries must themselves be audited (for example an EDI load's start and
completion); pair them via the same `trace_id`, and keep them at process/file
grain, never per record — a per-record `start`/`complete` at EDI volume is
exactly the write-storm the fan-out rule exists to prevent.

Audit **completed business milestones**, not technical lifecycle. A process
beginning is recorded as the completed fact `receive` (the file/work was
accepted), which can itself succeed or fail; it is never a bare `start`.
Duration, "running", and progress belong in SigNoz.

| Anti-pattern | Compliant | Reason |
|---|---|---|
| `action: "confirm_order"` | `action: "confirm"` | Action values should be stable verbs from the registry. |
| `action: "validation_failed"` | `action: "validate"` + `error_code` | The outcome lives in `error_code`, not the verb. |
| `resource_type: "bulk"` | `resource_type: "orders.batch"` | `bulk` destroys business entity identity. |

Prefer a small stable vocabulary of verbs. Adding one requires a registry pull
request; renaming a verb changes the query contract and requires architecture
review.

### User ID Guidance

`user_id` is a plain optional string in the backend schema — there is no
Pydantic-enforced format.

- Use an opaque, stable user identifier when a human actor exists.
- Use `null` when no human actor exists (for example scheduled/cron Boomi flows).
- Never store email addresses, display names, credentials, access tokens, or
  other mutable/sensitive values in `user_id`.

### Bulk Operations

A bulk action has two distinct concepts: the execution that coordinates the
work and the business entities changed by that execution. They must not be
collapsed into one audit record.

**Entity events are mandatory.** Every business entity whose state was changed
or whose requested change failed must receive its own audit event using the
normal entity identity, for example:

```text
resource_type: orders.order
resource_id: ORD-001
action: confirm
```

This preserves existing entity-timeline queries and provides complete evidence
for each resource. Audit semantics must not change at an arbitrary batch-size
threshold. The absence of an entity event never means that the entity action
succeeded.

An execution summary is supplementary:

- If the domain has a governed batch or job resource, emit a summary audit
  event using that resource type and ID, for example `orders.batch` and
  `BATCH-1001`.
- If no natural execution resource exists but a summary is required, generate a
  stable identifier before work starts (a UUID is recommended), for example
  `orders.batch` and `f4d5e6f7-a8b9-4c1d-9e2f-5a6b7c8d9e1f`. Every retry of
  that execution reuses the same identifier.
- Do not use a shared sentinel such as `"BULK"` or `"MULTIPLE"`; it destroys
  resource identity and makes unrelated operations indistinguishable.
- The summary and all entity events share the same `trace_id` for correlation.
- If needed, every entity event may carry the summary operation identifier in a
  module-defined `tpl_message.params` key.
- A summary may include bounded counts and IDs, but supplementary data must not
  replace mandatory entity events.
- Emit the completed summary only after all business outcomes are known.

For high-volume operations, preserve these semantics and control load with a
durable queue, bounded producer concurrency, chunked MongoDB bulk writes, and
backpressure. A module must not suppress successful entity audit events merely
to reduce write volume.

## Success And Failure

This contract records completed business attempts only:

- `error_code == null` means the action succeeded.
- `error_code != null` means the action failed.
- A failure must never be written with a null `error_code`.
- A success must never carry an `error_code`.

Canonical error codes use the format `<SYSTEM>-<MODULE>-<NNNN>`. Examples:
`OMS-PD-0001` (Order Management System / Product) and `365-RP-0001`
(Dynamics 365 / Report).

**System legend**

| Code | Full name |
|---|---|
| `OMS` | Order Management System |
| `ART` | Artwork Center |
| `BOM` | Boomi |
| `365` | Dynamics 365 |
| `IPP` | IPP |

**Module legend** — these meanings are global across systems and are not
redefined per system namespace.

| Code | Full name |
|---|---|
| `PD` | Product |
| `OD` | Order |
| `FC` | Format Center |
| `JC` | JCC |
| `UR` | User |
| `PS` | PPS |
| `RP` | Report |

Canonical format summary:

| Part | Allowed values | Rule |
|---|---|---|
| `SYSTEM` | `OMS`, `ART`, `BOM`, `365`, `IPP` | Uppercase system namespace owned by the producing system. |
| `MODULE` | `PD`, `OD`, `FC`, `JC`, `UR`, `PS`, `RP` | Uppercase module namespace owned by the producing bounded context; the code meanings above are global across all systems. |
| `NNNN` | `0001`-`9999` | Exactly four digits, zero-padded, allocated independently inside each system/module namespace. |

Exact regex:

```regex
^(OMS|ART|BOM|365|IPP)-(PD|OD|FC|JC|UR|PS|RP)-(?!0000)\d{4}$
```

Rules:

- codes are uppercase;
- use only the system and module registries above;
- once published, a code is immutable;
- codes are never reused;
- a central registry allocates codes and prevents duplicates;
- the numeric suffix does not encode severity, environment, HTTP status, or retryability;
- the error code is separate from the sanitized message, trace/request ID, `meta.status`/HTTP status, and SigNoz exception detail.

The detailed sanitized explanation belongs in `message` and approved
`tpl_message.params`; technical exceptions belong in SigNoz.

Started, retrying, warning, and progress events are operational telemetry, not
completed business audit outcomes. Send them to SigNoz rather than inventing
additional audit outcomes.

## Multi-Step Actions And Warnings

> **Audience:** Developer.

A single business action such as `confirm` can involve several
internal steps (for example: validate address, check inventory, charge
payment, notify ERP), and a step may need to communicate a caution that is not
a failure. Do not model this by nesting an array of messages inside
`tpl_message.params` — an audit trail records facts as they happen, not a
bundled report written after the fact.

**Write one record per step, immediately, as its own action.** Each step:

- uses its own action verb (for example `validate`, `check_inventory`);
- carries its own `error_code` (`null` or a stable failure code);
- shares the same `trace_id` (and the same `resource_type`/`resource_id` when
  the steps act on one entity) so the sequence is reconstructed by querying
  `trace_id` sorted by `time`.

**Warnings are a verb, not a third outcome.** The outcome stays binary
(`error_code` null/non-null); there is no `warning` outcome. A *technical*
warning (slow response, an internal retry, elevated latency) remains
operational telemetry in SigNoz, per [Success And Failure](#success-and-failure).
A *business-meaningful* caution attached to a completed step — one a compliance
reviewer would want to see — is audited as its own event using a dedicated
`flag` verb, `error_code: null`, and a `message`/`params` describing the
caution, for example `action: "orders.order.flag"`,
`message: "Address partially matched; proceeding with best match"`. This keeps
it independently queryable via `action` without overloading `error_code`.

This also explains why we rely on at-least-once semantics rather than
deduplication: because each step is written immediately as its own record
instead of being batched, a duplicate row from an ambiguous write retry is a
harmless repeated fact, and a genuine repeat attempt is correctly a second,
distinct fact. Neither case benefits from deduplication — see
[Correlation Rules](#correlation-rules).

## Structured Messaging And State Changes

### `tpl_message` (optional)

`tpl_message` is entirely optional; omit it when there is nothing structured
to say. When present it has exactly two fields, with a clear division of
responsibility between them:

```json
{
  "key": "orders.order.confirmed",
  "params": { "order_no": "ORD-2024-001" }
}
```

- **`key`** is the identifier a message-template engine uses to **look up**
  which i18n template to render. It is a free-form, producer-chosen string —
  it is **not** derived by the library and has no fixed segment count. Keep a
  key's meaning stable once introduced; give a genuinely new business meaning
  a new key rather than repurposing an old one.
- **`params`** are the values that same template engine **substitutes into**
  the placeholders of the looked-up template (for example a template
  `"Order {order_no} confirmed"` substituting `order_no` from `params`).
  `params` defaults to an empty object and is the only module-specific
  extension point in this document (see
  [Module-Owned Params](#module-owned-params)).

Do not place process identity fields (`boomi_process_id`, `main_program_code`,
`sub_program_code`) in `tpl_message.params`; those belong to `meta`.

In short: `key` says *which* message, `params` supplies *what* goes in it.

### `resource_changes` (optional, prefer this for state transitions)

For Boomi EDI load/transform integrations, `resource_changes` is generally not
needed and should usually be omitted (`null`). Use it only when the Boomi step
is truly asserting a before/after change on a canonical business resource field.

Use the real, indexable `resource_changes` field — not ad hoc `params`
fields — to record a field-level state transition:

```json
"resource_changes": {
  "status": ["PENDING", "PROCESSING"],
  "confirmed_at": [null, "2026-07-13T10:30:00.123Z"]
}
```

Format: `{field_name: [old_value, new_value]}`. Do not duplicate this as
`old_status`/`new_status` params inside `tpl_message.params`.

### Module-Owned Params

Each module may define the JSON fields it needs inside `tpl_message.params`.

Every module must document, for each template key:

- required and optional parameter names;
- JSON type for every parameter;
- whether a value is sensitive and how it is masked;
- one success or failure example as applicable.

Parameter names use lowercase `snake_case`. Values must be JSON-serializable.
Do not repeat fixed top-level fields such as `trace_id`, `action`,
`resource_type`, `resource_id`, or `user_id` inside `params`.

### Reserved Params

These names have contract-wide meaning and sit flat, directly in
`tpl_message.params`, alongside a module's business fields. A module must not
reuse a reserved name for a different purpose. Because `tpl_message` itself is
optional, a record must include `tpl_message` (even with a generic `key`) if
it needs to carry any of these.

| Param | Type | Required | Rule |
|---|---|---|---|
| `contract_version` | String | Recommended | Version of this contract the record was produced against, for example `"2.2"`. |
| `tenant_id` | String | Recommended | Stable tenant/brand identifier. |
| `operation_id` | String | Conditional | On an entity event, the `resource_id` of its execution summary. |
| `parent_operation_id` | String | Conditional | On an async child operation, the parent operation's ID. |
| `affected_ids` | Array of strings | Conditional | Bounded list of resources in a bulk summary. Omit when it would exceed the size limits. |
| `affected_count` | Integer | Conditional | Total resources targeted by a bulk operation. Zero or greater. |
| `success_count` | Integer | Conditional | Entity actions that succeeded. Required on a completed bulk summary. |
| `failure_count` | Integer | Conditional | Entity actions that failed. Required on a completed bulk summary. |
| `failed_ids` | Array of strings | Optional | Bounded diagnostic list of failed IDs. Never present a partial list as complete. |
| `payload_uri` | String | Optional | Reference to an approved encrypted private object for an offloaded payload. |
| `payload_sha256` | String | Conditional | Hex SHA-256 of the `payload_uri` object; required whenever `payload_uri` is present, for integrity and 404 detection. |

For a completed bulk summary:

- `success_count + failure_count` must equal `affected_count`;
- `error_code` is `null` only when `failure_count` is zero;
- a partial result uses a stable non-null code such as `OMS-OD-0001`;
- `affected_ids` and `failed_ids` contain only string IDs and must not
  be silently truncated;
- when an ID list is omitted due to size, `affected_count` and a governed
  `payload_uri` (with `payload_sha256`) are required;
- a bounded diagnostic subset must be documented by the module as a subset and
  must not appear to be the complete list.

Counts summarize the execution; they do not replace the mandatory entity audit
events.

`payload_uri` must not be a public URL, presigned URL, or URI containing
credentials or personal data. The referenced object must have access control,
encryption, and a storage lifetime greater than or equal to the audit retention
period, and it must be deleted in coordination with the audit record so no
orphaned payload outlives its index.

## Data Protection And Size Rules

The module extension point is not a raw-payload escape hatch.

- Never store passwords, access tokens, API keys, connection strings, payment
  card data, or authentication headers.
- Prefer pseudonymous references over personal data. Identities should use
  opaque tokens in `user_id`; keep the
  token-to-identity mapping in a separate, mutable, erasable identity store so a
  right-to-be-forgotten request is satisfied by severing the mapping rather than
  mutating the immutable audit record. Crypto-shredding is only a fallback for
  payloads that must be retained in full.
- Omit personal data unless it is necessary audit evidence. Mask any permitted
  personal data before calling the library.
- Do not store complete EDI, XML, JSON, request, response, or file content in
  `message` or `params`.
- Do not store stack traces, SQL statements, or unrestricted exception text.
- A serialized `tpl_message.params` object must not exceed 32 KiB.
- A complete serialized audit document must not exceed 64 KiB.

Exceeding a limit is a validation failure. The library must not silently
truncate evidence because truncation could make an audit record misleading.

## Correlation Rules

The first trusted system boundary, such as an API gateway, OMS request handler,
scheduled-job launcher, or Boomi listener, owns `trace_id` creation. All systems
participating in that logical operation must propagate the same value through
the standard transport context, for example a trusted HTTP trace header or a
Boomi Dynamic Process Property. Module code must not invent a new trace ID for
each audit call.

The audit library resolves `trace_id` in this order:

1. use the explicitly supplied value;
2. read the approved runtime trace context;
3. generate a fallback UUID when no upstream context exists.

A generated fallback is returned to the caller (in the `writeAuditLog` result)
for reuse by subsequent events; the library must never replace a valid
upstream value.

The current Groovy writer implements steps 2 and 3: it reads the trace ID off
an active OpenTelemetry span (`Span.current().getSpanContext()`) when one is
valid, and otherwise generates a fallback UUID and returns it. Because an OTel
trace ID is a 32-character hex string (not UUID-formatted), `trace_id` should
be treated as an opaque correlation string rather than assumed to always be a
UUID — callers must not parse or validate its format. A caller on a system
that propagates trace context through a different mechanism (for example a
trusted HTTP header the Boomi process reads itself) should continue supplying
`trace_id` explicitly so the two systems still correlate.

`trace_id` is a correlation identifier, not a uniqueness key, and must not have
a unique index. A duplicate record from an ambiguous write retry is an
acceptable, low-cost outcome for an audit trail — see
[Multi-Step Actions And Warnings](#multi-step-actions-and-warnings).

When a parent operation spawns asynchronous children that run beyond the parent
request, do not hold one `trace_id` open across all of them. Each child is its
own operation and links back with `parent_operation_id`, so the causal graph
survives without a long-lived trace.

Recommended indexes:

```javascript
db.auditlogs.createIndex({ trace_id: 1, time: 1 })
db.auditlogs.createIndex({ resource_type: 1, resource_id: 1, time: -1 })
db.auditlogs.createIndex({ action: 1, error_code: 1, time: -1 })
db.auditlogs.createIndex({ user_id: 1, time: -1 })
db.auditlogs.createIndex({ "tpl_message.key": 1, time: -1 })
```

There is intentionally no uniqueness/dedup index on this collection. A global
unique constraint would risk silently dropping a genuinely new event, which is
worse for a compliance store than an occasional duplicate.

Do not use an unanchored regular-expression suffix query as the normal access
path. Query the exact `action` value, or query indexed top-level fields such as
`resource_type`/`resource_id` and `error_code`.

`time` is a native BSON Date, so range queries and sorts (`$gte`/`$lte`,
`sort({ time: -1 })`) use real date semantics rather than string comparison.
Multiple records can still share the same millisecond, so use
`sort({ time: 1, _id: 1 })` for deterministic ordering when ties occur, and use
trace/span relationships in telemetry when causal ordering matters.

## Audit Versus Operational Telemetry

| Business audit in MongoDB | Operational telemetry in SigNoz |
|---|---|
| Completed business action and result | Start/progress/retry events |
| Who acted on which resource | Runtime component, pod, host, thread |
| Stable business error code | Exception class and sanitized stack trace |
| Business event occurrence time | Latency, timeout, retry count, connection status |
| Long-lived compliance evidence | Shorter-lived diagnostic data |

A failed MongoDB audit write must emit sanitized critical operational telemetry
before the library throws — see
[Write Failure Handling](#write-failure-handling). The telemetry event is not a
replacement audit record; the calling process decides how to respond to the
exception.

## Write Failure Handling

> **Audience:** Developer, DBA.

Audit writing is not silent, and it is not swallowed. When a record fails
validation or MongoDB insertion (after the library's bounded internal retries
for transient connection errors are exhausted), the library must:

1. emit a critical, sanitized telemetry event to SigNoz — via the
  OpenTelemetry Logs SDK (OTLP/HTTP), not a hand-built payload — containing
  the failure class, producer, exception type/message/stack trace, and
  `trace_id` when valid; if there is a currently active OpenTelemetry span,
  also record the exception on that span (`Span.recordException`) so it
  appears inline on the trace;
2. then throw an exception.

**The calling Boomi/OMS process is responsible for handling that exception** —
for example by retrying the business step through the process's own retry
shape, alerting a human, or halting the business flow. The audit library does
not maintain a dead-letter queue and does not attempt to guarantee delivery on
the caller's behalf; that responsibility belongs to the process definition,
which already has native error-handling paths in Boomi.

This is deliberately simpler than a durable quarantine/replay pipeline: it puts
failure handling where the business context actually lives (the process),
instead of an out-of-band store that still requires a human or a workflow to
resolve it.

## Validation Responsibilities

The shared audit library must validate the common contract before attempting a
database write:

- required fields present: `time`, `action`, `resource_type`, and `meta`
  (with `meta.boomi_process_id`, `meta.main_program_code`, `meta.sub_program_code`);
- field types and non-empty strings for required fields;
- native BSON Date `time`, generated/parsed by the library;
- `resource_type` naming rules, and that `action` is a registry verb;
- `tpl_message` shape when present (`key` + `params` only);
- `meta` shape (`boomi_process_id`/`main_program_code`/`sub_program_code` present);
- entity fan-out, bulk-summary count, and affected-ID rules;
- prohibited sensitive keys and size limits.

The module owns semantic validation of its registered params, such as whether
`order_no` is required for `orders.order.confirmed`.

Validation failure must prevent insertion. Following
[Write Failure Handling](#write-failure-handling), the library emits critical
sanitized telemetry to SigNoz and then throws so the calling Boomi/OMS process
can decide how to handle it. The library must never silently discard a
validation or insertion failure.

## Module Examples

### Order Confirmation Succeeded

```json
{
  "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ip": "10.0.1.45",
  "time": "2026-07-13T10:30:00.123Z",
  "action": "confirm",
  "error_code": null,
  "resource_type": "orders.order",
  "resource_id": "ORD-2024-001",
  "user_id": "018f2e4a-6b3c-7d21-9a4f-5e6b7c8d9e0f",
  "message": "Order confirmed by customer service agent",
  "tpl_message": {
    "key": "orders.order.confirmed",
    "params": {
      "order_no": "ORD-2024-001",
      "erp_reference": "ERP-99912",
      "contract_version": "2.2",
      "tenant_id": "HK_RETAIL"
    }
  },
  "resource_changes": {
    "status": ["PENDING", "PROCESSING"]
  },
  "meta": {
    "boomi_process_id": "PROC-ORDER-CONFIRM-001",
    "main_program_code": "ORDERS",
    "sub_program_code": "ORDER_CONFIRM"
  }
}
```

### Boomi EDI Document Load Failed

```json
{
  "trace_id": "a47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ip": null,
  "time": "2026-07-13T10:31:12.004Z",
  "action": "boomi.document.load",
  "error_code": "BOM-OD-0001",
  "resource_type": "boomi.document",
  "resource_id": "TCHIBO-0001.csv",
  "user_id": null,
  "message": "EDI document load failed: source file validation error",
  "tpl_message": {
    "key": "boomi.document.load_failed",
    "params": {
      "file_name": "orders-20260713.edi",
      "interchange_control_number": "000012345",
      "failure_reason": "Required interchange header is missing",
      "contract_version": "2.2",
      "tenant_id": "HK_RETAIL"
    }
  },
  "meta": {
    "boomi_process_id": "EU-TC-0001",
    "main_program_code": "EU",
    "sub_program_code": "TC"
  }
}
```

Note the naming: the resource is `boomi.document` (the EDI document being
processed — `document` is a registry scope; `load` is a verb, so
`boomi.load` would be an invalid `resource_type`). The action is the
milestone verb `load`, and **the failure lives only in `error_code`** — the
load was attempted (a completed business fact) and it failed. There is no
`load_failed` action and no failure encoded in the verb, per
[Success And Failure](#success-and-failure).

`resource_id` here uses the input file identity (`TCHIBO-0001.csv`) as the
business-facing Boomi document identifier. Record the interchange control number (ISA13/GS06) as
`interchange_control_number` in `params` rather than relying on `file_name`
for identity — vendors resend the same logical interchange under different
filenames and reuse filenames for different content.

This example omits `resource_changes` on purpose: a Boomi/EDI load,
map, or preprocess step is not naturally a before/after field diff on one
entity, so there is no meaningful old/new value pair to record here. The
field remains part of the contract and the Groovy library validates it when
present — a future Boomi module doing something more state-transition-like
(for example correcting a previously-loaded record's field) can use it — but
today's EDI-loading modules are expected to leave it `null`.

### Bulk Order Confirmation Summary

The operation has its own generated identity. This summary is accompanied by
one entity event per order; it does not replace them.

```json
{
  "trace_id": "b58bd21c-69dd-4a83-9678-1f13c3d4e58a",
  "ip": "203.0.113.42",
  "time": "2026-07-13T10:32:05.117Z",
  "action": "orders.batch.confirm",
  "error_code": null,
  "resource_type": "orders.batch",
  "resource_id": "f4d5e6f7-a8b9-4c1d-9e2f-5a6b7c8d9e1f",
  "user_id": "usr:018f2e4a-6b3c-7d21-9a4f-5e6b7c8d9e0f",
  "message": "Bulk order confirmation completed",
  "tpl_message": {
    "key": "orders.batch.confirmed",
    "params": {
      "contract_version": "2.2",
      "tenant_id": "HK_RETAIL",
      "affected_ids": ["ORD-001", "ORD-002", "ORD-003"],
      "affected_count": 3,
      "success_count": 3,
      "failure_count": 0
    }
  },
  "meta": {
    "method": "BOOMI",
    "path": "orders.batch.confirm",
    "status": 200
  }
}
```

One associated entity event remains directly queryable by the existing order
timeline:

```json
{
  "trace_id": "b58bd21c-69dd-4a83-9678-1f13c3d4e58a",
  "ip": "203.0.113.42",
  "time": "2026-07-13T10:32:05.118Z",
  "action": "orders.order.confirm",
  "error_code": null,
  "resource_type": "orders.order",
  "resource_id": "ORD-001",
  "user_id": "usr:018f2e4a-6b3c-7d21-9a4f-5e6b7c8d9e0f",
  "message": "Order confirmed by bulk operation",
  "tpl_message": {
    "key": "orders.order.confirmed",
    "params": {
      "contract_version": "2.2",
      "tenant_id": "HK_RETAIL",
      "operation_id": "f4d5e6f7-a8b9-4c1d-9e2f-5a6b7c8d9e1f"
    }
  },
  "resource_changes": {
    "status": ["PENDING", "CONFIRMED"]
  },
  "meta": {
    "method": "BOOMI",
    "path": "orders.order.confirm",
    "status": 200
  }
}
```

For a larger batch, the summary may omit long ID lists and keep exact counts.
Entity events are still emitted alongside the summary.

## Change Control

Top-level fields, field meanings, actor prefixes, reserved params, and result
semantics are architecture-owned and mirror `oms-backend`'s `AuditLogEntry`.
Changing any of them requires contract review, a `contract_version` bump, and
coordinated updates to producers, validators, indexes, queries, dashboards,
and documentation; when a change affects the persisted schema or runtime
validation, it also requires a coordinated change to the Pydantic model.

The controlled vocabularies — `context`, `scope`, `action` verbs, the
error-code `SYSTEM` registry, the error-code `MODULE` registry, and published
`error_code` values — are closed enums maintained in a version-controlled
registry in Git. New values are added by pull request with architecture
approval; producers select from the registry and must not invent values inline.

Adding a module-specific template and params does not require a top-level schema
change, but the module must register and document the template before production
use. Existing template meanings must not be changed; introduce a new template
key when the business meaning changes.

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.2 | 2026-07-16 | Documented the canonical `error_code` convention as `<SYSTEM>-<MODULE>-<NNNN>`, with architecture-controlled system/module registries and examples. The stored field type remains `String`/`null`; runtime enforcement of the naming convention is deferred. |
| 2.1 | 2026-07-14 | **Refined trace correlation, meta ergonomics, and messaging wording** — no field-set changes. `trace_id` now reuses an active OpenTelemetry span's trace ID when one exists (implementing correlation-rules step 2), instead of only ever generating a UUID; it is documented as an opaque correlation string since an OTel trace ID is not UUID-formatted. Write-failure telemetry is now emitted through the real OpenTelemetry Logs SDK (OTLP/HTTP) instead of a hand-built payload, and the exception is also recorded on the active span (`Span.recordException`) when one exists. The Groovy library now auto-defaults `meta` for Boomi callers that omit it entirely (`method: "BOOMI"`, `path: action`, `status` derived from `error_code`) — `meta` stays required in the persisted document (per the production Pydantic model) but is effectively optional for a Boomi caller. Tightened the `tpl_message` explanation: `key` is the template-lookup identifier, `params` are the substitution values the template engine interpolates into it. Fixed lenient date parsing in the Groovy library (`SimpleDateFormat` now runs with `setLenient(false)`, rejecting invalid dates like month 13 instead of silently rolling them over). Added `mo` (manufacturing order) to the `scope` registry as its own business entity distinct from `order`. Clarified that `resource_changes` is expected to stay `null` for Boomi/EDI-loading actions (no natural before/after diff) while remaining available to other modules. |
| 2.0 | 2026-07-14 | **Realigned with the production `AuditLogEntry` schema** in `oms-backend` (`apps/core/schemas.py`), which had diverged from this contract. Only `time`, `action`, `resource_type`, and `meta` (with `method`/`path`/`status`) are required — every other field, including `resource_id`, `user_id`, and `tpl_message`, is optional. `action` reverts to the full `{resource_type}.{verb}` string (matching production) instead of a bare verb. Reinstated `resource_changes` (`{field: [old, new]}`) and `meta` as real top-level fields. Added the missing `impersonator_id` field. Dropped the mandatory UUID constraint on `resource_id`/`trace_id`/`operation_id` (recommended for internal entities, but external entities should use their own stable identifier) — the backend schema never enforced this. `tpl_message.key` is no longer library-derived; it is a free-form producer-chosen string, matching the production `TplMessage` model, and `tpl_message` itself is optional. |
| 1.2 | 2026-07-14 | Removed the `std` wrapper — reserved params now sit flat, directly in `tpl_message.params`, alongside module fields. All system-generated identifiers (`trace_id`, `resource_id`, `operation_id`, `parent_operation_id`, and the identifier after `usr:`) are now UUID format. `time` is now a native BSON Date, generated/parsed by the library, not a formatted string. Expanded the action registry with `start`, `complete`, `compress`, `uncompress`, `copy`, `delete`, `update`, `merge`, `sync_to_d365`, `sync_from_d365`, `sync_from_plm`. The Groovy library was rewritten to a single simple `writeAuditLog(Map event)` call: it resolves the MongoDB connection, database, and collection internally; auto-generates `trace_id` (UUID) and `time` (BSON Date) when absent; and always emits critical SigNoz telemetry then throws on any failure — the fail-soft `writeAuditLogSafely` variant was removed. |
| 1.1 | 2026-07-14 | Removed `idempotency_key` and all dedup/uniqueness machinery — duplicates from write retries are an accepted, low-cost outcome. Added [Multi-Step Actions And Warnings](#multi-step-actions-and-warnings): one record per step, `flag` action for business-meaningful warnings. Replaced the DLQ/quarantine model with [Write Failure Handling](#write-failure-handling): the library emits critical SigNoz telemetry then throws, and the calling Boomi/OMS process handles the exception. Added `rfid` (context) and `prozip` (scope) to the registry. Compressed the template-key section — `key` is fully derived and carries no independent meaning. Corrected the `orders.order` confirm examples to a human `usr:` actor. |
| 1.0 | 2026-07-14 | First versioned edition: library-derived keys, `std` namespace with mandatory `contract_version`/`tenant_id`, async `parent_operation_id`, coordinated payload lifecycle with `payload_sha256`, PII pseudonymization, and business-milestone actions (`receive`/`load`) replacing `start`/`stop`. |
