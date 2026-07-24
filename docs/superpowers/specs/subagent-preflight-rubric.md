# Subagent Preflight Rubric

Purpose: provide a mechanically enforceable preflight gate before implementation.
Any implementing agent for the Phase 2 orchestration plan must output a fully
completed table from this file before running commands, editing code, or
requesting commit authorization.

## Completion Rules

1. Every row must be marked `PASS` or `FAIL` (no blanks).
2. Every `PASS` requires concrete evidence (file paths, test names, commands, or rationale).
3. Any `FAIL` blocks implementation until remediated or explicitly waived by user decision.
4. Output must include a short remediation list for all `FAIL` rows.

## Required Preflight Table

| Category | Check | Evidence | Status (PASS/FAIL) | Notes/Remediation |
|---|---|---|---|---|
| Safety | Explicit scope and non-goals are unchanged from approved plan |  |  |  |
| Safety | Fail-closed behavior preserved for unavailable/deferred scopes |  |  |  |
| Safety | No path from unified mode to legacy dev execution |  |  |  |
| Operability | Runbook coverage exists for primary happy-path operator flow |  |  |  |
| Operability | Break-glass/stale-lock procedure is documented and testable |  |  |  |
| Operability | Partial-failure retry behavior is documented with bounded blast radius |  |  |  |
| Portability | CI artifact boundary contract is defined (prepare/execute jobs) |  |  |  |
| Portability | Artifact storage policy selected (native CI vs secure vault) with sensitivity criteria |  |  |  |
| Portability | Toolchain parity checks are defined across prepare/execute jobs |  |  |  |
| Recoverability | Evidence/confirmation lifecycle and anti-replay checks are defined |  |  |  |
| Recoverability | Post-consumption failure recovery path is documented |  |  |  |
| Recoverability | Retention and cleanup invariants are testable without live infra |  |  |  |

## Output Template

Use this heading before the completed table in implementation sessions:

`Phase 2 Preflight Rubric Result`

Then include:

1. Completed required table.
2. `Blocking FAIL items` list (or `None`).
3. `Go/No-Go` decision with justification.
