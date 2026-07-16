# Error Code Standard Design

## Goal

Standardize audit-log error codes across OMS and connected enterprise systems,
then update every active MongoDB repository document and executable example
that uses the legacy error-code style.

## Canonical Format

Error codes use:

```text
<SYSTEM>-<MODULE>-<NNNN>
```

Examples:

```text
OMS-PD-0001
BOM-OD-0001
365-RP-0001
```

The segments are:

| Segment | Allowed values | Meaning |
|---|---|---|
| `SYSTEM` | `OMS`, `ART`, `BOM`, `365`, `IPP` | System that owns the error definition |
| `MODULE` | `PD`, `OD`, `FC`, `JC`, `UR`, `PS`, `RP` | Stable business module |
| `NNNN` | `0001` through `9999` | Zero-padded sequence allocated independently within each system/module namespace |

The validation expression is:

```regex
^(OMS|ART|BOM|365|IPP)-(PD|OD|FC|JC|UR|PS|RP)-\d{4}$
```

Codes are uppercase, immutable after publication, and never reused. A central
registry must prevent duplicate allocation within a system/module namespace.
The numeric suffix does not encode severity, transport status, retryability,
or environment.

## Error Contract

The error code identifies a stable error condition; it does not replace:

- a sanitized human-readable `message`;
- `trace_id` or request/correlation identifiers for one occurrence;
- `meta.status` or an HTTP status;
- operational exception details in SigNoz.

Audit success remains `error_code: null`. Audit failure requires a non-null
canonical error code.

## Repository Update Scope

Update active documentation and executable examples:

- `docs/references/audit-log-contract.md`
- `docs/guides/boomi-integration-guide.md`
- `docs/guides/boomi-audit-log-owner-guide.md`
- `scripts/write-auditlog-and-telemetry.groovy`
- `scripts/run-audit-telemetry-test.sh`

Use `BOM-OD-0001` for the existing Boomi order/document ingestion failure
examples. Do not rewrite historical design/plan documents. Do not add runtime
format validation to `BoomiAuditLogLibrary` in this documentation-focused
change.

## Verification

- Search active docs and executable examples for legacy `ERR_*`,
  `*_ERR_*`, and `BOOMI_ON_ERROR` values.
- Confirm all non-null sample codes match the canonical expression.
- Run existing shell syntax checks and any repository-provided audit sample
  validation that does not require unavailable infrastructure.
