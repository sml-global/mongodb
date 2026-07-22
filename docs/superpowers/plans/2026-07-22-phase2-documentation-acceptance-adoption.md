# Phase 2 Documentation, Acceptance, And Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an environment-aware documentation front door, complete operator/configuration reference, UAT acceptance evidence templates, a validated index to the foundation-owned imported-code review matrix, and a separate dev adoption gate without provisioning, destroying, verifying live readiness, or claiming deployment of either environment.

**Architecture:** Documentation is treated as a tested public interface over the frozen environment-aware scripts, foundation-owned immutable registry mappings, loader, validation, and graph, package-owned numbered declarative fragments and their exact pre-mapped canonical scope handler, verifier, and pre-destroy guard wrapper symbols, roots, and configuration contract defined by the approved unified design and landed by the implementation packages. Each package-owned numbered handler or verifier fragment defines its exact canonical wrapper functions already named by the immutable foundation mappings and delegates to package-owned, mode-safe internal functions under `scripts/lib/packages/NN-domain/internal` only after foundation validation. Foundation fragments do not define downstream wrappers; package internal function names remain distinct from canonical wrapper symbols, and no package mutates registration, mappings, or the registry graph. On a complete second-pass destroy, foundation validates the confirmation artifact and invokes the selected immutable pre-destroy guards in reverse dependency order. Every package guard is read-only and emits exactly one structured in-memory result to foundation; packages never write artifacts. Foundation validates the complete ordered result set and exclusively writes operation-bound canonical JSON evidence before approval, confirmation-artifact consumption, or handler dispatch. Foundation owns the evidence schema, path, permissions, digest, retention, access, audit, and cleanup lifecycle. A guard or ordered-result validation failure preserves the unconsumed confirmation artifact, dispatches no handler, and performs no mutation; foundation records the failed evaluation through its evidence audit lifecycle. Every dispatched destroy handler independently rechecks identity immediately before mutation. One canonical provisioning guide owns command semantics and file inventory; focused status, acceptance, migration, and adoption documents record evidence references and promotion decisions without duplicating procedures. A Python static-contract suite defines future validation of links, inventories, status language, command forms, safe examples, evidence sentinels, and the destroy guard result and evidence lifecycle. Documentation tests, link checks, scripts, and every AWS, Terraform, Kubernetes, database, provision, destroy, verify, smoke, acceptance, or adoption command run only when that execution class is separately authorized; none run while implementing this plan.

**Tech Stack:** Markdown, Bash command examples, Python 3 `unittest`, `pathlib`, `re`, `json`, Terraform and Kustomize static checks

---

## Approved Inputs And Execution Boundary

Implement this plan only after the foundation, EKS, data, and Boomi work
packages have landed the foundation-owned immutable registry mappings, loader,
validation, and graph; each package-owned numbered declarative fragment with
its exact pre-mapped canonical scope handler, verifier, and pre-destroy guard
wrapper functions; package-owned mode-safe internal libraries; Terraform roots;
overlays; generated-path contracts; and command grammar. All must be frozen. The
foundation-owned registry graph, including its exact scope catalog,
dependencies, provision order, and reverse destroy order, must also be frozen.
This is a hard prerequisite: documentation must consume those landed
interfaces exactly and must not speculate about names or flags. Reconcile
exact names against:

- `docs/superpowers/specs/2026-07-22-unified-environment-provisioning-design.md`
- `docs/superpowers/specs/2026-07-21-uat-platform-consolidation-design.md`
- `docs/superpowers/specs/2026-07-21-uat-workforce-access-design.md`
- `docs/superpowers/plans/2026-07-21-uat-access-foundation.md`
- the merged implementation plans for Phase 2 work packages 1 through 5

If any declarative schema fragment, immutable wrapper mapping, package-owned
mode-safe internal library, graph entry, schema key, root, overlay, generated
path, scope, verification mode, or command form is not frozen and landed, stop
and return that issue to the owning implementation package. Do not use
placeholder grammar in shared docs, infer a readiness-only interface, or
document an implementation-private handler as a public command.
Package-owned internal libraries live only under
`scripts/lib/packages/NN-domain/internal` and use function names distinct from
canonical wrapper symbols. Each package-owned numbered handler or verifier
fragment defines the exact canonical scope handler, verifier, and read-only
pre-destroy guard wrapper functions already named by the immutable foundation
mappings, and each wrapper delegates to the package's distinct internal
function only after foundation validation. Each guard emits exactly one
structured in-memory result conforming to the foundation-owned result schema
and performs no file or artifact I/O. Foundation owns the immutable registry
mappings, loader, validation, graph, ordered-result validation, canonical JSON
serialization, and the complete evidence audit lifecycle; foundation fragments
do not define downstream wrappers. Packages never write artifacts. This
package must not document or introduce
package registration APIs, runtime registration, mapping mutation, additional
guard slots, public guard commands, or registry-graph edits.

This is a documentation and static-validation work package. It must not:

- run `scripts/provision.sh`, `scripts/destroy.sh`, or a compatibility
  provisioning script;
- run `terraform init`, `terraform plan`, `terraform apply`, `terraform
  destroy`, `terraform import`, `terraform state mv`, or `terraform state rm`;
- access AWS, Kubernetes, MongoDB, PostgreSQL, SigNoz, Boomi Platform, or IAM
  Identity Center;
- create `.local/dev/` or `.local/uat/` execution evidence;
- change a promotion gate from disabled to enabled;
- claim that UAT or dev has been deployed, verified, destroyed, rebuilt,
  adopted, or promoted.

No command in this plan is authorized by its inclusion here. Documentation
tests, link checks, syntax checks, format checks, render checks, repository
scripts, and Git checks run only after their execution class receives separate
authorization. A static, offline, read-only, readiness, or dry-run label does
not authorize execution.
Commands under **Authorized UAT acceptance command** or **Authorized dev
adoption command** headings are template content only. UAT acceptance remains
`NOT_EXECUTED`; a separate future execution plan must define and authorize the
live lifecycle run.

## Status Vocabulary

Use these exact values everywhere status is recorded:

| Value | Meaning |
|---|---|
| `IMPLEMENTED_STATICALLY` | Code and offline checks exist; no runtime claim is made. |
| `MODELED_READ_ONLY` | Configuration can be validated and compared, but mutation is blocked. |
| `AUTHORIZED_EXECUTION_REQUIRED` | The command can mutate or inspect a live environment and requires a separately recorded authorization. |
| `NOT_EXECUTED` | No acceptance execution has been recorded in the artifact. |
| `EVIDENCE_RECORDED` | Immutable evidence references and reviewer decision have been recorded. |
| `PROMOTION_BLOCKED` | The environment cannot use unified mutation commands. |
| `PROMOTION_APPROVED` | Named approvers accepted all gates and enabled mutation through a separate reviewed code change. |

Templates start with `NOT_EXECUTED` or `PROMOTION_BLOCKED`. A documentation
change alone can never set `EVIDENCE_RECORDED` or `PROMOTION_APPROVED`.

## File Structure

| File | Responsibility |
|---|---|
| `README.md` | Environment-aware public front door, capability/status summary, truthful quick starts, and canonical links. |
| `docs/guides/environment-provisioning.md` | Canonical explanation of every public script, Terraform root, base/overlay, configuration class, generated artifact, dependency, full flow, and narrow flow. |
| `docs/guides/environment-setup.md` | Workstation prerequisites, explicit environment selection, local-input setup, and read-only readiness checks. |
| `docs/guides/operator-runbook.md` | Authorized operational procedure, plan review, approval, independent component workflows, and stop conditions. |
| `docs/references/verification-commands.md` | Offline checks, authorized runtime checks, expected evidence, and environment/component verification boundaries. |
| `docs/references/recovery-procedures.md` | Environment-qualified recovery, independent database restore/destroy, retained controls, and rebuild guidance. |
| `docs/operations/environment-capability-matrix.md` | Current dev/UAT capability, implementation, authorization, acceptance, and promotion state by scope. |
| `docs/operations/imported-code-review-matrix.md` | Existing foundation-created canonical seven-column source-to-target decision matrix, appended by implementation packages and validated/indexed by this final package through the foundation validator. |
| `docs/operations/legacy-command-state-mapping.md` | Legacy command, state, Terraform address, Kubernetes resource, local artifact, and unified destination mapping. |
| `docs/operations/uat-acceptance/README.md` | Acceptance order, authorization rule, evidence storage contract, and completion gate. |
| `docs/operations/uat-acceptance/provision.md` | UAT provision authorization and evidence template. |
| `docs/operations/uat-acceptance/no-drift.md` | UAT post-provision no-drift evidence template. |
| `docs/operations/uat-acceptance/destroy.md` | UAT reverse-order destroy and retention evidence template. |
| `docs/operations/uat-acceptance/rebuild.md` | UAT documented-command rebuild and final smoke evidence template. |
| `docs/operations/dev-adoption/README.md` | Separate dev adoption process and prohibition on implementation-time mutation. |
| `docs/operations/dev-adoption/resource-state-inventory.md` | Existing dev resources and state-object disposition artifact. |
| `docs/operations/dev-adoption/state-move-import-plan.md` | Peer-reviewed imports, moves, backups, rollback, and dry-run evidence artifact. |
| `docs/operations/dev-adoption/postgresql-topology-decision.md` | Evidence-based mapping of legacy `pg` state to core or brand and creation/adoption plan for the second cluster. |
| `docs/operations/dev-adoption/promotion-gate.md` | No-unintended-change checks, approvals, and explicit promotion decision. |
| `config/environments/dev.env` | Committed, validated dev environment configuration documented directly. |
| `config/environments/uat.env` | Committed, validated UAT environment configuration documented directly. |
| `config/environments/dev.local/*.json.example` | Exact safe shapes for dev local workforce, database, Boomi, and SigNoz inputs. |
| `config/environments/uat.local/*.json.example` | Exact safe shapes for UAT local workforce, database, Boomi, and SigNoz inputs. |
| `platform-prerequisites/terraform/README.md` | Terraform root, module, dependency, input, output, backend, and state-key inventory. |
| `docs/index.md` | Canonical navigation to the unified guide, status, design, plan, acceptance, migration, and adoption documents. |
| `tests/documentation/__init__.py` | Python test package marker. |
| `tests/documentation/test_documentation_contract.py` | Links, commands, status, inventory, example, evidence, and promotion static contracts. |

## Documentation Ownership Rules

1. This work package exclusively owns all edits to the shared documentation
  surfaces: `README.md`, `platform-prerequisites/terraform/README.md`,
  `docs/index.md`, `docs/guides/environment-setup.md`,
  `docs/guides/operator-runbook.md`,
  `docs/references/verification-commands.md`, and
  `docs/references/recovery-procedures.md`. Earlier implementation plans add
  only focused component references and append their reviewed rows to the
  foundation-created canonical matrix; they must not edit these shared files.
2. `docs/guides/environment-provisioning.md` owns public scope semantics,
   dependency order, file explanations, configuration flow, and quick starts.
3. `docs/operations/environment-capability-matrix.md` owns current capability
   and promotion status. Other files link to it instead of copying status.
4. `platform-prerequisites/terraform/README.md` owns detailed Terraform root and
   state inventory; the provisioning guide summarizes and links to it.
5. `docs/references/verification-commands.md` owns check commands and expected
   evidence; acceptance templates reference named sections.
6. `docs/references/recovery-procedures.md` owns recovery procedures; the
   runbook links to them rather than duplicating destructive commands.
7. `docs/operations/imported-code-review-matrix.md` is created by the
  foundation and appended in place by each implementation package. Its only
  schema is exactly `ID | Domain | Source | Target | Disposition | Evidence |
  Status`. This final package invokes
  `scripts/validate-imported-code-review-matrix.py` and adds navigation to the
  existing file; it never recreates the matrix, copies rows into another file,
  changes the schema, or maintains a competing validator or matrix.
8. `docs/operations/legacy-command-state-mapping.md` owns compatibility and
   destination mappings. Dev adoption artifacts reference mapping row IDs.
9. UAT acceptance and dev adoption artifacts record evidence references and
   decisions, never secrets, raw Terraform plans, generated variable files,
   role ARN inputs, database credentials, or tokens.
10. Foundation exclusively owns the pre-destroy guard evidence API and
  artifact lifecycle. Package guards are read-only producers of exactly one
  structured in-memory result per invocation. Documentation and acceptance
  templates may record the ordered result, canonical JSON evidence path,
  digest, and review decision, but must never assign artifact creation,
  serialization, append/update, permissions, retention, access auditing,
  consumption, or cleanup to a package.

### Task 1: Establish The Documentation Static Contract

**Files:**
- Create: `tests/documentation/__init__.py`
- Create: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Write the initial failing inventory and truthfulness tests**

Create a `unittest.TestCase` named `DocumentationContractTests` with
`REPO_ROOT`, a Markdown-link extractor, a heading slug helper, and methods with
these exact names:

```text
test_required_documentation_files_exist
test_relative_markdown_links_resolve
test_readme_uses_environment_aware_front_door
test_capability_matrix_uses_closed_status_vocabulary
test_every_public_script_is_inventoried
test_every_terraform_root_is_inventoried
test_every_kustomize_base_and_overlay_is_inventoried
test_safe_examples_are_non_secret_and_non_runnable
test_uat_acceptance_templates_start_not_executed
test_dev_promotion_starts_blocked
test_imported_code_rows_have_closed_decisions
test_legacy_mapping_has_no_unclassified_rows
test_mutating_commands_are_under_authorization_headings
test_docs_make_no_unsubstantiated_deployment_claims
test_destroy_guard_result_and_evidence_lifecycle_is_foundation_owned
```

Each method uses a concrete per-file context such as
`self.subTest(path=path.relative_to(REPO_ROOT).as_posix())` and
`self.assertEqual`, `self.assertIn`, `self.assertNotRegex`, or
`self.assertFalse` with a message naming the missing path, row, status, or
unsafe command. The exact assertions for inventories, statuses, commands,
examples, templates, mappings, and claims are defined in this task and the
task that introduces each artifact.

Implement file discovery from the repository rather than copying an inventory
into the test:

```python
public_scripts = sorted(
    path.relative_to(REPO_ROOT).as_posix()
    for path in (REPO_ROOT / "scripts").glob("*.sh")
)
terraform_roots = sorted(
    path.parent.relative_to(REPO_ROOT).as_posix()
    for path in (REPO_ROOT / "platform-prerequisites/terraform").glob("*/versions.tf")
)
kustomizations = sorted(
    path.parent.relative_to(REPO_ROOT).as_posix()
    for root in ("k8s", "gitops", "policies")
    for path in (REPO_ROOT / root).glob("**/kustomization.yaml")
)
```

Require the canonical guide to contain each discovered path in backticks.
Require evidence templates to contain `Status: NOT_EXECUTED`, and require
`docs/operations/dev-adoption/promotion-gate.md` to contain
`Decision: PROMOTION_BLOCKED` and `Unified dev mutation enabled: false`.

For the imported-code assertion, invoke the foundation validator against
`docs/operations/imported-code-review-matrix.md`; do not implement a second
Markdown parser or duplicate its schema rules in the documentation suite.
Assert the acceptance index and docs index link the canonical matrix path.

For the destroy-guard assertion, require every package guard to be documented
as read-only and to emit exactly one structured in-memory result with no
artifact I/O. Require foundation to validate the complete reverse-dependency-
ordered result set and exclusively write operation-bound canonical JSON before
approval, confirmation-artifact consumption, or handler dispatch. Require
foundation ownership of evidence schema, path, permissions, digest, retention,
access, audit, and cleanup. Reject any documentation assigning artifact writes
or evidence lifecycle operations to a package. Require failure to preserve the
unconsumed confirmation artifact and dispatch no handler while foundation
records the failed evaluation in its evidence audit lifecycle.

For truthfulness, reject unqualified present-tense claims matching
`(dev|uat).*(is deployed|has been deployed|is verified|passed acceptance|was
rebuilt|is promoted)` outside `docs/history/` and evidence files whose status
is `EVIDENCE_RECORDED`. Reject `--env dev` provision/destroy examples outside
an **Authorized dev adoption command** block while promotion is blocked.

- [ ] **Step 2: When execution is separately authorized, run the test to verify the documentation contract is absent**

Run:

```bash
python3 -m unittest tests.documentation.test_documentation_contract -v
```

Expected: FAIL on missing canonical guide, matrices, examples, acceptance
templates, and adoption artifacts. The test itself must import successfully.

- [ ] **Step 3: When execution and commit are separately authorized, commit the failing contract**

```bash
git add tests/documentation
git commit -m "test: define Phase 2 documentation contract"
```

### Task 2: Publish The Capability Matrix And Environment-Aware Front Door

**Files:**
- Create: `docs/operations/environment-capability-matrix.md`
- Modify: `README.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Define the matrix schema and initial status**

Read the exact provision scope catalog from the landed foundation registry and
assert, without adding aliases or a documentation-only scope, that it is
exactly:

```text
backend, eks-platform, access-governance, eks-access,
platform-controllers, boomi-runtime, mongodb, postgresql-core,
postgresql-brand, mongodb-access, database-access-core,
database-access-brand, workload-identity, signoz,
signoz-observability, all
```

`verification` is a verification mode, not a provision/destroy scope, and
must not appear as a scope row. `postgresql-core` and `postgresql-brand` are
distinct scopes, roots, states, credentials, endpoints, plans, locks, backup
paths, and failure domains throughout the documentation.

The public verification entrypoint is exactly:

```text
bash scripts/verify-platform-health.sh --env <dev|uat> [mode]
```

The exact accepted public forms are `--preflight`, `--full`, no mode flag, and
`--smoke-test`. No mode flag is exactly equivalent to `--full`; both are public
full-verification forms. Documentation must not pass a provision scope to the
verifier, invent a `verification` scope, add a readiness alias, or expose a
private scope-verifier function as a public command.

Use columns:

```text
Scope | Dev capability | Dev mutation | UAT capability | UAT mutation |
Runtime acceptance | Promotion dependency | Evidence link
```

Set dev capability to `MODELED_READ_ONLY` for unified paths, dev mutation to
`PROMOTION_BLOCKED`, UAT mutation to `AUTHORIZED_EXECUTION_REQUIRED`, and UAT
runtime acceptance to `NOT_EXECUTED`. Where an implementation package has not
landed, use `PROMOTION_BLOCKED` and state the exact missing work package in the
promotion-dependency column. Do not use prose synonyms for status values.

Add a boundary table that states:

- repository managed: the canonical scope catalog;
- externally owned prerequisite: Identity Center permission sets, groups,
  memberships, and assignments;
- externally owned authorization: Boomi Platform roles and permissions;
- separately approved and excluded from `all`: cross-account S3 application
  access;
- retained during ordinary destroy: backend, Access Analyzer, CloudTrail
  baseline, and mandatory governance alerts.

- [ ] **Step 2: Rewrite the root README as the environment-aware front door**

Use this section order:

```text
Purpose
Current Environment Status
Choose An Operator Path
Complete Environment Boundary
Quick Start
Narrow Scopes
Independent PostgreSQL Clusters
Safety And Authorization
Documentation Map
Historical Compatibility
```

The README must:

- say this repository is the single provisioning project for complete OMS dev
  and UAT after each environment passes its promotion gate;
- link current status rather than claim deployment;
- define `all` as the full repository-managed dependency graph;
- show `bash scripts/provision.sh --env uat all` only in a block beginning
  `AUTHORIZED UAT ACCEPTANCE COMMAND - DO NOT RUN WITHOUT RECORDED APPROVAL`;
- show the dev read-only path exactly as
  `bash scripts/verify-platform-health.sh --env dev --preflight`; do not
  document any provisioning command or readiness-only alias as a verification
  interface;
- list every canonical narrow scope;
- show `postgresql-core` and `postgresql-brand` as independent states and
  failure domains;
- link setup, provisioning, runbook, verification, recovery, capability,
  acceptance, migration, and adoption documents;
- move detailed Boomi/SigNoz instructional material to existing focused guides
  and retain only concise links;
- label no-`--env`, `pg`, `mongo`, and `provision-uat-access.sh` paths as legacy
  compatibility, never as the recommended interface.

- [ ] **Step 3: Extend tests for exact scope and status coverage**

Parse the first column of the capability table and assert it equals the closed
scope set above. Assert the README contains `--env uat`, the read-only dev
command, both PostgreSQL scopes, and a link to the status matrix. Assert it no
longer recommends the legacy four-command dev sequence as the current unified
full-environment quick start.

- [ ] **Step 4: When execution and commit are separately authorized, run focused tests and commit**

```bash
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_readme_uses_environment_aware_front_door \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_capability_matrix_uses_closed_status_vocabulary \
  -v
git add README.md docs/operations/environment-capability-matrix.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: add environment-aware front door"
```

Expected: both focused tests PASS.

### Task 3: Document Committed Configuration, Add Safe Local Examples, And Write The Canonical Provisioning Guide

**Files:**
- Create: `config/environments/dev.local/workforce-principals.json.example`
- Create: `config/environments/dev.local/database-secrets.json.example`
- Create: `config/environments/dev.local/boomi-runtime.json.example`
- Create: `config/environments/dev.local/signoz-bootstrap.json.example`
- Create: `config/environments/uat.local/workforce-principals.json.example`
- Create: `config/environments/uat.local/database-secrets.json.example`
- Create: `config/environments/uat.local/boomi-runtime.json.example`
- Create: `config/environments/uat.local/signoz-bootstrap.json.example`
- Create: `docs/guides/environment-provisioning.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Document the committed validated environment configurations directly**

Inventory `config/environments/dev.env` and `config/environments/uat.env`
directly in the canonical guide as the checked-in, non-secret, validated
environment configuration contract. Confirm the committed files use the closed
key set from the merged environment-schema implementation and preserve key
order and comments by category:

```text
identity and promotion
AWS and backend
network and EKS
namespaces and names
node groups and storage
MongoDB
PostgreSQL core
PostgreSQL brand
Boomi runtime
SigNoz and observability
backup, retention, and deletion protection
tags and feature gates
```

Document the actual validated dev and UAT values without duplicating either
file into an example contract. The committed files contain no secret value;
operator-local role ARNs, endpoints, tokens, passwords, connection material,
and secret references remain in protected local JSON inputs. Tests validate
the committed files against the landed schema instead of expecting intentionally
invalid account or promotion sentinels.

- [ ] **Step 2: Create exact local-input shapes**

Use JSON objects with the exact merged validator keys. Safe values are explicit
sentinels such as:

```json
{
  "secret_reference": "NOT_A_SECRET_REFERENCE",
  "operator_action": "REPLACE_USING_AUTHORIZED_LOCAL_INPUT_PROCEDURE"
}
```

The workforce example contains every approved role key with value
`NOT_AN_AWS_ROLE_ARN`. The database example contains separate `core`, `brand`,
and `mongodb` objects so credentials cannot be shared accidentally. The Boomi
example contains `installation_token: NOT_A_BOOMI_TOKEN`. The SigNoz example
contains `api_token: NOT_A_SIGNOZ_TOKEN`. Add a top-level
`example_only: true` key only if the merged validators explicitly allow it;
otherwise explain example-only status in adjacent README text and keep exact
validator keys.

- [ ] **Step 3: Write the canonical guide with a complete generated inventory**

Use this section order:

```text
Purpose And Current Status
Environment Selection Contract
Complete Scope Catalog
Dependency And Destruction Order
Script Inventory
Terraform Root And State Inventory
Kubernetes, GitOps, And Policy Inventory
Committed Configuration
Operator-Local Configuration
Generated Files And Cleanup
Full Quick Starts
Narrow Quick Starts
Independent PostgreSQL Workflows
Plan Review And Approval
Verification And Evidence
Destroy And Recovery
Adding A Component
Adding An Environment
Legacy Compatibility
External Ownership Boundary
```

For every top-level `scripts/*.sh`, document:

```text
Path | Public or internal | Reads | Writes/mutates | Why it exists |
Environment behavior | Safe invocation | Replacement/deprecation status
```

For each Terraform root, document root path, owning scope, dependencies, state
key for dev and UAT, non-secret inputs, outputs, generated files, lock/plan
paths, and why it has separate state. List reusable modules separately and
mark them non-runnable.

For every discovered `kustomization.yaml`, explain whether it is a base or
environment overlay, its owner scope, selected namespaces/labels, and why the
base/overlay split exists. Also inventory non-Kustomize configuration and
generated classes:

```text
config/environments/dev.env
config/environments/uat.env
config/environments/dev.local/
config/environments/uat.local/
.local/dev/generated/
.local/dev/plans/
.local/dev/locks/
.local/dev/logs/
.local/dev/evidence/
.local/uat/generated/
.local/uat/plans/
.local/uat/locks/
.local/uat/logs/
.local/uat/evidence/
```

State what creates each generated class, its expected mode, cleanup owner, and
whether it may be committed. Secret inputs, generated tfvars, plans, locks,
logs, and runtime evidence must all be marked `NEVER COMMIT`.

- [ ] **Step 4: Add full and narrow quick starts without deployment claims**

Document three distinct command classes, all of which remain unauthorized
until their execution class is separately approved:

1. Offline static commands and public `--preflight` verification, runnable
  only when their exact execution class is separately authorized.
2. Authorized UAT acceptance commands, requiring authorization record,
   account/context confirmation, plan review, and evidence directory.
3. Authorized dev adoption commands, unavailable until promotion approval.

The full UAT flow uses the merged implementation's exact command shape:

```bash
bash scripts/provision.sh --env uat all
bash scripts/verify-platform-health.sh --env uat --smoke-test
```

Place it only under the exact authorization banner from Task 2. The
provision/destroy narrow examples cover every canonical scope. Verification
examples use only `--preflight`, `--full`, no mode flag, or `--smoke-test` and
never accept a scope argument. State that no mode flag is exactly equivalent to
`--full`. Do not append `--auto-approve` to a quick start; explain that
automation flags never bypass identity, context, plan, dependency, retention,
evidence, or separate execution-authorization gates.

- [ ] **Step 5: Document independent dual-PostgreSQL operations**

Give separate subsections for `postgresql-core` and `postgresql-brand`, each
with its own:

- provision and plan-review command;
- verification command and `cluster_role` expectation;
- database-access command;
- backup evidence and restore procedure link;
- destroy preconditions and the repeatable foundation-owned
  two-pass contract. The first invocation omits
  `--confirmation-artifact` and may omit or provide an incomplete repeated
  confirmation set. It must print the repository-relative path of a newly
  created mode-`0600` operation artifact plus the exact arguments required for
  the second invocation, exit nonzero, and perform no mutation. The second
  invocation must repeat the command with
  `--confirmation-artifact <repository-relative-path-printed-by-first-invocation>`
  and the complete repeated
  `--confirm <exact-value> [--confirm <exact-value> ...]` set. Every selected
  persistent scope requires its exact typed value
  `destroy:<env>:<account>:<scope>:<resource>:<consequence>` from that
  operation artifact;
- state key, plan path, lock path, secret-reference class, endpoint class,
  security group, parameter group, and final-snapshot name;
- negative statement that the other root/state is not initialized or changed.

Add a paired narrow-flow example that runs core and brand sequentially for
operator clarity but explicitly says neither command requires the other. Do
not show a shared credential, endpoint, grant, snapshot, state, or lock.
The package documents the foundation-defined confirmation grammar and the
required persistent component represented by each value. For `all`, require
the union of values for all selected persistent scopes, supplied through
repeated `--confirm` flags on the second invocation. Every concrete narrow or
`all` second-pass example and every corresponding test must include
`--confirmation-artifact <repository-relative-path-printed-by-first-invocation>`.
The foundation owns artifact creation and guarantees that each artifact is
operation-bound through foundation-owned expiry, single-use, replay, and
tamper checks, and validates the complete repeated confirmation set. After
artifact validation, foundation invokes the selected immutable read-only
pre-destroy guard wrappers in reverse dependency order. Each wrapper is defined
by its package-owned numbered verifier fragment at the exact canonical symbol
already named by the immutable foundation mapping and delegates to a distinct
package internal function. Each guard emits exactly one structured in-memory
result and never writes an artifact. Foundation validates the complete ordered
result set and exclusively writes operation-bound canonical JSON guard evidence
before approval, confirmation-artifact consumption, or destroy-handler
dispatch. Foundation owns the evidence schema, path, permissions, digest,
retention, access, audit, and cleanup lifecycle. Approval, confirmation-
artifact consumption, and destroy-handler dispatch occur only after every
ordered result validates and every guard passes.
A guard or result-validation failure exits nonzero, preserves the confirmation
artifact as unconsumed, dispatches no handler, and performs no mutation;
foundation records the failed evaluation through its owned evidence audit
lifecycle. Each dispatched destroy handler rechecks the selected
environment and caller identity immediately before its first mutation.
Packages never parse confirmation artifacts or confirmation values, write
evidence artifacts, mutate guard registration or mappings, or change the
public destroy interface. Every concrete UAT
`destroy all` example and test union represents all five foundation-required
persistent-scope values as follows:

```bash
bash scripts/destroy.sh --env uat all \
  --confirmation-artifact <repository-relative-path-printed-by-first-invocation> \
  --confirm destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster \
  --confirm destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs \
  --confirm destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs \
  --confirm destroy:uat:672172129937:postgresql-core:db/oms-uat-core:final-snapshot=<foundation-generated-id-from-artifact> \
  --confirm destroy:uat:672172129937:postgresql-brand:db/oms-uat-brand:final-snapshot=<foundation-generated-id-from-artifact>
```

This is a documentation template, not an actual operation: the artifact path
and angle-bracketed snapshot values must be copied exactly from the first
invocation's output. No hard-coded operation-generated artifact path, snapshot
identifier, or other operation ID may be presented as an actual value. The
resource identities and PostgreSQL final-snapshot identifiers for an actual
operation derive from the validated UAT configuration, platform contracts,
and operation artifact.
Backend and retained governance controls require no ordinary `destroy all`
confirmation and remain excluded from the union.

- [ ] **Step 6: When execution and commit are separately authorized, run focused tests and commit**

```bash
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_every_public_script_is_inventoried \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_every_terraform_root_is_inventoried \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_every_kustomize_base_and_overlay_is_inventoried \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_safe_examples_are_non_secret_and_non_runnable \
  -v
git add config/environments docs/guides/environment-provisioning.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: add canonical environment provisioning guide"
```

Expected: all four focused tests PASS.

### Task 4: Update Terraform Navigation And Operator Setup

**Files:**
- Modify: `platform-prerequisites/terraform/README.md`
- Modify: `docs/guides/environment-setup.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Replace the dev-only Terraform overview**

Use this section order:

```text
Purpose
Use Repository Entrypoints
Root Inventory
Reusable Module Inventory
Environment Input Inventory
State And Lock Contract
Platform Output Contract
Dependency Graph
Generated Inputs And Plans
Legacy Dev State
Static Validation
Canonical Documentation
```

The root table must include every discovered root with both state keys and
must distinguish the independent `postgresql-core` and `postgresql-brand`
states. Explain that backend selection is passed by the orchestrator, provider
`allowed_account_ids` is mandatory, workspaces are prohibited, reusable
modules are not runnable roots, and direct Terraform apply/destroy is not an
operator interface.

Document `oms/dev/pg.tfstate` as a frozen legacy compatibility state whose
future core-or-brand destination is decided only by recorded evidence. Never
show it as owning both new PostgreSQL clusters.

- [ ] **Step 2: Make setup environment-aware**

Replace dev-only setup assumptions with:

- required tools by offline, UAT-authorized, and optional integration use;
- explicit AWS profiles for dev and UAT without treating profile names as
  environment selection;
- exact `--env` requirement and no-default rule;
- account and Region expectations sourced from committed validated config;
- protected local directory/file modes (`0700`/`0600`), symlink rejection,
  and example-to-local copy flow;
- immutable account and workforce-prefix validation;
- dev read-only preflight through
  `bash scripts/verify-platform-health.sh --env dev --preflight` and blocked
  mutation;
- UAT authorization prerequisite and no Identity Center API ownership;
- separate kubeconfig/context verification for each environment;
- links to the canonical provisioning guide instead of copied scope details.

Keep commands that call STS, EKS, or Kubernetes under clearly labeled
authorized headings that also state whether behavior is read-only. A
read-only heading alone is insufficient authorization. Do not claim successful
output from either environment.

- [ ] **Step 3: Add root/state and setup assertions**

Assert every Terraform root appears in the Terraform README, both PostgreSQL
state keys are different, the legacy state is labeled frozen, and setup states
that environment is never inferred from profile, context, directory,
workspace, namespace, or resource name.

- [ ] **Step 4: When execution and commit are separately authorized, validate and commit**

```bash
python3 -m unittest tests.documentation.test_documentation_contract -v
git diff --check
git add platform-prerequisites/terraform/README.md \
  docs/guides/environment-setup.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: document environment setup and Terraform roots"
```

Expected: documentation tests PASS at the current implementation stage and
`git diff --check` exits 0.

### Task 5: Rewrite Runbook, Verification, And Recovery Contracts

**Files:**
- Modify: `docs/guides/operator-runbook.md`
- Modify: `docs/references/verification-commands.md`
- Modify: `docs/references/recovery-procedures.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Restructure the operator runbook around explicit environments**

Use this section order:

```text
Authorization And Stop Conditions
Offline Static Checks
Select Environment And Scope
Review Committed And Local Inputs
Review Dependency Preconditions
Create And Review Saved Plans
Approve And Apply
Run Preflight Verification
Run Full Or Smoke Verification
Independent PostgreSQL Procedures
Partial Failure And Resume
Destroy Authorization
Evidence Handling
Legacy Compatibility
```

State near the section opening that the exact accepted public verification
forms are
`bash scripts/verify-platform-health.sh --env <dev|uat> --preflight`,
`bash scripts/verify-platform-health.sh --env <dev|uat> --full`,
`bash scripts/verify-platform-health.sh --env <dev|uat>`, and
`bash scripts/verify-platform-health.sh --env <dev|uat> --smoke-test`.
No mode flag is exactly equivalent to `--full`; both are public full-verification
forms.
Verification has no public scope argument; component-specific checks are
selected by immutable foundation-mapped verifier wrapper symbols. Each
package-owned numbered verifier fragment defines its exact canonical verifier
and read-only pre-destroy guard wrapper functions already named by those
immutable mappings. Each wrapper may source its package-owned mode-safe
internal library under `scripts/lib/packages/NN-domain/internal` only after
foundation validation and delegates to a distinct internal function.
Foundation owns the immutable registry mappings, loader, validation, and graph;
foundation fragments do not define downstream wrappers, and packages do not
mutate registration, mappings, or the graph. Every guard is read-only, emits
exactly one structured in-memory result to foundation, and writes no artifact.
Foundation validates the reverse-dependency-ordered result set and exclusively
writes operation-bound canonical JSON evidence before approval, confirmation-
artifact consumption, or dispatch. These guards and their foundation-owned
evidence API are lifecycle internals, not additional public verifier modes,
scope arguments, or destroy flags.

For each mutating procedure, require these recorded facts before the command:

```text
authorization reference
environment
expected account and Region
resolved caller account
canonical EKS ARN when Kubernetes is involved
scope
saved-plan digest and summary when Terraform is involved
retention decision when persistent data is involved
evidence directory
operator and reviewer
```

Remove current quick starts that imply no-`--env` dev mutation is the unified
path. Keep a compatibility section linking each legacy command to its mapping
row and frozen approval process.

- [ ] **Step 2: Split static and authorized verification**

Structure `verification-commands.md` as:

```text
Evidence Rules
Offline Static Verification
Authorized Environment Preflight Verification
Authorized UAT Component Verification
Authorized UAT Full Smoke Verification
No-Drift Verification
Independent PostgreSQL Verification
Negative Cross-Cluster Verification
Audit And Observability Verification
Acceptance Evidence Crosswalk
Dev Promotion Verification
```

Every live command states required authorization, mutation/read-only behavior,
expected identity, generated evidence path, and exact success criteria. Static
commands include only syntax, unit tests, Terraform format/validate without a
backend, Kustomize render checks, JSON parsing, documentation tests, and
`git diff --check`.

All public verification examples conform to the foundation grammar: explicit
`--env` first, followed by `--preflight`, `--full`, no mode flag, or
`--smoke-test`. No mode flag is exactly equivalent to `--full`. A
component-verification section explains the evidence emitted by immutable
foundation-mapped verifier wrappers during full or smoke verification; it does
not append a component scope, add another accepted form, expose an internal
library, or introduce another public verifier.

No-drift success is exactly: every Terraform root reports `0 to add, 0 to
change, 0 to destroy`; Kubernetes rendered and live inventories have no
unexplained difference; generated plans and evidence are environment-qualified;
and each exception has an owner, explanation, and approval. Do not reduce
no-drift to a single aggregate Terraform result.

The PostgreSQL section must prove core/brand identifier, endpoint, secret,
security-group, parameter-group, state, plan, lock, snapshot, audit
`cluster_role`, and monitoring filter separation. Include negative
connectivity/authentication checks proving brand credentials and paths cannot
reach core, and vice versa where the approved authorization matrix requires
isolation.

- [ ] **Step 3: Make recovery environment- and component-qualified**

Add separate recovery decision trees for:

- orchestration lock or interrupted plan/apply;
- wrong account/context rejection before mutation;
- Terraform state backup and restore by environment/root;
- partial `all` completion and safe resume;
- MongoDB workload, storage, PBM backup, and prerequisite recovery;
- independent core PostgreSQL backup, point-in-time restore, final snapshot,
  and destroy recovery;
- independent brand PostgreSQL backup, point-in-time restore, final snapshot,
  and destroy recovery;
- Boomi runtime drain, token rotation, EFS, and PDB recovery;
- SigNoz platform versus observability API recovery;
- retained governance controls and backend break-glass boundary;
- full UAT destroy/rebuild acceptance.

Every destructive path requires environment, account, resource, retention
consequence, and typed confirmation through the exact two-pass destroy flow.
The first invocation, without `--confirmation-artifact` and without a complete
confirmation set, creates a mode-`0600` operation artifact, prints its
repository-relative path and the exact second-invocation arguments, exits
nonzero, and performs no mutation. The second invocation requires
`--confirmation-artifact <repository-relative-path>` plus the complete
repeated `--confirm <exact-value>` set using the exact value grammar
`destroy:<env>:<account>:<scope>:<resource>:<consequence>`. For `all`, require
the union of exact values for all selected persistent scopes. The foundation
guarantees that the artifact is operation-bound and owns its expiry,
single-use, replay, and tamper validation plus confirmation validation;
packages never parse artifacts or confirmation values. After artifact
validation and before approval, artifact consumption, or handler dispatch,
foundation invokes the immutable selected-scope pre-destroy guard wrappers in
reverse dependency order. Each package-owned numbered verifier fragment defines
its exact canonical guard wrapper already named by the immutable foundation
mapping and delegates to a distinct package internal function. Every guard is
read-only, emits exactly one structured in-memory result, and performs no
artifact I/O. Foundation validates the complete ordered result set and
exclusively writes operation-bound canonical JSON evidence before approval,
confirmation-artifact consumption, or handler dispatch. Foundation owns the
evidence schema, path, permissions, digest, retention, access, audit, and
cleanup lifecycle. Any guard or result-validation failure exits nonzero,
leaves the confirmation artifact unconsumed, dispatches no destroy handler,
and performs no mutation; foundation records the failed evaluation through
the same owned evidence audit lifecycle. After dispatch, each destroy handler must recheck the
selected environment and caller identity immediately before mutation; an
identity mismatch fails without that handler mutating. State that
authorization for one PostgreSQL cluster never authorizes the other. Ordinary
`destroy all` must retain backend and mandatory governance controls.

- [ ] **Step 4: Test authorization headings and truthful language**

Extend tests to scan fenced Bash blocks. A block containing `provision.sh`,
`destroy.sh`, `verify-platform-health.sh`, `terraform plan` with a backend, or live
`kubectl` mutation must have the nearest preceding heading contain
`Authorized`, except commands explicitly tagged as legacy examples inside the
compatibility section. Reject language claiming expected live success unless
the text says it is an acceptance criterion rather than recorded evidence.
Also reject any explicit verifier form outside the four accepted foundation
forms (`--preflight`, `--full`, no mode flag, and `--smoke-test`), any claim
that no mode flag differs from `--full`, or any form with a trailing scope
argument. Reject a persistent destroy flow unless its first invocation omits
`--confirmation-artifact`, is documented to print a mode-`0600`
repository-relative operation-artifact path and exact second-invocation
arguments, exits nonzero, and performs no mutation. Reject a concrete narrow
or `all` second invocation that omits
`--confirmation-artifact <repository-relative-path>` or its exact repeated
`destroy:<env>:<account>:<scope>:<resource>:<consequence>` confirmations, uses
a non-repeatable confirmation interface, or shows `all` without the union of
required values. For every concrete UAT `destroy all` example and test union,
assert that the repeated values represent exactly these five scope/resource
and consequence contracts, with each operation-generated snapshot ID copied
from the artifact rather than hard-coded in documentation:

```text
destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster
destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs
destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs
destroy:uat:672172129937:postgresql-core:db/oms-uat-core:final-snapshot=<foundation-generated-id-from-artifact>
destroy:uat:672172129937:postgresql-brand:db/oms-uat-brand:final-snapshot=<foundation-generated-id-from-artifact>
```

Assert that no backend or governance confirmation is present, that only the
foundation creates and validates operation artifacts and confirmations,
including enforcing that each artifact is operation-bound and performing
expiry, single-use, replay, and tamper checks,
and that packages parse neither artifacts nor confirmation values. Assert the
documented lifecycle orders artifact validation, reverse-dependency execution
of immutable read-only guard wrappers defined by their package-owned numbered
verifier fragments at the exact canonical symbols already named by immutable
foundation mappings and delegated to distinct package internal functions,
exactly one structured in-memory result from each guard; foundation validation
of the complete ordered result set; and foundation-exclusive serialization of
operation-bound canonical JSON evidence before approval, confirmation-artifact
consumption, and handler dispatch. Assert packages perform no artifact writes
or evidence lifecycle operations, while foundation owns evidence schema, path,
permissions, digest, retention, access, audit, and cleanup. Assert a guard or
result-validation failure preserves the unconsumed confirmation artifact,
causes no mutation or dispatch, and is recorded through the foundation-owned
evidence audit lifecycle. Assert every destroy handler rechecks environment and
caller identity immediately before mutation. Assert each package-owned
numbered verifier fragment defines its exact canonical guard wrapper function
already named by the immutable foundation mapping and delegates to a distinct
package internal function; foundation fragments define no downstream wrappers,
packages mutate no registration or mapping, and no new public verifier or
destroy interface is added. Assert
actual-operation resource and snapshot values derive from validated UAT
configuration/platform contracts and the artifact, placeholders are not
accepted as operational values, and no hard-coded operation-generated ID is
presented as actual.

- [ ] **Step 5: When execution and commit are separately authorized, validate and commit**

```bash
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_mutating_commands_are_under_authorization_headings \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_docs_make_no_unsubstantiated_deployment_claims \
  -v
git diff --check
git add docs/guides/operator-runbook.md \
  docs/references/verification-commands.md \
  docs/references/recovery-procedures.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: define authorized operations and recovery"
```

Expected: focused tests PASS and `git diff --check` exits 0.

### Task 6: Add UAT Acceptance Evidence Templates

**Files:**
- Create: `docs/operations/uat-acceptance/README.md`
- Create: `docs/operations/uat-acceptance/provision.md`
- Create: `docs/operations/uat-acceptance/no-drift.md`
- Create: `docs/operations/uat-acceptance/destroy.md`
- Create: `docs/operations/uat-acceptance/rebuild.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Define the acceptance evidence contract**

The README states that a separate future UAT execution plan may execute only
after a named authorization is recorded and in this strict order:

```text
provision -> no-drift -> destroy -> rebuild -> final no-drift and smoke
```

Require evidence files produced by authorized execution to live under an
environment-qualified directory such as
`.local/uat/evidence/20260722T153045Z-frank-full-lifecycle/`. Define the run ID
as UTC basic timestamp, operator identifier, and scope joined with hyphens;
require mode `0700` for directories and `0600` for files. Committed templates
contain references and redacted summaries only.
Prohibit secrets, role ARN input files, generated tfvars, raw plans, state,
tokens, passwords, connection strings, and kubeconfig content.

Each template begins with:

```text
Status: NOT_EXECUTED
Environment: uat
Expected account: 672172129937
Authorization reference: NOT_RECORDED
Execution run ID: NOT_ASSIGNED
Operator: NOT_RECORDED
Reviewer: NOT_RECORDED
Started UTC: NOT_RECORDED
Completed UTC: NOT_RECORDED
Evidence digest manifest: NOT_RECORDED
Decision: PROMOTION_BLOCKED
```

These are explicit status sentinels, not omitted fields. The template explains
that authorized operators replace sentinels only with concrete evidence and
that review changes status through a dedicated evidence commit.

- [ ] **Step 2: Define provision evidence**

Include tables for:

- preflight identity/config/context evidence;
- imported-code matrix gate and zero unclassified rows;
- each scope in dependency order;
- saved-plan digest, add/change/destroy summary, reviewer, apply result, and
  verification result per Terraform root;
- rendered inventory and readiness per Kubernetes-owned scope;
- independent core/brand PostgreSQL identifiers and isolation checks;
- external Identity Center and Boomi authorization prerequisite references;
- deviations, owner, risk decision, and follow-up;
- final component and integrated smoke result.

The template must say a failed or skipped required row keeps status
`NOT_EXECUTED` or records a failed run; it cannot be marked accepted.

- [ ] **Step 3: Define no-drift evidence**

Include one row per Terraform state, one row per rendered overlay/release
inventory, generated-artifact isolation checks, environment/account reference
checks, and explicit core/brand cross-state isolation. Require plan digests and
summaries but not raw plans. Acceptance requires zero unexplained changes;
approved exceptions still block lifecycle acceptance until reconciled.

- [ ] **Step 4: Define destroy evidence**

Include reverse dependency order, precondition result, retention/backup
evidence, typed-confirmation digest, operator/reviewer, result, remaining
resources, and reconciliation action per scope. Give core and brand separate
rows and approvals. Add retained-control rows proving backend, Access Analyzer,
CloudTrail baseline, and governance alerts remain. Require a post-destroy
inventory showing no unintended cross-environment deletion. The template's
concrete UAT destroy flow must show both passes. The first invocation has no
`--confirmation-artifact` or complete confirmation set, prints a mode-`0600`
repository-relative artifact path and exact second-invocation arguments,
exits nonzero, and performs no mutation. The second invocation must include
`--confirmation-artifact <repository-relative-path-printed-by-first-invocation>`
and repeat the five-value union listed in Task 3 for `eks-platform`,
`boomi-runtime`, `mongodb`, `postgresql-core`, and `postgresql-brand`, with no
backend or governance confirmation. It must state that actual resource
identities and operation-generated final-snapshot IDs come from validated UAT
configuration, platform contracts, and the artifact, are never placeholders
in an actual operation, and are not hard-coded in documentation as actual
values. It must also state that the foundation guarantees the artifact is
operation-bound, owns expiry, single-use, replay, and tamper checks, and that
packages never parse the artifact or confirmation values. The destroy evidence
table must record each selected guard in reverse dependency order, its wrapper
symbol, exactly one structured in-memory result, canonical JSON evidence
reference and digest, and failure disposition. It must state that package
guards are read-only and never write artifacts; foundation runs guards after
confirmation-artifact validation, validates the complete ordered result set,
and, only after every guard reports `PASS`, exclusively writes the operation-bound canonical JSON success evidence before approval, confirmation-artifact consumption, or handler dispatch. The evidence table
records foundation ownership of evidence schema, path, permissions, digest,
retention, access audit, and cleanup. A failed, missing, duplicate, or invalid guard result leaves the confirmation artifact unconsumed, records zero mutation and zero handler dispatch, writes no all-pass evidence artifact, and is captured in a separate foundation-owned canonical `destroy-guard-failure.<operation-id>.json` audit record containing the ordered results received and failure metadata. It
must also record each destroy handler's environment and caller-identity
recheck immediately before mutation. Each package-owned numbered verifier
fragment defines its exact immutable pre-mapped canonical guard wrapper
function and delegates to a distinct package internal function. Foundation
owns the immutable mappings, loader, validation, and graph but defines no
downstream wrappers; packages do not mutate registration or mappings, perform
artifact I/O, or add a public command form.

- [ ] **Step 5: Define rebuild evidence**

Require a clean starting inventory, documented commands only, no manual state
or resource repair, complete provision evidence cross-reference, final
no-drift cross-reference, smoke result, PostgreSQL separation, audit and
observability dimensions, and a final reviewer decision. A manual workaround
must be documented as a failed rebuild criterion until incorporated into code
and rerun.

- [ ] **Step 6: Test sentinel and section completeness**

Assert all four files start `NOT_EXECUTED`, include every metadata field, do
not contain secret-like values, and contain their required tables. Assert the
README contains the exact acceptance order and says implementation of this
plan does not authorize execution. Assert the destroy template assigns package
guards only the read-only, one-result in-memory API and assigns foundation
exclusive ownership of ordered-result validation, canonical JSON evidence
writes, and the complete evidence audit lifecycle.

- [ ] **Step 7: When execution and commit are separately authorized, validate and commit**

```bash
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_uat_acceptance_templates_start_not_executed \
  -v
git add docs/operations/uat-acceptance \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: add UAT acceptance evidence templates"
```

Expected: focused acceptance-template test PASS.

### Task 7: Validate And Index The Foundation-Owned Imported-Code Review Matrix

**Files:**
- Verify: `docs/operations/imported-code-review-matrix.md`
- Verify: `scripts/validate-imported-code-review-matrix.py`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Validate the existing foundation-owned matrix through its validator**

Treat the landed foundation-created matrix and validator as inputs, not files
introduced by this plan. Invoke the foundation validator against exactly
`docs/operations/imported-code-review-matrix.md`. The one canonical table has
exactly these seven columns and no others:

```text
ID | Domain | Source | Target | Disposition | Evidence | Status
```

IDs use the foundation pattern `DOMAIN-0001`, replacing `DOMAIN` with an

```text
FOUNDATION, EKS, DATA, BOOMI, DOCS
```

This list is exactly the foundation validator's closed domain enum. Detailed
subsystem classification belongs in `Source`, `Target`, and `Evidence`, not in
additional `Domain` values or a documentation-specific second enum.
`Disposition` values are exactly uppercase `KEEP`, `REWRITE`, `REPLACE`, or
`REJECT`. `Status` values are exactly uppercase `PROPOSED`, `REVIEWED`, or
`VERIFIED`. The foundation validator remains the sole schema, ID, enum,
evidence, duplicate, placeholder, and unclassified-row authority. This task
does not reproduce those checks in a documentation-specific parser.

Verify that the matrix records read-only external sources explicitly. This
repository never copies source Terraform state, credentials, generated files,
`.terraform/`, lock ownership, or account assumptions.

- [ ] **Step 2: Verify every package appended its rows in place**

For each Phase 2 implementation package, verify that it already appended its
reviewed source rows directly to the foundation-created table, preserving
concrete source, target, disposition, and evidence. This final work package
only invokes the landed validator and adds navigation to the canonical file;
it never recreates the matrix, copies rows to another document, changes the
seven-column schema, creates another matrix path, or authors missing package
rows.

The landed matrix must include every considered script, Terraform
module/resource, manifest, Helm value, configuration value, and generated-file
behavior. A source item considered and intentionally not used must already be
recorded as `REJECT`; absence is not a classification. Duplicate source/target
decisions are rejected by the foundation validator.

Do not add an `UNCLASSIFIED` decision. If implementation work exposes an item
without a reviewed decision, stop this task and return it to the owning work
package before UAT planning is authorized.

- [ ] **Step 3: Add validator invocation and navigation tests**

Run `scripts/validate-imported-code-review-matrix.py` against exactly the
canonical path `docs/operations/imported-code-review-matrix.md` and assert it
exits zero. Require every UAT-gate row to have exact status `REVIEWED` or
`VERIFIED`; `PROPOSED` never passes the gate. Do not parse or copy matrix rows
in `tests/documentation/test_documentation_contract.py` or introduce a second
schema, domain interpretation, path, or status gate. Separately assert that
the UAT acceptance README and `docs/index.md` link the canonical matrix path as
a blocking gate.

- [ ] **Step 4: When execution and commit are separately authorized, validate and commit**

```bash
python3 scripts/validate-imported-code-review-matrix.py \
  docs/operations/imported-code-review-matrix.md
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_imported_code_rows_have_closed_decisions \
  -v
git add docs/operations/uat-acceptance/README.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: validate and index imported infrastructure decisions"
```

Expected: the foundation validator exits zero, reports only valid reviewed or
verified gate rows, and the navigation test passes. The matrix and validator
are not staged or modified by this task.

### Task 8: Map Legacy Ownership And Create Separate Dev Adoption Artifacts

**Files:**
- Create: `docs/operations/legacy-command-state-mapping.md`
- Create: `docs/operations/dev-adoption/README.md`
- Create: `docs/operations/dev-adoption/resource-state-inventory.md`
- Create: `docs/operations/dev-adoption/state-move-import-plan.md`
- Create: `docs/operations/dev-adoption/postgresql-topology-decision.md`
- Create: `docs/operations/dev-adoption/promotion-gate.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Inventory legacy commands and local ownership**

Create stable mapping IDs and rows for every legacy public command and alias,
including at minimum:

```text
scripts/provision.sh all
scripts/provision.sh mongodb
scripts/provision.sh mongo
scripts/provision.sh pg
scripts/provision.sh signoz
scripts/provision.sh signoz-observability
scripts/destroy.sh all
scripts/destroy.sh mongodb
scripts/destroy.sh mongo
scripts/destroy.sh pg
scripts/destroy.sh signoz
scripts/destroy.sh signoz-observability
scripts/verify-platform-health.sh
scripts/provision-uat-access.sh governance
scripts/provision-uat-access.sh eks-access
scripts/provision-uat-access.sh all
```

Columns are:

```text
ID | Legacy interface | Environment limit | Current owner/state |
Unified destination | Compatibility behavior | Retirement gate |
Adoption artifact | Verification
```

Inventory all top-level scripts even if internal, and map each to reused,
forwarded, frozen, replaced, or retired behavior. No Phase 2 scope may route
through a legacy dev mutation script.

- [ ] **Step 2: Map state, Terraform, Kubernetes, and generated artifacts**

Add separate tables for:

- legacy state keys, including `oms/dev/mongo.tfstate`,
  `oms/dev/pg.tfstate`, and `oms/dev/signoz-observability.tfstate`;
- every Terraform address obtained from configuration and, during separately
  authorized read-only adoption discovery, `terraform state list`;
- Kubernetes namespaces, releases, CRDs, policies, workloads, services,
  service accounts, Secrets by name only, PVCs, and storage classes;
- local escrow, generated tfvars, plan, lock, log, and evidence paths;
- destination unified scope and disposition `REUSE`, `MOVE`, `IMPORT`, or
  `RETIRE`.

The committed documentation phase records known static rows and labels live
inventory evidence `NOT_RECORDED`. Live discovery is an authorized dev
adoption activity, not part of this plan.

- [ ] **Step 3: Define the dev resource/state inventory artifact**

Start with:

```text
Status: NOT_EXECUTED
Environment: dev
Expected account: 815402439714
Mutation permitted: false
Inventory evidence: NOT_RECORDED
```

Provide tables for AWS resource identifiers, Terraform state/address,
Kubernetes identity, local artifact, owner, destination scope, disposition,
backup reference, collision check, and reviewer. Require every mapping row ID
to resolve to exactly one disposition.

- [ ] **Step 4: Define the state move/import plan artifact**

Start `Status: NOT_EXECUTED` and include:

- remote-state version/backup references;
- source and destination address/state;
- exact proposed `terraform state mv` or `terraform import` command;
- immutable resource identifier;
- reason the operation is safe;
- rollback command and backup version;
- peer reviewer;
- pre-move plan summary;
- post-move plan summary requiring no unintended create, replace, or destroy.

Commands are content under **Authorized dev adoption command** and must not be
run in this work package. Prohibit automatic import based only on a name.

- [ ] **Step 5: Define the PostgreSQL topology decision artifact**

Start with `Decision: NOT_RECORDED`. Require evidence for the existing cluster
identifier, database name, workloads, schemas, users/roles, network paths,
secret ownership, retention, and application consumers. The reviewer must
choose exactly one destination for `oms/dev/pg.tfstate`:

```text
postgresql-core
postgresql-brand
```

Then require a separate reviewed create-or-adopt plan for the missing second
cluster. State explicitly that one legacy state cannot own both clusters and
that a temporarily retained third cluster needs an owner, read/write status,
migration plan, retirement date, and completion-blocking gate.

- [ ] **Step 6: Define the promotion gate artifact**

Start with:

```text
Decision: PROMOTION_BLOCKED
Unified dev mutation enabled: false
Approval reference: NOT_RECORDED
```

Require all of these gates:

1. UAT provision, no-drift, destroy, rebuild, final no-drift, and smoke
   evidence are `EVIDENCE_RECORDED`.
2. The foundation validator accepts the imported-code matrix and all UAT-gate
  rows have uppercase `REVIEWED` or `VERIFIED` status.
3. Every legacy command, state object, Terraform address, Kubernetes resource,
   and local artifact has one reviewed disposition.
4. State backups and rollback commands are recorded.
5. PostgreSQL legacy state has exactly one core-or-brand destination and the
   second-cluster plan is approved.
6. Proposed moves/imports are peer-reviewed.
7. Unified dev plans show no unintended create, replace, or destroy per root.
8. Cross-environment reference and generated-artifact isolation tests pass.
9. Security, platform, database, and application owners approve.
10. A separate code change enables dev mutation; editing this document cannot
    enable it.

- [ ] **Step 7: Add adoption and mapping tests**

Assert every legacy script/scope/state found in the current implementation has
a row; every disposition is closed; the PostgreSQL artifact requires exactly
one destination; all adoption files begin blocked/not executed; and no
authorized dev command appears in README/setup/runbook while promotion remains
blocked.

- [ ] **Step 8: When execution and commit are separately authorized, validate and commit**

```bash
python3 -m unittest \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_legacy_mapping_has_no_unclassified_rows \
  tests.documentation.test_documentation_contract.DocumentationContractTests.test_dev_promotion_starts_blocked \
  -v
git add docs/operations/legacy-command-state-mapping.md \
  docs/operations/dev-adoption \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: define legacy mapping and dev adoption gate"
```

Expected: both focused tests PASS; no AWS, Terraform backend, or Kubernetes
command has run.

### Task 9: Complete Navigation And Cross-Document Contracts

**Files:**
- Modify: `docs/index.md`
- Modify: `docs/operations/README.md`
- Modify: `docs/references/component-catalog.md`
- Modify: `docs/guides/architect-reference.md`
- Modify: `tests/documentation/test_documentation_contract.py`

- [ ] **Step 1: Make the docs index environment-aware**

Add first-class links to:

- the canonical provisioning guide;
- environment capability/status matrix;
- approved unified design;
- this implementation plan;
- Terraform inventory;
- UAT acceptance index and four templates;
- canonical `docs/operations/imported-code-review-matrix.md`;
- legacy mapping;
- dev adoption index and promotion gate.

Replace the dev-only system overview and deployment sequence with the complete
scope boundary and a link to the canonical dependency graph. Preserve Boomi
persona links and the audit-log contract; this phase changes infrastructure
navigation, not the Boomi API contract.

- [ ] **Step 2: Update operations, component, and architecture navigation**

`docs/operations/README.md` describes status, acceptance, matrix, mapping, and
adoption artifacts and their update owners. `component-catalog.md` uses the
canonical scope names and identifies the owner/state for every component.
`architect-reference.md` links the shared-module, dual-PostgreSQL,
environment-overlay, state-isolation, output-contract, retained-governance,
and promotion-gate sections without copying operator commands.

- [ ] **Step 3: Make link validation anchor-aware**

Complete the Markdown test helper so relative links resolve after URL decoding,
ignore `http:`, `https:`, and `mailto:`, and validate local `#anchor` fragments
against GitHub-style heading slugs. Skip fenced code blocks and historical
documents from command-truthfulness checks, but do not skip them from local
link resolution.

- [ ] **Step 4: When execution is separately authorized, run full documentation verification**

```bash
python3 -m unittest discover -s tests/documentation -p 'test_*.py' -v
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
git diff --check
```

Expected: all documentation and existing UAT access static tests PASS; diff
check exits 0.

- [ ] **Step 5: When commit is separately authorized, commit navigation**

```bash
git add docs/index.md docs/operations/README.md \
  docs/references/component-catalog.md docs/guides/architect-reference.md \
  tests/documentation/test_documentation_contract.py
git commit -m "docs: connect Phase 2 operator navigation"
```

### Task 10: Validate And Index The Documentation Package When Separately Authorized

**Files:**
- Verify: all files changed by Tasks 1-9

- [ ] **Step 1: When execution is separately authorized, run Python contracts**

```bash
python3 -m unittest discover -s tests/documentation -p 'test_*.py' -v
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
```

Expected: all tests PASS.

- [ ] **Step 2: When execution is separately authorized, run offline syntax and format checks**

```bash
bash -n scripts/*.sh scripts/lib/*.sh
terraform fmt -check -recursive platform-prerequisites/terraform
git diff --check
```

Expected: all commands exit 0. `terraform fmt -check` is formatting-only and
must not initialize a backend or contact providers.

- [ ] **Step 3: When execution is separately authorized, run offline Terraform validation only for initialized local fixtures**

Use the repository's existing backend-free static test harness. If merged
work packages provide an explicit offline validation script, run that exact
script. Do not run `terraform init` in this documentation package merely to
enable validation. Record the exact command used in the commit message body or
review notes.

Expected: all available backend-free validations PASS; unavailable provider
plugins are reported as a skipped offline prerequisite, not replaced with a
live backend initialization.

- [ ] **Step 4: When execution is separately authorized, render every environment overlay offline**

```bash
for file in $(find k8s gitops policies -name kustomization.yaml -print | sort); do
  kustomize build "$(dirname "$file")" >/dev/null
done
```

Expected: every committed base/overlay renders without contacting a cluster.
If a base is intentionally non-runnable alone, list it in the documentation
test's explicit non-runnable-base set and render each environment overlay that
consumes it instead.

- [ ] **Step 5: When execution is separately authorized, prove no evidence or secrets were committed**

```bash
if git ls-files | rg '(^|/)(\.local|terraform\.tfstate|[^/]*\.tfplan|generated\.auto\.tfvars\.json)(/|$)'; then
  echo "Generated execution artifact is tracked" >&2
  exit 1
fi

if rg -n '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*[^N])' \
  README.md docs config/environments; then
  echo "Potential credential-like documentation value found" >&2
  exit 1
fi
```

Expected: no tracked generated execution artifact and no credential-like
value. Review any false positive manually and narrow the static expression;
never suppress a real secret.

- [ ] **Step 6: When execution is separately authorized, verify status remains non-executed and blocked**

```bash
rg -n '^Status: NOT_EXECUTED$' docs/operations/uat-acceptance/*.md \
  docs/operations/dev-adoption/*.md
rg -n '^Decision: PROMOTION_BLOCKED$|^Unified dev mutation enabled: false$' \
  docs/operations/uat-acceptance/*.md \
  docs/operations/dev-adoption/promotion-gate.md
```

Expected: all UAT templates and dev adoption artifacts retain non-executed or
blocked status. No file claims `EVIDENCE_RECORDED` or `PROMOTION_APPROVED` as
its current status.

- [ ] **Step 7: When execution is separately authorized, review the final diff without executing live commands**

```bash
git status --short
git diff --stat
git diff -- README.md docs config/environments \
  platform-prerequisites/terraform/README.md tests/documentation
```

Expected: only planned documentation, examples, and documentation-test files
are changed. No `.local/`, plan, state, generated tfvars, lock, evidence,
credential, or implementation file is present.

- [ ] **Step 8: When commit is separately authorized, commit static acceptance corrections if needed**

If Steps 1-7 required documentation-only corrections:

```bash
git add README.md docs config/environments \
  platform-prerequisites/terraform/README.md tests/documentation
git commit -m "test: verify Phase 2 documentation contracts"
```

If no correction was required, do not create an empty commit.

## Future UAT Execution Plan Inputs: Documentation Templates Only

The implementing engineer adds the exact frozen command forms to the canonical
guide and acceptance templates but does not run them in this work package.
UAT acceptance is not an execution task here. A separate future execution plan
must record authorization, sequence the lifecycle, confirm UAT account
`672172129937` and canonical cluster context, and collect evidence before any
command below may run.

### Authorized UAT acceptance command: provision

```bash
bash scripts/provision.sh --env uat all
bash scripts/verify-platform-health.sh --env uat --smoke-test
```

### Authorized UAT acceptance command: no drift

Run the merged environment-aware no-drift entrypoint for every Terraform root
and rendered Kubernetes scope, then record per-root `add/change/destroy`
summaries and digests in `docs/operations/uat-acceptance/no-drift.md`. The
documentation must use the exact implemented entrypoint; it must not invent a
raw Terraform loop that bypasses backend/account guards.

### Authorized UAT acceptance command: destroy

First invocation, intentionally incomplete and guaranteed not to mutate:

```bash
bash scripts/destroy.sh --env uat all
```

This invocation must create a mode-`0600` operation artifact, print its
repository-relative path and the exact arguments for the second invocation,
and exit nonzero without mutation. Use only those printed values in the second
invocation:

```bash
bash scripts/destroy.sh --env uat all \
  --confirmation-artifact <repository-relative-path-printed-by-first-invocation> \
  --confirm destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster \
  --confirm destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs \
  --confirm destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs \
  --confirm destroy:uat:672172129937:postgresql-core:db/oms-uat-core:final-snapshot=<foundation-generated-id-from-artifact> \
  --confirm destroy:uat:672172129937:postgresql-brand:db/oms-uat-brand:final-snapshot=<foundation-generated-id-from-artifact>
```

The second block is a template: its angle-bracketed artifact path and snapshot
IDs are not operational values and must be replaced by the exact output from
the first invocation. No operation-generated ID is hard-coded or presented as
actual. The concrete resource identities come from the validated UAT
configuration and platform contracts. Run only after separate retention
evidence and the foundation-owned two-pass interface has received both the
operation artifact and the union of exact typed values required for every
selected persistent scope, using the grammar
`destroy:<env>:<account>:<scope>:<resource>:<consequence>`. The foundation
guarantees that the artifact is operation-bound, owns expiry, single-use,
replay, and tamper checks, and validates confirmations; packages parse neither
the artifact nor confirmation values. After artifact validation, foundation
runs the selected immutable read-only pre-destroy guard wrappers in reverse
dependency order. Each wrapper is defined by its package-owned numbered
verifier fragment at the exact canonical symbol already named by the immutable
foundation mapping and delegates to a distinct package internal function. Each
guard emits exactly one structured in-memory result and never writes an
artifact. Foundation validates the complete ordered result set and exclusively
writes operation-bound canonical JSON evidence before it performs approval,
consumes the confirmation artifact, or dispatches destroy handlers. Foundation
owns the evidence schema, path, permissions, digest, retention, access, audit,
and cleanup lifecycle. Any guard or result-validation failure exits nonzero,
preserves the unconsumed confirmation artifact, dispatches no handler, performs
no mutation, and is recorded through the foundation-owned evidence audit
lifecycle. Every dispatched handler rechecks the selected environment and
caller identity immediately before mutation. Each package-owned numbered
verifier fragment defines its exact canonical guard wrapper function already
named by the immutable foundation mapping and delegates to a distinct package
internal function. Foundation fragments define no downstream wrappers;
packages mutate no registration or mappings, write no artifacts, and this
lifecycle adds no public command, flag, scope, or verifier mode. Backend and governance controls have no ordinary
`destroy all` confirmation and remain retained; confirm them afterward through
the merged verification entrypoint.

### Authorized UAT acceptance command: rebuild

```bash
bash scripts/provision.sh --env uat all
bash scripts/verify-platform-health.sh --env uat --smoke-test
```

Rebuild acceptance additionally requires final no-drift evidence. Any manual
repair means the documented-command rebuild criterion failed and must be rerun
after code correction.

## Completion Gate

This documentation work package is complete only when:

- README and docs present one truthful environment-aware operator path;
- every script, Terraform root, reusable module, base/overlay, config class,
  and generated artifact is explained with ownership and rationale;
- safe examples are complete, non-secret, and intentionally non-runnable;
- full and narrow UAT procedures include independent core/brand PostgreSQL;
- destroy documentation and acceptance evidence preserve the existing public
  interfaces while proving the immutable foundation lifecycle: artifact
  validation; reverse-order read-only pre-destroy guards defined by their
  package-owned numbered verifier fragments at the exact canonical symbols
  already named by immutable foundation mappings and delegated to distinct
  package internal functions; exactly one structured in-memory result emitted
  by each package guard with no package artifact writes; foundation validation
  of the complete ordered result set; foundation-exclusive operation-bound
  canonical JSON evidence creation before approval, confirmation-artifact
  consumption, or handler dispatch; foundation ownership of evidence schema,
  path, permissions, digest, retention, access, audit, and cleanup;
  confirmation-artifact preservation, zero mutation, and zero dispatch on guard
  or result-validation failure; and an identity recheck by every destroy
  handler immediately before mutation, with no registration or mapping mutation
  and no downstream wrapper definitions in foundation fragments;
- dev is documented as modeled/read-only and mutation remains blocked;
- UAT templates remain `NOT_EXECUTED` and make no deployment claim;
- the foundation-created imported-code matrix is indexed and validates with
  the foundation validator using the exact seven-column schema and uppercase
  enums, without recreating it, copying rows, or adding another matrix path;
- every legacy command/state/resource/artifact has a destination disposition;
- dev adoption has separate inventory, move/import, PostgreSQL decision, and
  promotion artifacts with `PROMOTION_BLOCKED` as the current decision;
- after separate execution authorization, all static documentation, link,
  inventory, syntax, formatting, render, and secret-path checks pass;
- no AWS, Kubernetes, database, SigNoz, Boomi, backend, plan, apply, destroy,
  import, state move, smoke, acceptance, or adoption execution occurred while
  implementing this plan.