# Error Code Standard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace legacy audit error-code guidance and examples with the canonical `<SYSTEM>-<MODULE>-<NNNN>` enterprise standard.

**Architecture:** The Audit Log Contract remains the source of truth and owns the complete format, whitelist, allocation, and lifecycle rules. Audience-specific Boomi guides summarize and link to that contract, while executable Groovy and shell fixtures use the same `BOM-OD-0001` example. Runtime validation is intentionally outside scope.

**Tech Stack:** Markdown, Groovy, Bash, ripgrep, Git

---

### Task 1: Establish the canonical contract

**Files:**
- Modify: `docs/references/audit-log-contract.md:190`
- Modify: `docs/references/audit-log-contract.md:362-374`
- Modify: `docs/references/audit-log-contract.md:499-504`
- Modify: `docs/references/audit-log-contract.md:718-720`

- [ ] **Step 1: Record the legacy examples that must fail the new standard**

Run:

```bash
rg -n 'ERR_[A-Z0-9_]+|[A-Z]{2,}_ERR_[A-Z0-9_]+|BOOMI_ON_ERROR' \
  docs/references/audit-log-contract.md
```

Expected: matches include `ERR_VALIDATION`, `ORD_ERR_PARTIAL_FAILURE`, and
`ERR_SOURCE_FILE_INVALID`.

- [ ] **Step 2: Replace the field summary and success/failure guidance**

Change the `error_code` field description to require a canonical code on
failure. Replace the legacy uppercase-snake-case paragraph with:

```markdown
Use the canonical format `<SYSTEM>-<MODULE>-<NNNN>`, for example
`OMS-PD-0001`, `BOM-OD-0001`, or `365-RP-0001`.

| Segment | Allowed values | Rule |
|---|---|---|
| `SYSTEM` | `OMS`, `ART`, `BOM`, `365`, `IPP` | System that owns the error definition. |
| `MODULE` | `PD`, `OD`, `FC`, `JC`, `UR`, `PS`, `RP` | Stable business module that owns the error. |
| `NNNN` | `0001`-`9999` | Four-digit, zero-padded sequence allocated independently within the system/module namespace. |

Codes must match
`^(OMS|ART|BOM|365|IPP)-(PD|OD|FC|JC|UR|PS|RP)-\d{4}$`.
Once published, a code is immutable and must never be reused. Allocation must
be recorded in the central error-code registry to prevent duplicates. The
number does not encode severity, environment, HTTP status, or retryability.
Those remain separate structured fields or operational telemetry.
```

Retain the existing rules that success uses `null`, failure uses a non-null
code, human detail belongs in `message`, and technical exceptions belong in
SigNoz.

- [ ] **Step 3: Update contract examples**

Replace:

```text
ORD_ERR_PARTIAL_FAILURE
ERR_SOURCE_FILE_INVALID
```

with:

```text
OMS-OD-0001
BOM-OD-0001
```

Use `OMS-OD-0001` for an OMS-owned partial order result and `BOM-OD-0001` for
the Boomi-owned order/document ingestion failure.

- [ ] **Step 4: Verify the contract**

Run:

```bash
! rg -n 'ERR_[A-Z0-9_]+|[A-Z]{2,}_ERR_[A-Z0-9_]+|BOOMI_ON_ERROR' \
  docs/references/audit-log-contract.md
rg -n 'OMS-OD-0001|BOM-OD-0001|365-RP-0001' \
  docs/references/audit-log-contract.md
```

Expected: the first command succeeds with no output; the second finds the new
canonical examples.

- [ ] **Step 5: Commit the contract**

```bash
git add docs/references/audit-log-contract.md
git commit -m "docs: standardize audit error codes" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 2: Update audience-facing Boomi documentation

**Files:**
- Modify: `docs/guides/boomi-integration-guide.md:132-137`
- Modify: `docs/guides/boomi-integration-guide.md:365-395`
- Modify: `docs/guides/boomi-audit-log-owner-guide.md:192-200`
- Modify: `docs/guides/boomi-audit-log-owner-guide.md:265-278`

- [ ] **Step 1: Confirm both guides contain legacy examples**

Run:

```bash
rg -n 'ERR_SOURCE_FILE_INVALID|BOOMI_ON_ERROR' \
  docs/guides/boomi-integration-guide.md \
  docs/guides/boomi-audit-log-owner-guide.md
```

Expected: both guides contain `ERR_SOURCE_FILE_INVALID`.

- [ ] **Step 2: Update the Integration Guide**

Change the `error_code` API description to say that failure values use
`<SYSTEM>-<MODULE>-<NNNN>` and link to the Audit Log Contract's Success And
Failure section. Replace the worked failure value with:

```groovy
error_code: 'BOM-OD-0001',
```

Add one concise explanation after the example:

```markdown
`BOM-OD-0001` identifies a Boomi-owned (`BOM`) Order-module (`OD`) error.
The four-digit suffix is the stable registry number; the adjacent message
provides the human-readable reason.
```

- [ ] **Step 3: Update the Process Owner Edition**

Replace both `ERR_SOURCE_FILE_INVALID` examples with `BOM-OD-0001`. Explain
the value in plain language as "Boomi, Order module, registered error 0001"
and direct readers to copy the complete code rather than memorize it.

- [ ] **Step 4: Verify both guides**

Run:

```bash
! rg -n 'ERR_SOURCE_FILE_INVALID|BOOMI_ON_ERROR' \
  docs/guides/boomi-integration-guide.md \
  docs/guides/boomi-audit-log-owner-guide.md
rg -n 'BOM-OD-0001' \
  docs/guides/boomi-integration-guide.md \
  docs/guides/boomi-audit-log-owner-guide.md
```

Expected: no legacy examples; both guides contain the canonical example.

- [ ] **Step 5: Commit the guide updates**

```bash
git add docs/guides/boomi-integration-guide.md \
  docs/guides/boomi-audit-log-owner-guide.md
git commit -m "docs: update Boomi error code examples" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 3: Synchronize executable fixtures

**Files:**
- Modify: `scripts/write-auditlog-and-telemetry.groovy:114-169`
- Modify: `scripts/run-audit-telemetry-test.sh:210-220`

- [ ] **Step 1: Confirm fixture drift**

Run:

```bash
rg -n 'BOOMI_ON_ERROR' \
  scripts/write-auditlog-and-telemetry.groovy \
  scripts/run-audit-telemetry-test.sh
```

Expected: one match in each executable fixture.

- [ ] **Step 2: Update both fixtures**

Replace each:

```text
BOOMI_ON_ERROR
```

with:

```text
BOM-OD-0001
```

Do not add runtime validation or change success/failure behavior.

- [ ] **Step 3: Verify syntax and fixture consistency**

Run:

```bash
bash -n scripts/run-audit-telemetry-test.sh
rg -n 'BOM-OD-0001' \
  scripts/write-auditlog-and-telemetry.groovy \
  scripts/run-audit-telemetry-test.sh
```

Expected: Bash syntax passes and both files contain the new value.

- [ ] **Step 4: Commit executable fixture updates**

```bash
git add scripts/write-auditlog-and-telemetry.groovy \
  scripts/run-audit-telemetry-test.sh
git commit -m "test: align audit fixtures with error code standard" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 4: Repository-wide verification

**Files:**
- Verify: all active files outside `docs/history/`

- [ ] **Step 1: Search for stale legacy values**

Run:

```bash
if rg -n \
  --glob '!docs/history/**' \
  --glob '*.{md,groovy,sh,json,yaml,yml}' \
  'ERR_[A-Z0-9_]+|[A-Z]{2,}_ERR_[A-Z0-9_]+|BOOMI_ON_ERROR' .; then
  echo "Legacy error code found" >&2
  exit 1
fi
```

Expected: exit 0 with no matches.

- [ ] **Step 2: Validate every non-null canonical-looking sample**

Run:

```bash
rg -o \
  --glob '!docs/history/**' \
  --glob '*.{md,groovy,sh,json,yaml,yml}' \
  '(OMS|ART|BOM|365|IPP)-(PD|OD|FC|JC|UR|PS|RP)-[0-9]{4}' . \
  | sort -u
```

Expected: only approved codes such as `BOM-OD-0001`, `OMS-OD-0001`,
`OMS-PD-0001`, and `365-RP-0001`.

- [ ] **Step 3: Run whitespace and repository checks**

Run:

```bash
git diff --check
bash -n scripts/run-audit-telemetry-test.sh
git status --short
```

Expected: no whitespace errors, Bash syntax succeeds, and only the plan file
is uncommitted before the final plan commit.

- [ ] **Step 4: Commit the implementation plan**

```bash
git add docs/superpowers/plans/2026-07-16-error-code-standard.md
git commit -m "docs: add error code implementation plan" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
