# Phase 2 Environment Orchestration Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Required preflight rubric before implementation:** Before any implementation command, edit, or commit for this plan, the implementing agent MUST output a fully completed markdown table from `docs/superpowers/specs/subagent-preflight-rubric.md` covering Safety, Operability, Portability, and Recoverability, with concrete evidence and pass/fail outcomes for each row.

**Goal:** Build work packages 1-2 of the approved unified-environment design: extensible closed `dev`/`uat` contracts, fail-closed shared guards and environment-local artifacts, and the permanent registry-driven provision/destroy/verify foundation that later work packages extend only through declarative numbered manifests and canonical handler/pre-destroy-guard/verifier fragments.

**Architecture:** This foundation exclusively owns the three public scripts, `platform-env.sh`, `environment-contracts.sh`, `scope-registry.sh` and its complete final dependency/reverse/verification graph and provision/destroy/pre-destroy-guard/verifier symbol mappings, `orchestrator.sh`, `orchestration-paths.sh`, `confirmation-artifact.py`, `destroy-evidence.py`, and the single per-environment lock. Invocations without `--env` execute frozen legacy dev implementations unchanged; invocations with `--env` enter a data-only environment parser, immutable constants, shared safety guards, and a registry dispatcher that never calls legacy dev code. Later plans add only numbered declarative environment-schema manifests, package-owned mode-safe internal libraries, and canonical named handler/pre-destroy-guard/verifier function fragments; they never edit foundation code, parser logic, public routing, registry mappings, orchestration order, evidence/confirmation behavior, path/lock behavior, or the `all` graph.

**Tech Stack:** Bash 3.2-compatible shell libraries, non-executable UTF-8 dotenv files, Python 3 standard-library `unittest`, temporary mocked executables, existing Terraform access roots and backend bootstrap script, `jq`, static source-contract tests

---

## Scope, Constraints, And Execution Policy

This plan implements only work packages 1 and 2 from
`docs/superpowers/specs/2026-07-22-unified-environment-provisioning-design.md`.
It does not implement EKS platform resources, Kubernetes controllers, MongoDB,
either PostgreSQL cluster, database access, workload identity, SigNoz, SigNoz
observability, or the Boomi runtime. Those scopes appear in the registry only
as closed dependency declarations whose handlers fail before backend access,
generated-file mutation, Terraform, AWS, or Kubernetes execution.

The current review session is planning/editing/static-source-review only.
**Do not execute or commit anything.** This is a uniform hard boundary over
every command block in this document: tests, formatters, syntax checks,
validators, repository scripts, initialization, render, dry-run, Terraform,
AWS CLI, kubectl, Git commands, and any other command may run only after the
user separately authorizes execution in a later session. A narrower label such
as `test`, `static`, `offline`, `read-only`, `dry-run`, or `init` never implies
authorization. Editor/file-reading review is allowed now; editing this plan is
allowed now. During implementation, code editing may proceed only within the
then-current authorization, and each command and commit remains separately
gated. All command steps below are instructions for that future authorized
session, not commands to run while reviewing this plan.

The immutable account constants are:

| Environment | AWS account | Region | Promotion mode |
|---|---:|---|---|
| `dev` | `815402439714` | `ap-east-1` | `modeled` (all unified mutation blocked) |
| `uat` | `672172129937` | `ap-east-1` | `uat-build` (only available fixed-graph scopes may mutate) |

The UAT EKS and workforce contract remains the approved Phase 1 contract:

| Field | Immutable value |
|---|---|
| Cluster | `EKS-boomi-runtime-cluster` |
| Boomi namespace | `boomi-uat` |
| Infra role prefix | `AWSReservedSSO_UATInfraAdminEA_` |
| Application developer prefix | `AWSReservedSSO_UATApplicationDeveloper_` |
| Boomi admin prefix | `AWSReservedSSO_UATBoomiAdmin_` |
| Process owner prefix | `AWSReservedSSO_UATBoomiProcessOwner_` |

Do not invent dev Identity Center role prefixes in this plan. Unified dev
mutation is blocked, and its workforce principal contract is a required input
to the later dev-adoption plan. The parser still validates the committed dev
account, Region, cluster, namespaces, backend, state-key, and promotion
constants.

## Canonical Foundation Ownership And APIs

The following files and behavior have one owner for all Phase 2 plans: this
foundation plan.

| Foundation-owned surface | Permanent contract |
|---|---|
| `scripts/provision.sh`, `scripts/destroy.sh`, `scripts/verify-platform-health.sh` | Only public routing entrypoints; later plans do not add or edit public orchestration scripts. |
| `scripts/lib/scope-registry.sh` | Owns the complete final scope catalog, dependencies, deterministic provision order, reverse destroy order, internal verification order, state-key mapping, and required provision/destroy/pre-destroy-guard/verifier symbols. |
| `scripts/lib/orchestrator.sh` | Owns parsing, secure fragment loading, complete-graph pre-resolution, promotion authorization, reverse-order pre-destroy guard dispatch, the active guard-capture protocol, destroy evidence and confirmation-artifact orchestration, one-lock lifecycle, and handler dispatch. |
| `scripts/lib/orchestration-paths.sh` | Owns all `.local/<env>/` paths, evidence/confirmation-artifact placement, containment checks, cleanup registration, and the single environment lock. |
| `scripts/lib/destroy-evidence.py` | Owns the closed pre-destroy guard-evidence schema, canonical bytes, exclusive mode-`0600` writes, no-follow validation, digests, operation binding, atomic lifecycle-status files, retention checks, and evidence cleanup. |
| `scripts/lib/confirmation-artifact.py` | Owns the closed destroy-confirmation schema, canonical bytes, no-follow validation, and atomic consumption. |
| `scripts/lib/platform-env.sh` | Owns generic dotenv parsing and generic manifest-driven closed-schema validation; later plans never edit parser logic. |
| `scripts/lib/environment-contracts.sh` | Owns immutable account, Region, environment name, state-prefix, promotion-mode, and approved role-prefix constants independently of editable manifests/config. |

These function names and signatures are canonical downstream APIs:

```bash
load_platform_env <dev|uat>
verify_aws_identity_and_region
verify_kubernetes_context
initialize_orchestration_paths
require_environment_mutation_authorized
source_package_internal_library <repository-relative-path>
dispatch_scope_handler <provision|destroy|verify> <scope-or-mode> [handler-args...]
record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>
```

`pre_destroy_guard_for_scope <canonical-scope>` is a foundation-owned internal
registry lookup used only by `orchestrator.sh`; it is not a public dispatcher,
mode, registration API, or package-selectable operation.

`record_pre_destroy_guard_result` is the only guard-result channel and its
signature remains exactly the five arguments shown above. Before
invoking each selected guard, the orchestrator opens an in-memory capture phase
for exactly that expected canonical scope. The callback rejects calls outside
an active guard phase, calls for any scope other than the active expected
scope, and a missing or duplicate call. It records exactly one result in
memory and performs no file or remote write. Guard stdout and stderr are
diagnostics only and are never parsed as evidence. After the wrapper returns,
the orchestrator requires one callback result and requires callback status
`PASS` with wrapper status zero, or callback status `FAIL` with wrapper status
nonzero; disagreement, missing result, duplicate result, or callback misuse
fails closed. On any `FAIL`, missing, duplicate, malformed, wrong-scope,
out-of-phase, out-of-order, or wrapper/status-disagreeing result, the
foundation writes the separate canonical operation-bound guard-failure record
defined below, does not write the all-pass guard-evidence artifact, leaves the
confirmation artifact unconsumed, and performs no dispatch. No package may
replace, wrap, export, or invoke the callback
outside its currently active mapped guard wrapper.

The callback grammar is closed and locale-independent: `scope` must be the
exact registry-selected lowercase token; `status` is exactly `PASS` or `FAIL`;
`resource-identity` matches
`^[A-Za-z0-9][A-Za-z0-9._/@+=:-]{0,255}$`; `evidence-digest` matches exactly
`^sha256:[0-9a-f]{64}$`; and `summary-code` matches
`^[A-Z][A-Z0-9_]{0,63}$`. Empty values, whitespace, control bytes, alternate
digest algorithms/casing, unknown statuses, and tokens outside these grammars
are rejected before the result enters the ordered in-memory capture.

`PROMOTION_MODE` accepts exactly `modeled` and `uat-build` and is the sole
environment mutation gate. No plan may introduce
`MUTATION_ENABLED`, `DEV_MUTATION_ENABLED`, `UAT_MUTATION_ENABLED`,
`BOOMI_MUTATION_ENABLED`, `require_mutation_enabled`, or component-specific
mutation booleans. `require_environment_mutation_authorized` interprets only
the immutable expected `PROMOTION_MODE`, selected environment, operation, and
scope. It authorizes mutation now only when `ENVIRONMENT=uat` and
`PROMOTION_MODE=uat-build`; `ENVIRONMENT=dev` is always blocked in the unified
path, including if an editable config attempts another value. A handler may
impose stricter safety preconditions but may not create another
environment-enable switch.

The registry maps every final provision/destroy scope, every destroyable
canonical scope's read-only pre-destroy guard, and every internal verification
slot to one canonical required function name from the fixed graph. These
mappings are immutable: there is no registration API, no
registration call, and no fragment-provided graph, order, slot, mode, or
mapping data. The loader validates each selected fragment as a regular,
non-symlink, mode-safe file beneath its canonical numbered package directory
before sourcing it. While that fragment is loading, it may call only the
foundation-owned `source_package_internal_library <repository-relative-path>`
helper to source implementation libraries beneath its own
`scripts/lib/packages/NN-domain/internal/` directory. The helper rejects an
absolute path, `..`, a path outside the active package directory, malformed
ownership, a symlink, a non-regular file, and group/world-writable mode before
sourcing. Direct `source`/`.` of any other path from a fragment is rejected by
static fragment validation. Each fragment itself defines the exact canonical
wrapper functions already pre-mapped to its package by the registry. Existing
numbered `scope-verifiers.d` fragments define both their exact mapped read-only
pre-destroy guard wrappers and their exact mapped internal verification
wrappers. Guard implementation libraries and verification implementation
libraries remain distinct even when the same package owns both. After loading,
the loader verifies that every selected required symbol is a shell
function with the exact immutable registry name and that the fragment defined
no unassigned function. Missing or unavailable symbols fail closed before
`.local/` creation or command execution. Foundation placeholders use those
canonical names and return non-zero with
`ERROR: <scope> requires <owning work package>` without command or file
mutation. For a selected destroy graph this includes the mapped pre-destroy
guard symbol for every selected destroyable scope: an absent downstream symbol
selects the canonical fail-closed placeholder for that scope rather than
skipping the guard. A downstream numbered fragment cannot alter graph, order,
mode, slot, or mapping variables.

## Public Compatibility Contract

These existing commands retain their current behavior and argument grammar:

```bash
bash scripts/provision.sh all
bash scripts/provision.sh mongodb
bash scripts/provision.sh mongo
bash scripts/provision.sh pg --auto-approve
bash scripts/provision.sh signoz
bash scripts/provision.sh signoz-observability --auto-approve
bash scripts/destroy.sh all --auto-approve
bash scripts/verify-platform-health.sh --preflight
```

Their current bodies move byte-for-byte into `scripts/legacy/dev/`; thin public
wrappers invoke them only when `--env` is absent. This is separation, not
generalization: no new environment library, registry, handler, or UAT command
may source or execute a file below `scripts/legacy/dev/`.

These no-`--env` commands are compatibility paths for the existing dev
environment, not members of the unified graph. Unified UAT orchestration never
calls them directly or indirectly. New documentation uses explicit `--env`
commands; preserving a legacy command does not authorize changing its behavior
or treating it as an implementation handler.

The new explicit interface is:

```bash
bash scripts/provision.sh --env uat access-governance
bash scripts/provision.sh --env uat eks-access
bash scripts/provision.sh --env uat all
bash scripts/destroy.sh --env uat eks-access
bash scripts/verify-platform-health.sh --env uat --preflight
```

These examples illustrate the leading `--env <scope>` command shape only, not
a complete recipe for every operation. In particular, the destroy example is
a first-pass preparation invocation as specified in Task 4: run without
`--confirm`/`--confirmation-artifact`, it generates the confirmation artifact,
prints the required second-pass arguments, and exits nonzero without
mutation — it does not delete anything by itself. See Task 4's two-pass
destroy protocol for the complete, non-illustrative command sequence.

`--env` must be the first argument. This deliberately makes routing decidable
before legacy code, AWS, backend, Terraform, Kubernetes, locks, plans, or
generated files are touched. Explicit invocations reject missing values,
duplicates, `--env=uat`, unsupported names, and flags before scope. There is no
default environment.

The public verification grammar remains mode-based and contains no component
scope or executable. The complete accepted forms after `--env <dev|uat>` are
exactly `--preflight`, `--full`, no mode flag, and `--smoke-test`; no mode flag
is exactly equivalent to `--full`. No other flag, positional value, alias, or
combination is accepted. The orchestrator maps the selected public mode to an
immutable list of internal verifier slots and invokes their registry-mapped
verifier symbols in dependency order. Downstream work packages provide
verifier fragments for those pre-existing slots; they do not register modes
or slots downstream and do not add public component modes, component
verification scripts, aliases, or executables.

## File Structure

| File | Responsibility |
|---|---|
| `config/environment-schema/base.manifest` | Foundation key declarations, validators, requiredness, and immutable bindings. |
| `config/environment-schema/fragments/NN-domain.manifest` | Declarative downstream key fragments loaded in bytewise lexical order without parser edits; `NN` is two decimal digits and `domain` is a lowercase hyphenated owner name. |
| `config/environments/dev.env` | Closed committed dev modeling values for the composed manifest. |
| `config/environments/uat.env` | Closed committed UAT values for the composed manifest. |
| `config/environments/<env>.local/*.json.example` | Canonical checked-in local-input examples; real sibling `.json` files remain ignored. |
| `scripts/lib/environment-contracts.sh` | Compiled immutable account, Region, promotion, state-prefix, and UAT role-prefix constants. |
| `scripts/lib/platform-env.sh` | Generic non-executable dotenv/manifest parser, composed closed-schema validation, immutable comparison, and selected exports. |
| `scripts/lib/platform-guards.sh` | Override, AWS account/Region, backend-input, Kubernetes ARN, and EKS authentication-mode guards. |
| `scripts/lib/orchestration-paths.sh` | Environment-qualified `.local/<env>/` directories, locks, plans, generated inputs, and cleanup helpers. |
| `scripts/lib/confirmation-artifact.py` | Foundation-only standard-library implementation for exclusive mode-`0600` destroy-artifact creation, no-follow descriptor reads, validation, and atomic consumed renames; never a public operator entrypoint. |
| `scripts/lib/destroy-evidence.py` | Foundation-only standard-library implementation for canonical mode-`0600` operation-bound guard evidence, no-follow validation/digest binding, atomic lifecycle-status files, retention, and safe cleanup; never a public operator entrypoint. |
| `scripts/lib/scope-registry.sh` | Canonical scopes, provision dependencies, reverse-destroy and verification orders, implementation status, and required provision/destroy/pre-destroy-guard/verifier symbol lookup. |
| `scripts/lib/orchestrator.sh` | Parse explicit command shape, pre-resolve graph, run guards, acquire one environment lock, and dispatch handlers. |
| `scripts/lib/packages/NN-domain/internal/*.sh` | Package-owned implementation libraries; sourceable only by the matching active numbered fragment through `source_package_internal_library` after canonical path, ownership, regular-file, non-symlink, and mode validation. |
| `scripts/lib/scope-handlers.d/NN-domain.sh` | Mode-safe downstream fragments loaded in bytewise lexical order; each file may source only its package-owned validated internal libraries through the foundation helper, then defines exact registry-pre-mapped canonical provision/destroy wrappers; it contains no registration, graph, order, mode, slot, mapping, or dispatch data. |
| `scripts/lib/scope-verifiers.d/NN-domain.sh` | Mode-safe downstream fragments loaded in bytewise lexical order; each file may source only its package-owned validated internal libraries through the foundation helper, then defines exact registry-pre-mapped canonical read-only pre-destroy guard wrappers and internal verifier wrappers; guard and verifier implementation libraries are distinct, and the fragment contains no public mode parsing, registration, graph, order, mode, slot, mapping, or dispatch data. |
| `scripts/lib/packages/10-foundation-access/internal/access-scopes.sh` | Existing reviewed backend/governance/EKS-access plan-and-apply behavior using shared guards and environment-local artifacts. |
| `scripts/legacy/dev/provision.sh` | Frozen current `scripts/provision.sh` implementation. |
| `scripts/legacy/dev/destroy.sh` | Frozen current `scripts/destroy.sh` implementation. |
| `scripts/legacy/dev/verify-platform-health.sh` | Frozen current `scripts/verify-platform-health.sh` implementation. |
| `scripts/provision.sh` | Route leading `--env` to unified orchestration; otherwise execute frozen legacy dev provision. |
| `scripts/destroy.sh` | Route leading `--env` to unified orchestration; otherwise execute frozen legacy dev destroy. |
| `scripts/verify-platform-health.sh` | Route leading `--env` to unified verification; otherwise execute frozen legacy dev verification. |
| `scripts/provision-uat-access.sh` | Temporary compatibility wrapper forwarding old scope names to the explicit unified UAT interface. |
| `tests/environment_orchestration/helpers.py` | Private repository fixture, subprocess helper, and command-logging mocks. |
| `tests/environment_orchestration/test_environment_contract.py` | Parser, schema, immutable-value, file-mode, and no-execution tests. |
| `tests/environment_orchestration/test_guards_and_paths.py` | Override, account/Region/context, backend key, path, lock, and cleanup tests. |
| `tests/environment_orchestration/test_scope_registry.py` | Full catalog, graph, ordering, immutable pre-destroy guard mapping, pre-resolution, and stub failure tests. |
| `tests/environment_orchestration/test_entrypoints.py` | Explicit parser, legacy preservation, and no-UAT-to-legacy routing tests. |
| `tests/environment_orchestration/test_destroy_evidence.py` | Canonical evidence bytes/schema/path/mode, callback protocol, operation binding, lifecycle status, tamper, and retention tests. |
| `tests/environment_orchestration/test_access_dispatch.py` | Mocked access ordering, saved-plan, cleanup, compatibility-wrapper, and failure-boundary tests. |
| `tests/environment_orchestration/test_static_boundary.py` | Static prohibition of legacy calls, cross-environment paths, and unimplemented platform/data/Boomi handlers. |
| `docs/operations/imported-code-review-matrix.md` | Canonical stable source-to-target classification ledger for every imported-code candidate. |
| `scripts/validate-imported-code-review-matrix.py` | Foundation-owned standard-library validator and sole parser for the canonical matrix schema, IDs, dispositions, evidence, and status. |
| `tests/environment_orchestration/test_imported_code_review_matrix.py` | Contract tests that import the sole foundation parser/validator and enforce no unclassified rows. |
| `.gitignore` | Ignore environment-local operator inputs and `.local/` artifacts. |

### Task 0: Establish The Canonical Imported-Code Review Matrix

**Files:**
- Create: `docs/operations/imported-code-review-matrix.md`
- Create: `scripts/validate-imported-code-review-matrix.py`
- Create: `tests/environment_orchestration/test_imported_code_review_matrix.py`

- [ ] **Step 1: Write the matrix contract test against the sole validator**

Import `parse_matrix` and `validate_rows` from the foundation validator and
exercise one canonical Markdown table with this exact stable schema:

```text
ID | Domain | Source | Target | Disposition | Evidence | Status
```

Require `ID` to match exactly `^DOMAIN-[0-9]{4}$`, beginning with
`DOMAIN-0001` and increasing without gaps in table order.
Require unique IDs; `Domain` to be exactly one member of the closed enum
`FOUNDATION`, `EKS`, `DATA`, `BOOMI`, `DOCS`; concrete repository-relative or
explicit external source and target identifiers; disposition in `KEEP`,
`REWRITE`, `REPLACE`, `REJECT`; non-empty evidence linking a review artifact,
test, source location, or rationale; and status in `PROPOSED`, `REVIEWED`,
`VERIFIED`. Reject `UNCLASSIFIED`, `TBD`, `TODO`, blank cells, angle-bracket
placeholders, duplicate source/target decisions, and unknown columns.

- [ ] **Step 2: Create the ledger and validator**

The document declares `docs/operations/imported-code-review-matrix.md` the
only canonical matrix. Source repositories are read-only. Every script,
Terraform module/resource, manifest, Helm value, configuration value, and
generated-file behavior considered for import gets one stable row even when
rejected. Later work packages append rows or advance `Status`; they do not
create domain-specific matrices or change the seven-column schema.

The foundation Python standard-library validator is the sole parser of this
matrix and exposes `parse_matrix(path)` and
`validate_rows(rows)`, reports every row error in one pass, and exits non-zero
on any contract violation. It is the sole validator of the closed Domain enum
`FOUNDATION`, `EKS`, `DATA`, `BOOMI`, `DOCS`; downstream inventories and gates
reuse its parsed/validated rows and may not maintain or widen another domain
list. The initial ledger records all imported items
already considered by the access foundation. It contains no synthetic
placeholder rows. Tests, inventories, and downstream gates must import or
invoke this validator; they must not implement another Markdown-table parser.

- [ ] **Step 3: Define the UAT classification gate**

Before any UAT plan, apply, lifecycle test, or acceptance plan is separately
authorized, the validator must pass and every candidate discovered by the
owning work-package inventory must have one matrix row with `Status` equal to
`REVIEWED` or `VERIFIED`. `PROPOSED` is allowed during implementation review
but blocks that UAT gate. There is never an `UNCLASSIFIED` row: discovery of an
unclassified item fails validation/inventory comparison until a concrete
disposition and evidence are reviewed.

- [ ] **Step 4: Run only when execution is separately authorized - validate the matrix contract**

```bash
python3 -m unittest tests.environment_orchestration.test_imported_code_review_matrix -v
python3 scripts/validate-imported-code-review-matrix.py docs/operations/imported-code-review-matrix.md
```

Expected: tests PASS and the validator reports the reviewed-row count with no
unclassified, malformed, or duplicate rows.

- [ ] **Step 5: Run only when commit execution is separately authorized - commit the matrix foundation**

```bash
git add docs/operations/imported-code-review-matrix.md \
  scripts/validate-imported-code-review-matrix.py \
  tests/environment_orchestration/test_imported_code_review_matrix.py
git commit -m "docs: establish imported-code review matrix"
```

Expected: one commit containing only the matrix, validator, and contract test.

### Task 1: Add The Closed Dev And UAT Environment Parser

**Files:**
- Create: `tests/environment_orchestration/__init__.py`
- Create: `tests/environment_orchestration/helpers.py`
- Create: `tests/environment_orchestration/test_environment_contract.py`
- Create: `config/environment-schema/base.manifest`
- Create: `config/environment-schema/fragments/README.md`
- Create: `config/environments/dev.env`
- Modify: `config/environments/uat.env`
- Create: `scripts/lib/environment-contracts.sh`
- Modify: `scripts/lib/platform-env.sh`

- [ ] **Step 1: Write parser tests that prove dotenv files are data, not shell**

Create a fixture helper that copies only requested files into a temporary
repository and invokes Bash with every infrastructure executable replaced by a
mock that exits `97` after logging its name:

```python
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class RepositoryFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repository"
        self.mock_bin = Path(self.temporary.name) / "bin"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.mock_bin.mkdir(parents=True)
        for command in ("aws", "kubectl", "terraform", "kustomize"):
            path = self.mock_bin / command
            path.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '{command} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
                "exit 97\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def copy(self, *relative_paths):
        for relative in relative_paths:
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def run_bash(self, script, extra_env=None):
        environment = os.environ.copy()
        environment.update({
            "PATH": f"{self.mock_bin}:{environment['PATH']}",
            "MOCK_COMMAND_LOG": str(self.command_log),
        })
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            ["bash", "-c", script], cwd=self.root, env=environment,
            text=True, capture_output=True,
        )

    def tearDown(self):
        self.temporary.cleanup()
```

In `test_environment_contract.py`, copy the parser, immutable-contract library,
and both environment files. Add tests for both successful environments and
for every prohibited dotenv construct:

```python
class EnvironmentContractTests(RepositoryFixture):
    def setUp(self):
        super().setUp()
        self.copy(
            "scripts/lib/platform-env.sh",
            "scripts/lib/environment-contracts.sh",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )

    def load(self, environment):
        return self.run_bash(
            'source scripts/lib/platform-env.sh && '
            f'load_platform_env {environment} && '
            "printf '%s|%s|%s|%s\\n' \"$ENVIRONMENT\" "
            '"$EXPECTED_AWS_ACCOUNT_ID" "$AWS_REGION" "$PROMOTION_MODE"'
        )

    def test_exact_dev_and_uat_contracts_load_without_commands(self):
        expected = {
            "dev": "dev|815402439714|ap-east-1|modeled\n",
            "uat": "uat|672172129937|ap-east-1|uat-build\n",
        }
        for environment, output in expected.items():
            with self.subTest(environment=environment):
                result = self.load(environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, output)
                self.assertFalse(self.command_log.exists())

    def test_rejects_shell_syntax_without_executing_it(self):
        uat = self.root / "config/environments/uat.env"
        original = uat.read_text(encoding="utf-8")
        cases = {
            "quoted": 'AWS_REGION="ap-east-1"',
            "command substitution": "AWS_REGION=$(touch exploited)",
            "backticks": "AWS_REGION=`touch exploited`",
            "export": "export AWS_REGION=ap-east-1",
            "inline comment": "AWS_REGION=ap-east-1 # wrong",
            "escape": r"AWS_REGION=ap-east-1\\x",
            "semicolon": "AWS_REGION=ap-east-1; touch exploited",
        }
        for label, replacement in cases.items():
            with self.subTest(label=label):
                uat.write_text(
                    original.replace("AWS_REGION=ap-east-1", replacement),
                    encoding="utf-8",
                )
                result = self.load("uat")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid dotenv assignment", result.stderr)
                self.assertFalse((self.root / "exploited").exists())
                uat.write_text(original, encoding="utf-8")
```

Also add exact tests for blank lines/comments, trimming unquoted values,
duplicate keys, unknown keys, missing keys, malformed key names, unresolved
`<example>` values, multiline attempts, symlink files, non-regular files,
group/world-writable files, a config `ENVIRONMENT` that differs from the
requested environment, wrong immutable account/Region/promotion/state prefix,
and unknown requested environments. Each failure must occur with an empty
command log. Add fragment tests proving a downstream manifest can add a key
and validator without editing `platform-env.sh`, lexical fragment order is
deterministic, duplicate key declarations fail, unknown validator names fail,
and omission of a fragment-declared required key fails.

- [ ] **Step 2: Run only when execution is separately authorized - prove the parser tests fail**

```bash
python3 -m unittest tests.environment_orchestration.test_environment_contract -v
```

Expected: FAIL because `dev.env`, `environment-contracts.sh`, and the closed
parser do not exist yet, and because the current parser sources `uat.env`.

- [ ] **Step 3: Define the foundation manifest and exact work-package 1-2 values**

Use a non-executable, pipe-delimited declarative manifest grammar. Key rows are:

```text
KEY|required|validator|immutable-key-or--
```

Cross-key constraint rows are:

```text
@constraint|predicate|KEY[,KEY...]|argument-or--
```

Blank lines and leading `#` comments are allowed; all other lines require four
fields. `validator` must name a built-in generic validator implemented by the
foundation: `environment`, `account-id`, `region`, `dns-label`, `s3-bucket`,
`state-prefix`, `state-key`, `promotion-mode`, `nonempty`, `enum:<value,...>`,
`fixed:<value>`, `integer:<min>:<max>`, or `ipv4-cidr`. Enum and fixed values
must themselves satisfy the closed metadata-token grammar; numeric bounds are
base-10 integers with `min <= max`. The foundation also implements only these
declarative cross-key predicates: `integer-order` for the listed keys in
nondecreasing order, `cidr-contained-by` for a child and parent key, and
`cidr-nonoverlap` for two or more CIDR keys. Constraint rows may reference only
keys declared by the fully composed schema, cannot execute code or name a
function, and are evaluated after all individual values validate but before
export. Unknown validators, predicates, arguments, or key references fail
closed. The final key-row field binds immutable values to
`environment-contracts.sh`; `-` means configurable.
The parser loads `base.manifest`, then every regular non-symlink
`fragments/*.manifest` in bytewise lexical order. The composed manifest is the
closed schema. Duplicate declarations, malformed rows, unsafe metadata, or
unknown validators fail before environment values are exported.

Use this exact key set and order in both files:

```dotenv
ENVIRONMENT=uat
EXPECTED_AWS_ACCOUNT_ID=672172129937
AWS_REGION=ap-east-1
TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937
TF_STATE_REGION=ap-east-1
TF_STATE_PREFIX=oms/uat
EKS_CLUSTER_NAME=EKS-boomi-runtime-cluster
BOOMI_NAMESPACE=boomi-uat
MONGODB_NAMESPACE=mongodb-uat
SIGNOZ_NAMESPACE=signoz-uat
SUPPORT_NAMESPACE=oms-support-uat
ACCESS_GOVERNANCE_STATE_KEY=oms/uat/access-governance.tfstate
EKS_PLATFORM_STATE_KEY=oms/uat/eks-platform.tfstate
EKS_ACCESS_STATE_KEY=oms/uat/eks-access.tfstate
WORKLOAD_IDENTITY_STATE_KEY=oms/uat/workload-identity.tfstate
MONGODB_STATE_KEY=oms/uat/mongo.tfstate
POSTGRESQL_CORE_STATE_KEY=oms/uat/postgresql-core.tfstate
POSTGRESQL_BRAND_STATE_KEY=oms/uat/postgresql-brand.tfstate
SIGNOZ_OBSERVABILITY_STATE_KEY=oms/uat/signoz-observability.tfstate
PROMOTION_MODE=uat-build
```

Use the same keys for dev with these exact values:

```dotenv
ENVIRONMENT=dev
EXPECTED_AWS_ACCOUNT_ID=815402439714
AWS_REGION=ap-east-1
TF_STATE_BUCKET=sml-oms-dev-tfstate
TF_STATE_REGION=ap-east-1
TF_STATE_PREFIX=oms/dev
EKS_CLUSTER_NAME=EKS-boomi-runtime-cluster
BOOMI_NAMESPACE=boomi
MONGODB_NAMESPACE=mongodb
SIGNOZ_NAMESPACE=signoz
SUPPORT_NAMESPACE=oms-support
ACCESS_GOVERNANCE_STATE_KEY=oms/dev/access-governance.tfstate
EKS_PLATFORM_STATE_KEY=oms/dev/eks-platform.tfstate
EKS_ACCESS_STATE_KEY=oms/dev/eks-access.tfstate
WORKLOAD_IDENTITY_STATE_KEY=oms/dev/workload-identity.tfstate
MONGODB_STATE_KEY=oms/dev/mongo.tfstate
POSTGRESQL_CORE_STATE_KEY=oms/dev/postgresql-core.tfstate
POSTGRESQL_BRAND_STATE_KEY=oms/dev/postgresql-brand.tfstate
SIGNOZ_OBSERVABILITY_STATE_KEY=oms/dev/signoz-observability.tfstate
PROMOTION_MODE=modeled
```

These unified dev state keys are modeling targets only. They do not adopt,
move, initialize, or reinterpret legacy `oms/dev/pg.tfstate` or any existing
state. The later dev-adoption plan owns that mapping. Preserve the existing dev
namespace contract exactly: `BOOMI_NAMESPACE=boomi`; no plan may introduce
`boomi-dev`.

- [ ] **Step 4: Compile immutable constants independently from editable dotenv values**

Implement `immutable_environment_value <env> <key>` as a `case` statement.
It must return constants for account, Region, backend Region, state prefix,
promotion mode, and UAT role prefixes. For example:

```bash
immutable_environment_value() {
  local environment_name="${1:-}"
  local key_name="${2:-}"
  case "${environment_name}:${key_name}" in
    dev:EXPECTED_AWS_ACCOUNT_ID) printf '%s\n' '815402439714' ;;
    dev:AWS_REGION|dev:TF_STATE_REGION) printf '%s\n' 'ap-east-1' ;;
    dev:TF_STATE_PREFIX) printf '%s\n' 'oms/dev' ;;
    dev:PROMOTION_MODE) printf '%s\n' 'modeled' ;;
    uat:EXPECTED_AWS_ACCOUNT_ID) printf '%s\n' '672172129937' ;;
    uat:AWS_REGION|uat:TF_STATE_REGION) printf '%s\n' 'ap-east-1' ;;
    uat:TF_STATE_PREFIX) printf '%s\n' 'oms/uat' ;;
    uat:PROMOTION_MODE) printf '%s\n' 'uat-build' ;;
    uat:INFRA_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATInfraAdminEA_' ;;
    uat:APPLICATION_DEVELOPER_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATApplicationDeveloper_' ;;
    uat:BOOMI_ADMIN_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATBoomiAdmin_' ;;
    uat:PROCESS_OWNER_ROLE_PREFIX) printf '%s\n' 'AWSReservedSSO_UATBoomiProcessOwner_' ;;
    *) return 1 ;;
  esac
}
```

Do not read these constants from process environment variables or dotenv.

- [ ] **Step 5: Replace `source` with a Bash 3.2-compatible manifest-driven closed parser**

`platform-env.sh` must generically compose the declarative manifests, reject
unsafe file metadata before reading, parse environment values with
`while IFS= read -r line || [[ -n "$line" ]]`, store values using prefixed
shell variables after validating keys, reject duplicates, compare observed
keys against the composed schema, dispatch only built-in validator names, and
compare immutable bindings to `environment-contracts.sh`. Parser logic must
contain no list of downstream keys. Only after all checks pass may it export
values.

Use this assignment grammar and explicit content rejection:

```bash
if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*)=([^\"\'\`\\\;\&\|\<\>\(\)\{\}\#]*)$ ]]; then
  _platform_env_error "invalid dotenv assignment at ${environment_file}:${line_number}"
  return 1
fi
key_name="${BASH_REMATCH[1]}"
value="${BASH_REMATCH[2]}"
value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -n "$value" ]] || {
  _platform_env_error "empty value for ${key_name}"
  return 1
}
```

The value character class excludes `"`, `'`, `` ` ``, `\`, `;`, `&`, `|`, `<`,
`>`, `(`, `)`, `{`, `}`, and `#`. This single regex is the sole rejection gate
for command substitution (`$(...)`), parameter expansion (`${...}`),
backticks, inline comments, and angle-bracket placeholders such as
`<example>`: every one of those constructs contains at least one excluded
character, so no separate post-hoc `case "$value" in *'$('*|...)` check is
reachable or needed. Do not add one — it would be dead code that can silently
drift out of sync with the regex (this exact drift was found and fixed during
Task 1 implementation, where an earlier draft of this regex omitted `#`,
making the inline-comment test case fall through to a second, unreachable
check). If the regex's excluded-character set ever changes, immediately
verify by inspection that nothing downstream still assumes a second check
fires for any of these constructs.

Do not use `eval`, `source`, `declare -g`, associative arrays, or process
substitution that hides loop assignments in a subshell. Bash 3.2 compatibility
is required on macOS.

- [ ] **Step 6: Run only when execution is separately authorized - verify parser behavior and syntax**

```bash
python3 -m unittest tests.environment_orchestration.test_environment_contract -v
bash -n scripts/lib/environment-contracts.sh scripts/lib/platform-env.sh
```

Expected: all parser tests PASS, both syntax checks exit `0`, unsafe fixtures
produce no command-log entries, and no fixture creates `exploited`.

- [ ] **Step 7: Statically review the closed contract; run the commit only when execution is separately authorized**

Review with editor search that `platform-env.sh` contains no `source
"$environment_file"`, `eval`, or `declare -A`, and that both dotenv files have
identical key sets. Then create the task commit:

```bash
git add config/environment-schema config/environments/dev.env config/environments/uat.env \
  scripts/lib/environment-contracts.sh scripts/lib/platform-env.sh \
  tests/environment_orchestration
git commit -m "feat: add closed environment contracts"
```

Expected: one commit containing only the listed parser/config/test files.

### Task 2: Generalize Shared Guards And Environment-Qualified Local State

**Files:**
- Create: `tests/environment_orchestration/test_guards_and_paths.py`
- Create: `scripts/lib/platform-guards.sh`
- Create: `scripts/lib/orchestration-paths.sh`
- Modify: `scripts/lib/platform-env.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write mocked guard and path-isolation tests**

Use a private fixture with command-specific `aws` and `kubectl` mocks. Add
tests proving:

1. Every prohibited execution override is rejected before any command or file mutation.
2. `AWS_IGNORE_CONFIGURED_ENDPOINT_URLS=true` is forced for allowed child commands.
3. STS account and configured Region must exactly match the selected contract.
4. The canonical cluster reference, not the context label, controls Kubernetes acceptance.
5. EKS authentication accepts only `API` and `API_AND_CONFIG_MAP`.
6. Backend bucket, Region, expected owner, and selected state key come only from the loaded contract.
7. `.local/dev` and `.local/uat` plans, generated inputs, locks, logs, and evidence never overlap.
8. A lock for one environment does not block the other; a second lock for the same environment fails.
9. Cleanup removes only registered artifacts beneath the selected environment and preserves the original failure status.

Use exact override cases:

```python
FORBIDDEN_OVERRIDES = {
    "AWS_ENDPOINT_URL": "",
    "AWS_ENDPOINT_URL_S3": "https://invalid.example",
    "AWS_S3_ENDPOINT": "https://invalid.example",
    "AWS_STS_ENDPOINT": "https://invalid.example",
    "AWS_CA_BUNDLE": "/tmp/invalid-ca.pem",
    "AWS_CONFIG_FILE": "/tmp/invalid-aws-config",
    "AWS_SHARED_CREDENTIALS_FILE": "/tmp/invalid-credentials",
    "AWS_PROFILE": "other",
    "AWS_DEFAULT_PROFILE": "other",
    "AWS_REGION": "us-east-1",
    "AWS_DEFAULT_REGION": "us-east-1",
    "KUBECONFIG": "/tmp/invalid-kubeconfig",
    "TF_CLI_CONFIG_FILE": "/tmp/invalid.tfrc",
    "TF_PLUGIN_CACHE_DIR": "/tmp/plugins",
    "TF_REATTACH_PROVIDERS": "{}",
    "TF_CLI_ARGS": "-destroy",
    "TF_CLI_ARGS_plan": "-destroy",
    "TF_VAR_expected_account_id": "000000000000",
    "TF_WORKSPACE": "other",
    "TF_DATA_DIR": "/tmp/terraform-data",
}
```

For path assertions, require exact results:

```python
self.assertEqual(paths["LOCAL_ROOT"], self.root / ".local" / "uat")
self.assertEqual(paths["LOCK_DIR"], self.root / ".local" / "uat" / "locks" / "orchestration.lock")
self.assertEqual(paths["PLAN_DIR"], self.root / ".local" / "uat" / "plans")
self.assertEqual(paths["GENERATED_DIR"], self.root / ".local" / "uat" / "generated")
self.assertEqual(paths["EVIDENCE_DIR"], self.root / ".local" / "uat" / "evidence")
self.assertNotIn(str(self.root / ".local" / "dev"), "\n".join(map(str, paths.values())))
```

- [ ] **Step 2: Run only when execution is separately authorized - prove guard/path tests fail**

```bash
python3 -m unittest tests.environment_orchestration.test_guards_and_paths -v
```

Expected: FAIL because the shared guard and path libraries do not exist.

- [ ] **Step 3: Implement execution, identity, Region, context, and backend guards**

Move the override rejection logic out of `provision-uat-access.sh` and expand
it to the exact list above. `reject_execution_environment_overrides` must run
before loading config or creating `.local/`. Keep inherited `PATH`, terminal,
locale, and ordinary AWS credential-process/session variables; reject only
values that can redirect account/profile/endpoint/Region/Kubernetes/Terraform
behavior.

Implement these functions with no top-level execution:

```bash
reject_execution_environment_overrides
verify_aws_identity_and_region
verify_kubernetes_context
verify_eks_authentication_mode
validate_backend_contract_for_scope
```

`verify_aws_identity_and_region` must call STS once and use
`aws configure get region` only as a consistency check when it returns a
non-empty value. Child AWS commands receive `--region "$AWS_REGION"` where the
CLI supports it. `validate_backend_contract_for_scope` must obtain the state
key from the registry mapping and reject keys outside `${TF_STATE_PREFIX}/`,
keys containing `..`, and unknown scopes before invoking the existing backend
bootstrap.

`platform-env.sh` currently still contains the legacy, UAT-only
`verify_aws_identity`, `verify_kubernetes_context`, `verify_eks_authentication_mode`,
and their `_validate_uat_contract`/`_validate_required_platform_env` helpers
(intentionally left unchanged by Task 1, whose scope was the parser only).
`platform-env.sh`'s Canonical Foundation Ownership contract is generic dotenv
parsing and schema validation only — it must not also own identity/context/
authentication guards once `platform-guards.sh` exists. This task must
therefore also modify `scripts/lib/platform-env.sh` to remove
`verify_aws_identity`, `verify_kubernetes_context`,
`verify_eks_authentication_mode`, `_validate_uat_contract`, and
`_validate_required_platform_env` entirely, migrating their checks into the
generalized dev+uat-capable equivalents (`verify_aws_identity_and_region`,
`verify_kubernetes_context`, `verify_eks_authentication_mode`) implemented in
the new `scripts/lib/platform-guards.sh`. Any caller of the old names
(currently none outside `platform-env.sh` itself) must be updated in the same
commit. After this task, `platform-env.sh` contains no `verify_*` guard
function and no UAT-only contract check.

- [ ] **Step 4: Implement environment-local paths, ownership, locks, and cleanup**

`initialize_orchestration_paths` computes paths from repository root and the
validated `ENVIRONMENT`; it accepts no path override. Create directories with
`umask 077` and verify each component from repository root through `.local`
and the environment directory is a real directory, not a symlink. Use:

```text
.local/<env>/locks/orchestration.lock
.local/<env>/plans/<scope>.<pid>.tfplan
.local/<env>/generated/eks-access.<pid>.auto.tfvars.json
.local/<env>/logs/
.local/<env>/evidence/
config/environments/<env>.local/workforce-principals.json
```

All checked-in local-input examples use the canonical layout
`config/environments/<env>.local/*.json.example`. Never use
`config/environments/*.example`, `config/environments/examples/`, or a
component-specific local-example root. Runtime `.json` siblings are ignored;
`.json.example` files are tracked and contain no credentials or real ARNs.

The lock is a directory created atomically with `mkdir`; cleanup removes it
with `rmdir`. Track active plan/generated paths in indexed Bash arrays, reject
registration outside `.local/${ENVIRONMENT}/`, attempt every cleanup action,
and return the original non-zero command status in preference to cleanup
errors. On an otherwise successful run, cleanup failure makes the command
fail.

- [ ] **Step 5: Ignore all local contracts and generated state**

Replace only the two UAT-specific ignore lines
(`config/environments/uat-workforce-principals.json` and
`platform-prerequisites/terraform/eks-access/generated.auto.tfvars.json`) with:

```gitignore
# Operator-local environment inputs and generated orchestration state
config/environments/*.local/
.local/
```

Keep every other existing `.gitignore` entry untouched, including the legacy
dev escrow ignores, the Terraform-local ignores, the `# Other` section
(`docs/operations/command-log.md`, `.worktrees/`, `*.bak`), and any general
hygiene entry such as `__pycache__/`. This step only narrows the UAT-specific
section; it is not a wholesale rewrite of the file.

- [ ] **Step 6: Run only when execution is separately authorized - verify shared guards and paths**

```bash
python3 -m unittest tests.environment_orchestration.test_guards_and_paths -v
bash -n scripts/lib/platform-guards.sh scripts/lib/orchestration-paths.sh
```

Expected: all tests PASS; wrong account/Region/context and every override stop
before backend or local mutation; dev and UAT lock/path tests are independent.

- [ ] **Step 7: Statically review shared safety behavior; run the commit only when execution is separately authorized**

Confirm every removal target passes the `.local/${ENVIRONMENT}/` containment
check and no library honors external variables for repository paths. Commit:

```bash
git add .gitignore scripts/lib/platform-guards.sh \
  scripts/lib/orchestration-paths.sh \
  tests/environment_orchestration/test_guards_and_paths.py
git commit -m "feat: add shared environment safety guards"
```

Expected: one commit containing only shared guards, path handling, ignores,
and their mocked tests.

### Task 3: Define The Permanent Unified Scope Registry And Fail-Closed Graph

**Files:**
- Create: `tests/environment_orchestration/test_scope_registry.py`
- Create: `scripts/lib/scope-registry.sh`

- [ ] **Step 1: Write exact catalog, dependency, and ordering tests**

Assert the provision catalog is exactly:

```python
EXPECTED_SCOPES = (
    "backend",
    "eks-platform",
    "access-governance",
    "eks-access",
    "platform-controllers",
    "boomi-runtime",
    "mongodb",
    "postgresql-core",
    "postgresql-brand",
    "mongodb-access",
    "database-access-core",
    "database-access-brand",
    "workload-identity",
    "signoz",
    "signoz-observability",
    "all",
)
```

Assert the provision dependency graph is exactly:

```python
EXPECTED_DEPENDENCIES = {
    "backend": (),
    "access-governance": ("backend",),
    "eks-platform": ("backend",),
    "eks-access": ("eks-platform",),
    "platform-controllers": ("eks-platform",),
    "workload-identity": ("eks-platform",),
    "boomi-runtime": ("eks-platform", "platform-controllers", "workload-identity"),
    "mongodb": ("eks-platform", "platform-controllers"),
    "postgresql-core": ("eks-platform",),
    "postgresql-brand": ("eks-platform",),
    "mongodb-access": ("mongodb",),
    "database-access-core": ("postgresql-core",),
    "database-access-brand": ("postgresql-brand",),
    "signoz": ("eks-platform", "platform-controllers"),
    "signoz-observability": ("signoz",),
}
```

The deterministic final `all` order must match the approved design and is
immutable after this foundation lands:

```python
EXPECTED_ALL_ORDER = (
    "backend", "access-governance", "eks-platform", "eks-access",
    "workload-identity", "platform-controllers", "boomi-runtime", "mongodb",
    "postgresql-core", "postgresql-brand", "mongodb-access",
    "database-access-core", "database-access-brand", "signoz",
    "signoz-observability",
)
```

Assert ordinary reverse destroy excludes `backend` and
`access-governance`, and equals:

```python
EXPECTED_DESTROY_ALL_ORDER = (
    "signoz-observability", "signoz", "boomi-runtime", "mongodb-access",
    "database-access-brand", "database-access-core", "mongodb",
    "postgresql-brand", "postgresql-core", "workload-identity",
    "platform-controllers", "eks-access", "eks-platform",
)
```

Add tests for cycle detection, unknown dependencies, duplicate resolution,
unknown scope rejection, `verification` rejection as a provision/destroy
scope, exact provision/destroy/pre-destroy-guard/verifier symbol mappings,
missing required symbols, non-function symbols, fragment attempts to define
unassigned names, and full graph pre-resolution. Assert every scope in
`EXPECTED_DESTROY_ALL_ORDER` has exactly one canonical
`pre_destroy_guard_for_scope` mapping, no pseudo-scope or downstream fragment
can add one, and selected destroy pre-resolution fails closed on an absent
mapped guard symbol before `.local/` creation or command execution. The
decisive provision test is that `all` reports
`eks-platform requires work package 3` with an empty handler command log;
neither `backend` nor `access-governance` may run before the unsupported graph
is rejected.

- [ ] **Step 2: Run only when execution is separately authorized - prove registry tests fail**

```bash
python3 -m unittest tests.environment_orchestration.test_scope_registry -v
```

Expected: FAIL because `scope-registry.sh` does not exist.

- [ ] **Step 3: Implement the registry as shell data and pure lookup functions**

Use readonly indexed arrays and `case` lookups, not executable external config
or associative arrays. Export functions:

```bash
list_provision_scopes
dependencies_for_scope
provision_handler_for_scope
destroy_handler_for_scope
pre_destroy_guard_for_scope
verification_handler_for_slot
verification_slots_for_mode
state_key_variable_for_scope
implementation_requirement_for_scope
resolve_provision_order
resolve_destroy_order
resolve_verification_order
dispatch_scope_handler
```

Dependencies, state mappings, and all orders are immutable registry data.
Provision, destroy, read-only pre-destroy guard, and internal verifier symbol
mappings are immutable registry data initialized to canonical fail-unavailable
foundation functions. Every canonical scope admitted to ordinary destroy has
one required guard mapping even when its downstream implementation is absent.
Numbered fragments may define only the mapped canonical symbols owned by their
domain; they do not register slots, modify this file, add a second registry,
or special-case a scope or verification mode in `orchestrator.sh`.

The public verifier modes map exactly as follows: `--preflight` selects the
foundation contract, AWS identity/Region, and optional canonical Kubernetes
readiness slots; `--full` (including the exact no-flag default) selects all
preflight slots followed by every component verifier slot in provision
dependency order; `--smoke-test` selects all full slots followed by immutable
cross-component smoke slots. Component verifier slots are internal names only
and are never accepted as public CLI values. `resolve_verification_order`
deduplicates shared dependencies while preserving registry order.

Handler status is exact:

| Scope | Provision handler in this plan | Destroy handler in this plan |
|---|---|---|
| `backend` | canonical `foundation_provision_backend` supplied by foundation access fragment | canonical blocked break-glass function |
| `access-governance` | canonical `foundation_provision_access_governance` supplied by foundation access fragment | canonical blocked retained-control function |
| `eks-access` | canonical `foundation_provision_eks_access` supplied by foundation access fragment | canonical work-package 3 dependency function |
| every other narrow scope | explicit owning-work-package failure | explicit owning-work-package failure |
| `all` | graph expansion only | reverse graph expansion only |

Although the existing EKS access implementation exists, unified `eks-access`
depends on `eks-platform`; permit narrow provisioning only after a
`verify_existing_eks_platform_dependency` handler proves canonical cluster
identity and API authentication mode. Represent this as the dependency status
`external-existing-platform` in work package 2; do not pretend this plan owns
or provisions EKS platform.

Map deferred work packages exactly:

```text
eks-platform -> work package 3
platform-controllers -> work package 3
workload-identity -> work package 3
mongodb -> work package 4
postgresql-core -> work package 4
postgresql-brand -> work package 4
mongodb-access -> work package 4
database-access-core -> work package 4
database-access-brand -> work package 4
signoz -> work package 4
signoz-observability -> work package 4
boomi-runtime -> work package 5
```

- [ ] **Step 4: Run only when execution is separately authorized - verify registry purity and graph results**

```bash
python3 -m unittest tests.environment_orchestration.test_scope_registry -v
bash -n scripts/lib/scope-registry.sh
```

Expected: all tests PASS; `all` resolves deterministically but refuses to
dispatch because work packages 3-5 are absent; ordinary destroy excludes
backend and governance, and every remaining destroy scope has an immutable
mapped pre-destroy guard symbol.

- [ ] **Step 5: Statically review the registry; run the commit only when execution is separately authorized**

Confirm every catalog scope appears exactly once, every dependency is a known
narrow scope, and no deferred scope maps to a command that invokes Terraform,
AWS, kubectl, or a legacy script. Commit:

```bash
git add scripts/lib/scope-registry.sh \
  tests/environment_orchestration/test_scope_registry.py
git commit -m "feat: define unified scope registry"
```

Expected: one commit containing the registry and graph tests only.

### Task 4: Add Explicit Unified Entrypoints Without Changing Legacy Dev Behavior

**Files:**
- Create: `tests/environment_orchestration/test_entrypoints.py`
- Create: `scripts/legacy/dev/provision.sh`
- Create: `scripts/legacy/dev/destroy.sh`
- Create: `scripts/legacy/dev/verify-platform-health.sh`
- Create: `scripts/lib/confirmation-artifact.py`
- Create: `scripts/lib/destroy-evidence.py`
- Create: `scripts/lib/orchestrator.sh`
- Create: `tests/environment_orchestration/test_destroy_evidence.py`
- Modify: `scripts/provision.sh`
- Modify: `scripts/destroy.sh`
- Modify: `scripts/verify-platform-health.sh`

- [ ] **Step 1: Freeze and test the legacy dev bodies before changing public scripts**

Copy the current three public script bodies byte-for-byte into
`scripts/legacy/dev/`. Because those scripts compute repository root relative
to their old location, make only this path correction in each frozen copy:

```bash
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
```

No other line changes. In tests, normalize that one `ROOT_DIR` line and assert
the frozen source equals the pre-wrapper source fixture stored as string
constants in the test. Also run old and frozen scripts with temporary mocked
child scripts for representative argument vectors and compare return code,
stdout, stderr, and child invocation log exactly.

Representative provision vectors:

```python
LEGACY_PROVISION_CASES = (
    ("all",), ("mongodb",), ("mongo",), ("pg", "--auto-approve"),
    ("signoz",), ("signoz-observability", "--auto-approve"),
    ("mongodb", "--bootstrap-platform-controllers"), ("unknown",),
)
```

Representative destroy vectors are `all`, `mongodb`, `mongo`, `pg`, `signoz`,
`signoz-observability`, and `unknown`; verification vectors are no arguments,
`--preflight`, `--smoke-test`, `--help`, and `--unknown`.

- [ ] **Step 2: Add explicit parser tests before implementing wrappers**

Assert all these fail before command invocation or `.local/` creation:

```python
INVALID_EXPLICIT_FORMS = (
    ("--env",),
    ("--env", "prod", "backend"),
    ("--env=uat", "backend"),
    ("backend", "--env", "uat"),
    ("--env", "uat"),
    ("--env", "uat", "--env", "dev", "backend"),
    ("--env", "uat", "unknown"),
)
```

Assert `scripts/provision.sh --env dev access-governance` and every explicit
dev provision/destroy scope fail with:

```text
ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled
```

and make no AWS/backend/Terraform/kubectl/legacy invocation. Assert unified dev
verification accepts `--preflight`, `--full` (also selected by no flag), and
`--smoke-test`. Preflight performs contract/readiness checks; full and smoke
fail closed on unavailable internal verifier symbols, not by treating
verification as mutation.

Most importantly, place executable sentinels at all three legacy paths that
exit `98`; every explicit UAT command must fail or succeed without seeing `98`
and without any `legacy/dev` entry in the command log.

For explicit destroy, assert the option parser accepts only
`--auto-approve`, exactly zero or one
`--confirmation-artifact <repository-relative-path>`, and repeatable
`--confirm <exact-value>`. Reject a missing artifact value, duplicate artifact
options, `--confirmation-artifact=<path>`, artifact options on provision or
verification, duplicate confirmation values, and every unknown option before
external commands, artifact creation, or package dispatch.

- [ ] **Step 3: Run only when execution is separately authorized - prove entrypoint tests fail**

```bash
python3 -m unittest tests.environment_orchestration.test_entrypoints -v
```

Expected: FAIL because the legacy split, orchestrator, and explicit parser do
not exist.

- [ ] **Step 4: Implement thin public compatibility wrappers**

Each wrapper makes one routing decision only. For `provision.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" != "--env" ]]; then
  exec bash "$ROOT_DIR/scripts/legacy/dev/provision.sh" "$@"
fi

# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/orchestrator.sh"
run_unified_command provision "$@"
```

Use the same shape for destroy and verification, changing only the legacy file
and operation. Do not inspect later arguments for `--env`; a non-leading flag
belongs to the unchanged legacy grammar and is rejected there as it is today.

- [ ] **Step 5: Implement orchestration parse, promotion gates, pre-resolution, and dispatch**

`run_unified_command <provision|destroy|verify> --env <dev|uat> ...` must:

1. Reject execution overrides.
2. Parse the exact leading environment form without mutation.
3. Load and validate the closed environment contract.
4. Parse scope/options or verification mode.
5. Call canonical `require_environment_mutation_authorized` for every mutating operation; it reads `PROMOTION_MODE` as the sole environment mutation gate.
6. Resolve and validate the entire graph, including every selected required
  handler, pre-destroy guard, and verifier symbol, before local path creation.
7. Initialize environment-local paths and acquire one environment lock.
8. Run operation-specific preflight and canonical `dispatch_scope_handler` in resolved order.
9. For destroy only, capture selected guard results through the exact
  five-argument foundation callback; on any failed, missing, duplicate, or
  invalid result, write the separate canonical operation-bound guard-failure
  record and stop without all-pass evidence, confirmation consumption, or
  dispatch; otherwise write and bind canonical all-pass operation evidence,
  then maintain its foundation-only lifecycle status through consume, success,
  or failure.
10. Clean plans/generated inputs/lock while preserving original failure; do
  not register durable destroy evidence or status files for ordinary temporary
  cleanup.

Before graph pre-resolution, `orchestrator.sh` validates and sources every
matching regular, non-symlink, mode-safe
`scripts/lib/scope-handlers.d/NN-domain.sh` and
`scripts/lib/scope-verifiers.d/NN-domain.sh` file in bytewise lexical order.
Reject group/world-writable files, symlinks, non-regular files, malformed
names, top-level command execution other than validated package-library
loading, graph/order/mode/slot/registry assignment, registration calls, and
definitions outside the exact immutable canonical symbol allowlist assigned
to that numbered package. There is no registration function to call. While a
fragment is active, `source_package_internal_library` accepts only a
repository-relative path beneath the matching
`scripts/lib/packages/NN-domain/internal/` directory and performs canonical
containment, regular-file, non-symlink, and group/world-writable checks before
sourcing it. Static validation rejects direct `source`/`.` statements and any
other top-level command. The fragment then defines the exact pre-mapped
canonical wrappers; internal guard and verifier libraries remain distinct and
do not define registry symbols or choose a scope/mode. After loading, the
orchestrator asks the fixed registry for every required symbol and fails closed
if any is unavailable. For destroy, this includes one mapped pre-destroy guard
for every selected destroyable canonical scope. Empty directories are valid
only while the selected graph maps to foundation placeholders, and selecting a
scope whose downstream guard symbol is absent invokes that scope's fail-closed
foundation placeholder rather than omitting the guard.

Options for unified provision are only `--auto-approve`. Options for unified
destroy are exactly `--auto-approve`, the foundation-owned destroy-only
`--confirmation-artifact <repository-relative-path>` accepted at most once,
and the separate foundation-owned destroy-only repeatable
`--confirm <exact-value>`. Each confirmation value has the colon-delimited
grammar
`destroy:<env>:<account-id>:<scope>:<resource>:<consequence>`. Components may
not contain a colon, whitespace, an empty token, or shell metacharacters; the
foundation validates this token grammar in addition to exact-value equality.
`<env>` is the selected environment, `<account-id>` is the immutable account ID
from its loaded contract, `<scope>` is the canonical persistent scope,
`<resource>` is a concrete resource identity from the loaded validated
environment configuration or platform contract, and `<consequence>` states
the retention outcome explicitly.

The immutable registry/foundation owns this closed confirmation-requirement
map and its templates; there is no downstream registration API, parser, or
template override:

| Persistent scope | Resource token | Consequence token | Exact-value example |
|---|---|---|---|
| `eks-platform` | canonical cluster identity from `EKS_CLUSTER_NAME` | `delete-cluster` | `destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster` |
| `boomi-runtime` | concrete runtime resource identity from the validated Boomi platform contract | `retain-efs` | `destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs` |
| `mongodb` | concrete MongoDB cluster identity from the validated data-platform contract | `delete-cluster-and-pvcs` | `destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs` |
| `postgresql-core` | concrete core DB cluster identity from the validated data-platform contract | `final-snapshot=<id>` | `destroy:uat:672172129937:postgresql-core:db/oms-uat-core:final-snapshot=oms-uat-core-final-20260722T120000Z` |
| `postgresql-brand` | concrete brand DB cluster identity from the validated data-platform contract | `final-snapshot=<id>` | `destroy:uat:672172129937:postgresql-brand:db/oms-uat-brand:final-snapshot=oms-uat-brand-final-20260722T120000Z` |

The first invocation without a complete confirmation set is a mandatory
preparation pass and must not include `--confirmation-artifact`; supplying an
artifact with an incomplete set is rejected as ambiguous. After environment
and account guards and complete destroy-graph resolution, the foundation
generates an unpredictable operation ID and deterministically generates each
selected PostgreSQL final snapshot identifier. It exclusively creates one
canonical JSON artifact at
`.local/<env>/generated/destroy-confirmation.<operation-id>.json` with mode
`0600`. The artifact records its schema version, operation ID, UTC creation
time, immutable UTC expiry time, selected environment, immutable account ID,
the originally requested canonical scope, the exact resolved selected scope
set in dispatch order, and the exact ordered confirmation set. The immutable
foundation lifetime is 15 minutes; an implementation or downstream package
cannot extend or override it.

Canonical JSON means UTF-8 bytes produced from a dictionary with exactly those
closed keys by `json.dumps(payload, sort_keys=True, separators=(",", ":"),
ensure_ascii=True)` plus exactly one trailing `\n`. Arrays preserve registry
dispatch order. The reader rejects duplicate keys with `object_pairs_hook`,
parses the bytes, validates the closed schema and types, reserializes with the
same algorithm, and requires byte-for-byte equality. Tests assert the exact
sorted key order, compact separators, ASCII escaping, one newline, ordered
arrays, duplicate/unknown-key rejection, and byte mismatch rejection.

Preparation prints
`Confirmation artifact: <repository-relative-path>` followed by the exact
`--confirmation-artifact <repository-relative-path>` argument and exact
repeated `--confirm` arguments required for the second invocation, exits
nonzero, and performs no infrastructure mutation or package dispatch. The
artifact write is the sole mutation permitted on the preparation pass and is
not registered for ordinary temporary-file cleanup because it must survive
that intentional nonzero exit. Exclusive creation rejects an existing path;
it never replaces a file, directory, or symlink.

Pre-destroy guards are read-only and may not create plans, generated inputs,
snapshots, backups, retention records, evidence, or any other file or remote
state. Each wrapper reports exactly one structured result through
`record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>`;
the callback has exactly these five arguments and arbitrary stdout/stderr parsing is
prohibited. The callback only records in foundation memory while that exact
scope's guard phase is active. Packages do not write evidence artifacts,
lifecycle files, confirmation artifacts, or any other foundation file.

On the first failed, missing, duplicate, or invalid guard result, the
foundation stops guard execution and exclusively writes
`.local/<env>/evidence/destroy-guard-failure.<operation-id>.json` with mode
exactly `0600` beneath the canonical real non-symlink evidence directory. This
is a separate operation-bound audit record, never the successful guard-evidence
artifact. Its closed payload contains exactly `schema_version`, `operation_id`,
`environment`, `account_id`, `requested_scope`, `resolved_scopes`,
`received_results`, `failure`, `created_at`, and
`confirmation_artifact_sha256`. `received_results` contains every callback
attempt received before abort, in arrival order, including the failing or
duplicate attempt when one exists; each object contains exactly the five
callback fields `scope`, `status`, `resource_identity`, `evidence_digest`, and
`summary_code`. A missing result adds no synthetic result. `failure` contains
exactly `code`, `expected_scope`, `guard_index`, `result_index`, and
`wrapper_status`; nullable indexes are used only when no corresponding guard or
result exists, and `code` is a closed foundation code for `FAIL`, missing,
duplicate, malformed, wrong-scope, out-of-phase, out-of-order, or
wrapper/status disagreement. The record uses the same canonical-byte,
exclusive-create, no-follow, operation/confirmation binding, and retention
rules as destroy evidence. Record creation failure is an additional
foundation failure and still cannot permit all-pass evidence, confirmation
consumption, approval, or dispatch.

After every selected guard has returned `PASS` in exact reverse destroy order,
the foundation exclusively writes
`.local/<env>/evidence/pre-destroy-guards.<operation-id>.json` with mode exactly
`0600`, using exclusive creation beneath a canonical real non-symlink evidence
directory. Its closed payload contains exactly `schema_version`,
`operation_id`, `environment`, `account_id`, `requested_scope`,
`resolved_scopes`, `guard_results`, `created_at`, `expires_at`, and
`confirmation_artifact_sha256`. `resolved_scopes` and `guard_results` preserve
the exact reverse destroy order. Each guard-result object contains exactly
`scope`, `status`, `resource_identity`, `evidence_digest`, and `summary_code`.
The operation ID, environment, immutable account, requested scope, and ordered
resolved scopes must equal the validated confirmation artifact and current
request. `confirmation_artifact_sha256` is the lowercase SHA-256 of the exact
canonical confirmation-artifact bytes read from the validated no-follow
descriptor. Evidence timestamps use the foundation clock; expiry equals the
confirmation artifact's immutable expiry so evidence can never authorize a
longer operation window.

Evidence JSON uses the same canonical byte algorithm as confirmation JSON:
closed dictionaries, duplicate-key rejection, sorted keys, compact separators,
ASCII escaping, and exactly one trailing newline. The helper exclusively
creates, reopens, and byte-for-byte validates the artifact, then returns its
`sha256:<lowercase-hex>` digest to the orchestrator. No approval prompt,
confirmation consumption, backend/bootstrap action, generated plan/input,
infrastructure mutation, or package dispatch occurs before this successful
write and validation. Any failed, missing, duplicate, or invalid guard result
writes only its separate guard-failure record, never this all-pass artifact,
and leaves the confirmation artifact unconsumed without approval or dispatch.
Any all-pass evidence-write failure also leaves the confirmation artifact
unconsumed and performs no dispatch.

The second pass requires `--confirmation-artifact` exactly once and the
complete repeatable confirmation set. The option value must be the exact
repository-relative path printed by preparation: absolute paths, `..`, empty
components, alternate spellings, and paths outside the canonical selected
environment's generated directory are rejected. The foundation-only
`confirmation-artifact.py` uses canonical-parent containment, `lstat`,
`os.open` with `O_NOFOLLOW`, and `fstat` on the opened descriptor to require a
foundation-owned regular non-symlink file with mode exactly `0600`; parsing
and validation use bytes read from that same descriptor so a path swap cannot
change the checked object. It rejects unknown or duplicate JSON keys,
non-canonical types/order, malformed timestamps or operation IDs, filename and
payload operation-ID disagreement, modified fields, expiry at or before the
current foundation clock, future creation times, and creation/expiry intervals
other than the immutable lifetime.

After independently resolving the current request, the foundation requires
artifact environment and account to equal the loaded immutable contract,
requested scope and exact ordered selected scope graph to equal the current
destroy request, and the artifact's exact ordered confirmation set to equal
both the freshly computed closed-map set and the CLI set. This rejects stale,
expired, replayed, cross-environment, cross-account, cross-scope,
cross-operation, missing, extra, duplicate, malformed, reordered, or
mismatched values before any handler runs. Selecting `all` requires the union
of requirements for all persistent scopes in the resolved selection, never a
literal `all` confirmation. Scopes absent from the closed map add no value.

The preparation sequence is exact: parse and validate environment; enforce
promotion authorization; verify AWS account; verify configured/current Region;
resolve the immutable destroy graph and resource identities; generate snapshot
IDs and the operation ID; exclusively write and re-read the artifact; print the
follow-up arguments; exit nonzero. The second-pass sequence is exact: repeat
environment/promotion/account/Region checks; resolve the same graph/resources;
open, parse, and validate the confirmation artifact and CLI ordered values;
activate one expected-scope capture and dispatch each registry-mapped read-only
pre-destroy guard in exact reverse destroy order; require exactly one valid
`PASS` result from every guard; on any failed, missing, duplicate, or invalid
result, exclusively write and re-read the separate canonical guard-failure
record and stop; only after the complete set passes, exclusively write and
re-read canonical all-pass guard evidence; obtain interactive approval unless
separately auto-approved;
revalidate the original confirmation bytes, expiry, and opened-file identity;
revalidate the evidence through a no-follow descriptor and bind its digest and
operation ID to the current confirmation descriptor and request; atomically
consume the confirmation artifact; atomically record evidence status
`consumed`; dispatch destroy handlers in that same reverse destroy order; then
atomically record `success`, or record `failure` with a closed foundation
failure code if any post-consumption step fails. Approval is neither requested
nor accepted for consumption until all guards pass and canonical evidence
exists. Tests assert this complete event order and that failure at every step
prevents all later events except the required foundation failure-status record
after consumption.

No backend bootstrap, generated plan/input write,
Terraform/Kubernetes mutation, or package dispatch may happen before
consumption on the second pass. Immediately before the first package dispatch,
the helper atomically renames the still-open, revalidated artifact in the same
canonical directory to
`destroy-confirmation.<operation-id>.json.consumed`; rename failure or any
identity change aborts without dispatch. The helper verifies after rename that
the consumed name still identifies the opened descriptor; mismatch is a
consumed failure and never dispatches. A consumed path is never accepted as
input and is never renamed back. A pre-consumption guard or approval failure
leaves the unconsumed artifact reusable only until its original expiry; any
failure at or after consumption leaves the consumed marker in place and a
retry requires a new preparation pass. Cleanup may remove only expired
unconsumed or consumed artifacts after repeating the same canonical
containment, no-follow descriptor, ownership, regular-file, and exact-mode
checks; cleanup failure never restores or makes a consumed operation reusable.

Destroy evidence is durable audit state, not temporary cleanup state. The
foundation writes mode-`0600` canonical sidecars named
`pre-destroy-guards.<operation-id>.status.<consumed|success|failure>.json` by
same-directory temporary-file plus atomic no-replace rename. Status payloads
bind the evidence digest, operation ID, status, and foundation timestamp;
`failure` also contains one closed foundation failure code and never package
text. Status transitions are append-only: later status files do not replace or
delete earlier ones. Ordinary orchestration cleanup never removes evidence or
status sidecars. The foundation retention helper keeps the evidence and all
status sidecars together for at least 90 days after the terminal `success` or
`failure` timestamp; an unconsumed evidence record remains until at least 90
days after expiry. Only the foundation helper may remove an expired complete
operation set, and only after canonical containment, no-follow, ownership,
regular-file, exact-mode, schema, digest, and age checks. Partial sets,
symlinks, unknown files, invalid modes, tampering, or missing terminal status
fail closed and are retained for operator review.

The artifact path and operation metadata are foundation-only and are never
passed to a package. Dispatch passes each canonical handler only its ordered
handler-specific confirmation subset, byte-for-byte unchanged from the
validated CLI values; a handler with no requirement receives an empty subset.
Packages do not generate, persist, receive, parse, normalize, synthesize, or
register confirmation artifacts or confirmations.

The evidence path, evidence digest, lifecycle files, and operation metadata are
foundation-only and are never passed to a package. Packages do not create,
persist, parse, normalize, synthesize, update, consume, or clean evidence or
status files. Their sole evidence-related capability is one valid callback
call from their active mapped read-only guard wrapper.

Each destroy handler must recheck its critical resource identity immediately
before its first mutation and abort on drift. That immediate identity recheck
is defense in depth only: it cannot replace, defer, or become the sole
retention/protection gate, and handlers cannot run unless all mapped
pre-destroy guards already passed before approval and artifact consumption.

In `tests/environment_orchestration/test_entrypoints.py`, use a deterministic
foundation clock, operation-ID source, and operation fixture to obtain the
exact canonical artifact path before preparation writes. Add parser tests and
focused preparation/replay/expiry/tamper/scope/account/environment tests,
including changed operation ID, timestamps, requested scope, ordered graph,
confirmation set, environment, and account. Precreate a symlink at the exact
path pointing outside `.local/<env>/generated/` and assert rejection before
external commands, replacement, or package dispatch; add parallel cases for a
non-regular path, wrong mode, traversal, read-time symlink/path swap, consumed
replay, and atomic-consume failure. Prove pre-consumption failures leave the
artifact reusable until expiry, post-consumption failures require a new
preparation pass, and no infrastructure/package mutation occurs before the
atomic consumed rename. These foundation tests own artifact safety;
downstream package tests receive only unchanged confirmation subsets.

In `tests/environment_orchestration/test_destroy_evidence.py`, assert exact
canonical bytes and key sets, exact all-pass evidence, guard-failure-record,
and status paths, operation and
confirmation-byte digest binding, ordered scopes/results, timestamps and
expiry, exclusive creation, owner-only mode `0600`, no-follow descriptor reads,
and symlink/non-regular/path-swap rejection. Exercise callback calls outside an
active phase, wrong scope, malformed tokens, missing calls, duplicate calls,
out-of-order calls, wrapper/status disagreement, and arbitrary stdout that must
not become evidence. For each `FAIL`, missing, duplicate, malformed,
wrong-scope, out-of-phase, out-of-order, and wrapper/status-disagreeing case,
assert one separate canonical mode-`0600` operation-bound
`destroy-guard-failure.<operation-id>.json` record with exact ordered received
results and closed failure metadata; assert no all-pass evidence, approval,
confirmation consumption, or dispatch. Tamper the confirmation, evidence,
failure record, digest, operation ID,
ordered results, status, and mode between each lifecycle boundary and prove
failure before consumption or dispatch. Assert atomic consumed/success/failure
status creation, append-only transitions, 90-day minimum retention, and
fail-closed cleanup for incomplete or invalid operation sets.

`--confirmation-artifact` and `--confirm` never imply `--auto-approve`, and
`--auto-approve` never supplies or bypasses either confirmation requirement.
No option can bypass environment/promotion, AWS
account/Region, backend, Kubernetes context, interactive approval, retention,
or resource-protection gates; confirmation is necessary but never sufficient,
and a canonical handler may still refuse ordinary destroy. Verification accepted forms are
exactly `--preflight`, `--full`, no mode flag (exactly equivalent to
`--full`), and `--smoke-test`, with immutable internal verifier slots and no
downstream mode registration. Reject legacy-only
`--bootstrap-platform-controllers` and `--keep-signoz-namespace` in explicit
mode because their target scopes are not implemented in this foundation.

- [ ] **Step 6: Run only when execution is separately authorized - verify routing and legacy parity**

```bash
python3 -m unittest tests.environment_orchestration.test_entrypoints -v
python3 -m unittest tests.environment_orchestration.test_destroy_evidence -v
python3 -m py_compile scripts/lib/confirmation-artifact.py
python3 -m py_compile scripts/lib/destroy-evidence.py
bash -n scripts/provision.sh scripts/destroy.sh \
  scripts/verify-platform-health.sh scripts/lib/orchestrator.sh \
  scripts/legacy/dev/provision.sh scripts/legacy/dev/destroy.sh \
  scripts/legacy/dev/verify-platform-health.sh
```

Expected: all tests PASS; all syntax checks exit `0`; no-env commands match
legacy behavior; malformed explicit forms produce no side effects; explicit
UAT commands never call legacy files.

- [ ] **Step 7: Statically review the compatibility split; run the commit only when execution is separately authorized**

Verify each public wrapper has exactly one legacy `exec`, only in the
non-`--env` branch. Verify `orchestrator.sh` contains no `legacy/dev`,
`provision-platform-prereq.sh`, `provision-k8s-components.sh`, or
`provision-signoz-observability.sh` reference. Commit:

```bash
git add scripts/provision.sh scripts/destroy.sh \
  scripts/verify-platform-health.sh scripts/legacy/dev \
  scripts/lib/confirmation-artifact.py scripts/lib/destroy-evidence.py \
  scripts/lib/orchestrator.sh tests/environment_orchestration/test_entrypoints.py \
  tests/environment_orchestration/test_destroy_evidence.py
git commit -m "feat: add explicit environment entrypoints"
```

Expected: one commit containing the wrappers, frozen legacy bodies,
orchestrator, and routing tests.

### Task 5: Supply Reviewed UAT Access Symbols To Unified Provisioning

**Files:**
- Create: `tests/environment_orchestration/test_access_dispatch.py`
- Create: `scripts/lib/packages/10-foundation-access/internal/access-scopes.sh`
- Create: `scripts/lib/scope-handlers.d/10-foundation-access.sh`
- Create: `scripts/lib/scope-verifiers.d/10-foundation-access.sh`
- Modify: `scripts/provision-uat-access.sh`
- Modify: `scripts/validate-uat-workforce-principals.sh`
- Modify: `tests/uat_access/test_platform_env.py`
- Modify: `tests/uat_access/test_principal_validation.py`

- [ ] **Step 1: Write private-fixture access dispatch tests**

Adapt the existing UAT access mocks rather than invoking live tools. Copy only
the new public wrapper/libraries, UAT config, backend bootstrap, principal
validator, and two existing access Terraform roots into a temporary repository.
Use command logs to assert exact narrow-scope order:

```python
EXPECTED_GOVERNANCE_ORDER = (
    "aws sts get-caller-identity",
    "aws configure get region",
    "aws s3api head-bucket",
    "terraform -chdir=", " fmt -check -recursive",
    " validate", " plan -input=false", " apply -input=false",
)

EXPECTED_EKS_ACCESS_ORDER = (
    "aws sts get-caller-identity",
    "aws configure get region",
    "kubectl config current-context",
    "kubectl config view --minify",
    "aws eks describe-cluster",
    "jq -e",
    "aws s3api head-bucket",
    "terraform -chdir=", " fmt -check -recursive",
    " validate", " plan -input=false", " apply -input=false",
)
```

Tests must prove:

- `access-governance` uses `ACCESS_GOVERNANCE_STATE_KEY` and the expected bucket owner.
- `eks-access` validates canonical context/auth mode and local principals before backend access.
- Principal input is exactly `config/environments/uat.local/workforce-principals.json`.
- Generated tfvars and saved plans exist only beneath `.local/uat/`.
- Generated tfvars are removed immediately after the saved plan captures them.
- Apply receives exactly one unchanged saved-plan path and no `-auto-approve` flag.
- Interactive approval accepts only exact `yes`; rejection/EOF never applies.
- `--auto-approve` skips the prompt but does not bypass identity, context, dependency, backend, saved-plan, or cleanup guards.
- Wrong account/Region/context/auth mode, invalid principals, lock contention, backend failure, plan failure, and apply failure clean only UAT temporary artifacts.
- Original failure wins over cleanup failure; cleanup failure makes an otherwise successful run fail.
- `all` fails during graph pre-resolution on work package 3 and invokes none of the access handlers.
- Explicit UAT command logs contain no legacy dev script or dev account ID.

- [ ] **Step 2: Add compatibility-wrapper tests**

Require exact forwarding:

```text
provision-uat-access.sh governance -> provision.sh --env uat access-governance
provision-uat-access.sh eks-access -> provision.sh --env uat eks-access
provision-uat-access.sh all -> provision.sh --env uat access-governance, then provision.sh --env uat eks-access
```

The old `all` wrapper expands to the two implemented access scopes; it must not
forward to unified `--env uat all`, because unified `all` correctly includes
the full platform and fails on deferred work package 3. Preserve the existing
`--auto-approve` option by appending it to each forwarded command. Unknown
arguments fail before forwarding.

- [ ] **Step 3: Run only when execution is separately authorized - prove access integration tests fail**

```bash
python3 -m unittest tests.environment_orchestration.test_access_dispatch -v
```

Expected: FAIL because `access-scopes.sh` and unified access handlers do not
exist and the compatibility script still owns orchestration.

- [ ] **Step 4: Extract access handlers without changing Terraform ownership**

Move these behaviors from `provision-uat-access.sh` into
`scripts/lib/packages/10-foundation-access/internal/access-scopes.sh`:

```bash
provision_backend_scope
provision_access_governance_scope
verify_existing_eks_platform_dependency
provision_eks_access_scope
run_saved_terraform_plan
confirm_saved_plan_apply
```

The foundation access fragments load foundation-owned implementation code
through the same validated package-library mechanism used by every numbered
fragment. Place `access-scopes.sh` at
`scripts/lib/packages/10-foundation-access/internal/access-scopes.sh`; the
orchestrator must not source it directly. The foundation handler fragment
first calls
`source_package_internal_library scripts/lib/packages/10-foundation-access/internal/access-scopes.sh`
and then defines only the exact canonical wrappers assigned by the immutable
registry:

```bash
foundation_provision_backend() { provision_backend_scope "$@"; }
foundation_provision_access_governance() { provision_access_governance_scope "$@"; }
foundation_provision_eks_access() { provision_eks_access_scope "$@"; }
```

Do not add scope-specific dispatch branches to `orchestrator.sh` and do not
change registry dependencies/order/symbol mappings. The matching foundation
verifier fragment defines only the canonical read-only pre-destroy guard and
access readiness verifier symbols assigned by the fixed registry. It loads
distinct package-owned internal libraries for guard behavior and verification
behavior when either is needed; the fragment itself contains only exact
wrappers. All later work packages
add numbered handler and verifier fragments that may load only their own
validated internal libraries and then directly define only their exact
pre-mapped canonical wrappers; no fragment performs registration or changes
the public verification grammar.

`provision_backend_scope` is an idempotent dependency handler within one
orchestration run: it validates/bootstraps the selected backend for the next
Terraform-owned scope, keyed by that scope, and records completion so the same
scope is not initialized twice. It does not create an EKS platform root.

`run_saved_terraform_plan` uses:

```bash
terraform -chdir="$terraform_root" fmt -check -recursive
terraform -chdir="$terraform_root" validate
terraform -chdir="$terraform_root" plan -input=false \
  -out="$plan_path" -var-file=uat.tfvars "${extra_var_file_args[@]}"
confirm_saved_plan_apply "$scope_name"
terraform -chdir="$terraform_root" apply -input=false "$plan_path"
```

Use an absolute environment-local plan path. For EKS access, pass
`-var-file="$generated_principal_tfvars"`; do not write
`generated.auto.tfvars.json` inside the Terraform root. Remove the generated
file after successful plan and before prompting/apply. Register plan/generated
paths before first creation so traps clean them on every failure.

Keep the two existing Terraform roots and `uat.tfvars` unchanged. This task
changes orchestration and generated-input location only; it does not broaden
Terraform resources, providers, principals, policies, or state ownership.

- [ ] **Step 5: Make the principal validator consume immutable UAT constants**

Keep its public `--input/--output` interface. Source
`environment-contracts.sh`, retrieve the four immutable UAT role prefixes,
and construct the same exact regular expressions. Continue to call no AWS API,
require exact JSON keys and unique strings, atomically write mode `0600`, and
emit only the three EKS roles. Update old tests only for the new library copy
and new local output path; preserve every existing negative case.

- [ ] **Step 6: Replace the old UAT orchestrator with a forwarding wrapper**

The wrapper contains no account, backend, Terraform, kubectl, lock, plan,
generated-file, or cleanup logic. Implement scope mapping with exact argument
validation and invoke public unified provision commands. Print one deprecation
line to stderr:

```text
DEPRECATED: use scripts/provision.sh --env uat <access-governance|eks-access>
```

For old `all`, call the two unified narrow commands sequentially so governance
finishes before EKS access. This wrapper is temporary and its removal is a
handoff item for the post-UAT migration plan.

- [ ] **Step 7: Run only when execution is separately authorized - verify all access and legacy regressions**

```bash
python3 -m unittest tests.environment_orchestration.test_access_dispatch -v
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
bash -n scripts/lib/packages/10-foundation-access/internal/access-scopes.sh \
  scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/orchestrator.sh
```

Expected: all tests PASS; existing UAT access safety assertions remain green;
plans/generated values are environment-local; old UAT commands forward; no
explicit UAT flow invokes legacy dev code.

- [ ] **Step 8: Statically review unified access integration; run the commit only when execution is separately authorized**

Confirm the compatibility wrapper contains only argument mapping/forwarding,
the access library contains no hard-coded `.uat-access.lock` or Terraform-root
generated file, and the existing access Terraform files are unchanged. Commit:

```bash
git add scripts/lib/packages/10-foundation-access/internal/access-scopes.sh \
  scripts/lib/scope-handlers.d/10-foundation-access.sh \
  scripts/lib/scope-verifiers.d/10-foundation-access.sh \
  scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh \
  tests/environment_orchestration/test_access_dispatch.py \
  tests/uat_access/test_platform_env.py \
  tests/uat_access/test_principal_validation.py
git commit -m "feat: unify UAT access orchestration"
```

Expected: one commit containing only access orchestration, compatibility, and
mocked regression tests; no Terraform resource file changes.

### Task 6: Complete Provision, Destroy, And Verification Failure Contracts

**Files:**
- Create: `tests/environment_orchestration/test_static_boundary.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`
- Modify: `tests/environment_orchestration/test_entrypoints.py`
- Modify: `scripts/lib/scope-registry.sh`
- Modify: `scripts/lib/orchestrator.sh`

- [ ] **Step 1: Add operation-matrix tests for every scope**

For each environment, operation, scope, and verification mode, assert the exact
result class:

| Environment/operation | Expected result |
|---|---|
| dev provision, any explicit scope | blocked by `PROMOTION_MODE=modeled` before commands/files |
| dev destroy, any explicit scope | blocked by `PROMOTION_MODE=modeled` before commands/files |
| dev verify `--preflight` | closed config plus mocked read-only account/Region readiness |
| dev verify full/smoke | fail closed on unavailable internal fixed-graph verifier symbols; no mutation gate is consulted |
| UAT provision `access-governance` | implemented |
| UAT provision `eks-access` | implemented after existing-platform verification |

For `eks-access` provision dispatch:
- Modify `orchestrator.sh` to skip the provision handler dispatch (but not the pass-1 dependency resolution) ONLY for scopes reporting `external-existing-platform`, and ONLY during the `provision` operation. Destroy and verify must remain strictly fail-closed.
- Update `test_scope_registry.py` to stop asserting that narrow `eks-access` fails via `eks-platform` pre-resolution.
- Update `test_entrypoints.py` to assert the new public CLI success path for UAT `eks-access` after `verify_existing_eks_platform_dependency` succeeds.
- Add an edge-case test: if `verify_existing_eks_platform_dependency` fails, assert no backend bootstrap, no Terraform plan/apply, and only UAT local artifact cleanup occurs.
| UAT provision `backend` | requires a concrete downstream state owner; direct standalone call reports usage and does not guess a key |
| UAT provision `all` | fails pre-resolution on work package 3 with no handler calls |
| UAT provision deferred narrow scope | exact owning-work-package dependency failure |
| UAT destroy any scope in this plan | retained/break-glass/deferred failure before mutation |
| UAT verify `--preflight` | account/Region and optional canonical context readiness only |
| UAT verify full/smoke | fixed verification graph fails on unavailable work-package 3-5 verifier symbols before workload checks |

For every UAT destroy scope, add parser and dispatch tests proving the
destroy-only, at-most-once
`--confirmation-artifact <repository-relative-path>` plus repeatable
`--confirm <exact-value>` implement the closed foundation-owned requirement
map, two-pass protocol, and exact confirmation grammar
`destroy:<env>:<account-id>:<scope>:<resource>:<consequence>`. Assert values
use the selected environment, immutable account ID, concrete resource identity
from loaded validated configuration/platform contracts, and the required
retention consequence. Cover `eks-platform`/`delete-cluster`,
`boomi-runtime`/`retain-efs`, `mongodb`/`delete-cluster-and-pvcs`, and both
PostgreSQL scopes with `final-snapshot=<foundation-generated-id>`. Prove the
foundation path/artifact API creates deterministic PostgreSQL final snapshot
identifiers before dispatch and that packages do not generate or parse them.

Assert a missing or incomplete first-pass set creates only a mode-`0600`
operation artifact with operation ID, created/expiry timestamps, environment,
account, requested scope, exact selected scope set/order, and exact ordered
confirmation set; it prints the exact artifact path and second-pass arguments
and exits nonzero without package or infrastructure mutation. Assert the
second pass requires the artifact option exactly once plus the complete set,
and rejects replayed/consumed, expired, stale, tampered, cross-scope,
cross-account, cross-environment, cross-operation, symlink, wrong-mode,
non-regular, traversal, and read-time path-swap cases. Prove atomic consumption
occurs after artifact validation, every mapped read-only guard in exact reverse
destroy order, and approval, but immediately before dispatch. Prove every
selected destroyable scope has exactly one required guard, absent downstream
guard symbols fail closed through canonical placeholders, guard failure skips
evidence/approval/consumption/handlers, guards perform no writes, and each
guard emits exactly one closed-grammar result through the active expected-scope
foundation callback. Prove callback calls outside an active phase, wrong-scope,
missing, duplicate, malformed, out-of-order, and wrapper/status-disagreeing
results fail closed and that stdout is never parsed as evidence. For every such
failure, prove the foundation writes a separate canonical mode-`0600`,
operation-bound `destroy-guard-failure.<operation-id>.json` record containing
the exact ordered received results and closed failure metadata, writes no
all-pass evidence, does not request approval, leaves confirmation unconsumed,
and dispatches nothing. Prove the foundation writes and validates canonical
mode-`0600` all-pass evidence only after all guards pass and before approval,
no infrastructure/package mutation occurs before consumption, and failures
after consumption require a new preparation pass.

Assert the foundation computes the expected ordered set before dispatch and
rejects missing, extra, duplicate, malformed-token, reordered, or mismatched
values. For selected `all`, require the union for every selected persistent scope and
reject a literal `all` confirmation; scopes without a registry requirement add
no value. Capture handlers must receive their ordered handler-specific subsets
byte-for-byte unchanged, with empty subsets for handlers without requirements;
the artifact path and operation metadata never reach handlers. Assert no
package artifact, registration, parser, normalizer, template, or synthesis API
exists. Test independently that `--auto-approve` neither satisfies nor
bypasses artifact/confirmation requirements and that artifact/confirmation
bypasses none of the
environment/promotion/account/Region/backend/context, interactive approval,
retention, or protection gates; a handler may still refuse. Assert each destroy
handler rechecks its critical resource identity immediately before mutation,
while static/event-order tests prove that no handler identity check is accepted
as the sole retention or protection gate. Assert exact evidence schema and
canonical bytes, exact `.local/<env>/evidence/` path, exclusive creation,
symlink/non-regular/mode rejection, ordered guard results, timestamps/expiry,
confirmation-byte digest, evidence digest, and operation/environment/account/
requested/resolved-scope binding. Assert final revalidation detects
confirmation/evidence tampering before consumption and dispatch. Assert only
the foundation creates append-only atomic `consumed`, `success`, and `failure`
status files, retains complete operation evidence for the required minimum,
and fails closed rather than cleaning partial, invalid, or tampered sets.

Test the public verification grammar as four and only four accepted forms:
`--preflight`, `--full`, no mode flag with exactly the same resolved slots as
`--full`, and `--smoke-test`. Reject every extra argument, combination, alias,
and component slot. Assert fragments expose only registry-pre-mapped internal
verifier functions and no registration API or downstream mode mapping exists.

Assert help exits `0`, lists all canonical scopes and current implementation
status, and does not load an environment or call commands. Assert aliases
`mongo` and `pg` remain legacy-only and are rejected by explicit unified mode
with canonical-name guidance.

- [ ] **Step 2: Add static source-boundary tests**

Use Python source reads, not shell grep, to assert:

```python
UNIFIED_FILES = (
    "scripts/lib/environment-contracts.sh",
    "scripts/lib/platform-env.sh",
    "scripts/lib/platform-guards.sh",
    "scripts/lib/orchestration-paths.sh",
    "scripts/lib/confirmation-artifact.py",
    "scripts/lib/destroy-evidence.py",
    "scripts/lib/scope-registry.sh",
    "scripts/lib/orchestrator.sh",
    "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh",
)

FORBIDDEN_UNIFIED_REFERENCES = (
    "scripts/legacy/dev",
    "provision-platform-prereq.sh",
    "provision-k8s-components.sh",
    "provision-signoz-observability.sh",
    ".local-dev-",
    ".uat-access.lock",
    "generated.auto.tfvars.json",
    "oms/dev/pg.tfstate",
)
```

Permit the public wrappers to contain their one non-explicit legacy path; do
not permit it anywhere else. Assert deferred handlers contain no `terraform`,
`aws`, `kubectl`, or `bash scripts/` token and include exact work-package
messages. Assert environment configs contain no shell quotes, command
substitution, unresolved angle-bracket examples, or secrets. Assert every
state key begins with its own environment prefix and no UAT config value
contains the dev account ID or `/dev/`.

### CI/CD Artifact Boundary Contract (Task 6 Required Gate)

This gate is mandatory before Task 6 implementation can be considered complete.
It defines portable, fail-closed handoff of `.local/<env>/` orchestration
artifacts between ephemeral CI jobs while preserving least-privilege and
anti-replay controls.

- [ ] **Required checklist**

1. Prepare/producer job writes all orchestration artifacts only beneath
   `.local/<env>/` and never outside repository containment checks.
2. Producer writes a canonical manifest (mode `0600`) with: file list,
   per-file SHA-256 digest, creation time, expiry time, operation ID,
   environment, account ID, repository commit SHA, orchestrator version, CI run
   ID, and CI job ID.
3. Producer records toolchain metadata: Terraform version, provider lock digest,
   Bash version, Python version, and script revision digest for every orchestration
   script invoked in prepare.
4. Producer packages artifacts into one deterministic archive whose root contains
   the canonical manifest and no extra files.
5. Consumer/execute job verifies canonical containment, file type, mode, and
   per-file SHA-256 digests before any mutation command.
6. Consumer rejects execution when producer and consumer toolchain metadata differ,
   unless a separately approved explicit override is present and recorded.
7. Consumer must re-evaluate all selected Assertion Scopes immediately before any
   Mutation Scope dispatch (TOCTOU protection). A stale assertion from prepare is
   never sufficient authorization for execute.
8. If assertion re-evaluation fails, execution stops before backend bootstrap,
   Terraform plan/apply, or handler dispatch, and only local cleanup may occur.
9. Artifact transport mechanism is explicit and policy-bound:
   - Native CI artifact storage is allowed only for non-sensitive payloads.
   - Any payload containing secrets, principal identifiers, or confirmation/evidence
     material must use a secure artifact vault (for example, S3 + KMS + strict OIDC IAM)
     with immutable object versioning and access logging.
10. Consumer enforces artifact TTL and rejects expired artifacts before dispatch.
11. Consumer rejects missing, extra, duplicate, symlinked, non-regular, traversal,
    or mode-unsafe artifact paths.
12. Orchestration lock ownership must be identity-bearing in ephemeral contexts.
    The lock payload contract is JSON with at least: `ci_run_id`, `ci_job_id`,
    `created_at_utc`, `owner`, and `orchestrator_pid` (if local).
13. Break-glass unlock requires deterministic fencing proof: verify lock owner liveness
    through CI API/process checks; if owner is live/unknown, force-unlock is denied.
14. If fencing proves lock owner is dead/stale, force-unlock is allowed only with
    an audit record capturing checker identity, timestamp, evidence, and reason.
15. Consumer writes an append-only consumption/status record for success/failure and
    preserves required evidence retention.
16. Cleanup securely purges extracted local artifacts after completion/failure and
    never deletes unvalidated or out-of-scope paths.
17. Runbooks must document prepare/execute artifact boundaries, storage policy,
    re-assertion behavior, and stale-lock break-glass steps.

- [ ] **Acceptance criteria**

1. A two-job CI rehearsal succeeds with prepare in Job A and execute in Job B using only transferred artifacts.
2. Hash mismatch in any artifact fails closed before any mutation command.
3. Missing/extra artifact path fails closed before any mutation command.
4. Toolchain mismatch fails closed unless explicit approved override is recorded.
5. Assertion re-evaluation failure in execute fails closed before backend/Terraform/dispatch.
6. Expired artifact fails closed with explicit expiry diagnostics.
7. Non-regular, symlinked, traversal, or mode-unsafe artifact path fails closed.
8. Sensitive payload routed through native CI artifacts is rejected by policy checks.
9. Secure vault path enforces immutable versioning, KMS encryption, and access logs.
10. Lock payload includes required identity fields and is parseable canonical JSON.
11. Force-unlock without fencing proof is rejected.
12. Force-unlock with validated stale-owner proof is allowed and audit-logged.
13. Consumption/status records are append-only and bound to operation ID.
14. Evidence bundle for rehearsal is attached to task closure notes.

- [ ] **Step 3: Run only when execution is separately authorized - verify the complete mocked/static suite**

```bash
python3 -m unittest discover -s tests/environment_orchestration -p 'test_*.py' -v
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
bash -n scripts/provision.sh scripts/destroy.sh \
  scripts/verify-platform-health.sh scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/*.sh \
  scripts/lib/packages/*/internal/*.sh \
  scripts/legacy/dev/*.sh
```

Expected: every Python test passes and every Bash syntax check exits `0`.
No test contacts AWS, Terraform providers/backends, or Kubernetes; subprocess
tests use temporary mocked executables only.

- [ ] **Step 4: Statically review the operation matrix; run the commit only when execution is separately authorized**

Using editor/file-reading tools, inspect every registry handler and every
public branch. Confirm direct UAT `backend` cannot choose an arbitrary or
default key, all deferred failures occur before local path initialization, and
ordinary destroy cannot remove backend or access governance. Commit:

```bash
git add tests/environment_orchestration/test_scope_registry.py \
  tests/environment_orchestration/test_entrypoints.py \
  tests/environment_orchestration/test_static_boundary.py
git commit -m "test: enforce orchestration scope boundaries"
```

Expected: one commit containing operation-matrix refinements and static safety
tests only.

### Task 7: Perform Static Review And Produce Later-Plan Handoff Contracts

**Files:**
- Verify: every file listed in Tasks 1-6
- Modify: `docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md` only if implementation discoveries require correcting this plan before handoff

- [ ] **Step 1: Complete a non-executing source review**

This step uses editor/file-reading tools only and remains permitted while test
execution is forbidden. Record the review result in the implementation
session summary, not in a new repository file. Check each invariant:

1. Dotenv and manifest files are never sourced or evaluated.
2. Dev and UAT use identical composed closed key sets; fragments extend the schema without parser edits; immutable account/Region/state-prefix/promotion checks remain separate.
3. Override rejection precedes config loading and `.local/` creation.
4. Explicit parser and graph pre-resolution precede handlers.
5. Every local artifact is beneath `.local/<selected-env>/`.
6. Every state key comes from the selected contract and registry mapping.
7. Explicit UAT code cannot reach any legacy dev script.
8. Existing no-`--env` dev argument grammar is preserved in frozen implementations.
9. `PROMOTION_MODE` accepts exactly `modeled` and `uat-build`; mutation is authorized only for selected UAT plus `uat-build`, and unified dev mutation is always blocked before AWS/backend/Terraform/Kubernetes/files.
10. Canonical API names and signatures exactly match the downstream handoff contract.
11. The registry contains the full final provision/destroy/verification graph, immutable orders, and canonical provision/destroy/pre-destroy-guard/verifier symbol mappings; every destroyable canonical scope has exactly one guard mapping, and fragments define assigned functions only and cannot register or alter slots.
12. Only existing access behavior has executable unified handlers; deferred platform/data/telemetry/Boomi handlers fail with exact owning work package.
13. All unified operations use one `.local/<env>/locks/orchestration.lock`; no component lock exists.
14. Ordinary destroy retains backend and access governance.
15. Compatibility `provision-uat-access.sh all` means the two historical access scopes, not the complete unified platform.
16. Dev keeps `BOOMI_NAMESPACE=boomi`; no config, manifest, handler, or example contains `boomi-dev`.
17. Local examples appear only as `config/environments/<env>.local/*.json.example`.
18. The exact canonical imported-code matrix is parsed only by the foundation validator, uses sequential `DOMAIN-0001` IDs, the closed `FOUNDATION`, `EKS`, `DATA`, `BOOMI`, `DOCS` domain enum, and the seven exact columns, validates with no unclassified rows, and blocks UAT planning while any candidate remains `PROPOSED`.
19. Numbered fragments use no registration API or calls, source only their own validated mode-safe internal libraries through the foundation helper, keep guard and verifier implementation libraries distinct, and define only exact immutable registry-pre-mapped wrappers; existing `scope-verifiers.d` fragments own both assigned pre-destroy guard and verification wrappers.
20. Destroy uses a mandatory preparation pass when confirmations are absent or incomplete; its sole mutation is exclusive creation of a mode-`0600`, 15-minute, operation-bound artifact beneath `.local/<env>/generated/`, and it exits nonzero after printing the exact `--confirmation-artifact` path and repeated `--confirm` arguments. The second invocation requires the artifact option exactly once plus the complete `destroy:<env>:<account-id>:<scope>:<resource>:<consequence>` set; no-follow same-descriptor reads validate operation ID, times, environment, account, requested scope, exact ordered graph, and exact ordered set against current state. After artifact validation, every registry-mapped read-only guard runs in exact reverse destroy order and emits exactly one closed-grammar result through the active expected-scope foundation callback; stdout is never parsed, callback misuse fails closed, and guards/packages write no files. After all guards pass, the foundation exclusively writes and validates canonical mode-`0600` operation evidence beneath `.local/<env>/evidence/` containing schema/operation/environment/account/requested and ordered resolved scopes, exact ordered results, timestamps/expiry, and the confirmation-byte digest. Only then may approval occur. Final revalidation binds the evidence digest and operation ID to the still-valid confirmation descriptor/current request before atomic confirmation consumption, atomic `consumed` status, and same-order dispatch; foundation-only atomic `success`/`failure` status files and minimum 90-day retention preserve audit history. Any guard/evidence failure leaves confirmation unconsumed and dispatches nothing. Each handler rechecks critical identity immediately before mutation but cannot be the sole retention/protection gate. Replay, expiry, tamper, stale/cross-operation use, symlinks, read swaps, missing/duplicate/out-of-order results, and invalid evidence/status fail closed, and post-consumption retry requires new preparation. The immutable foundation map supplies the union, not literal `all`, for `all`; handlers receive only unchanged confirmation subsets, packages never receive or write foundation artifacts/evidence/status, `--auto-approve` remains separate, and no safety, approval, retention, or protection gate is weakened.
20a. The guard callback remains exactly five arguments: scope, `PASS` or `FAIL`, resource identity, `sha256` digest, and summary code. Every failed, missing, duplicate, or invalid guard result causes a separate canonical mode-`0600`, operation-bound `destroy-guard-failure.<operation-id>.json` record containing ordered received results and closed failure metadata; no such path writes the all-pass evidence artifact, consumes confirmation, requests approval, or dispatches.
21. Public verification accepts exactly `--preflight`, `--full`, no mode flag as exact `--full`, and `--smoke-test`; downstream code supplies only fixed internal verifier slots and registers no mode.
22. No secret, local principal ARN, saved plan, generated tfvars, lock, log, or evidence file is tracked.

Expected: all twenty-two invariants can be traced to a concrete function and a
mocked/static test. Any failed invariant is repaired in the owning earlier task
and reviewed again before proceeding.

- [ ] **Step 1a: Add ADR follow-up backlog for post-foundation hardening**

Record these follow-up ADR tasks in the implementation session summary and in
later-plan handoff notes:

1. ADR: scope taxonomy migration (`assertion`, `mutation`, `composite`) so
   `external-existing-platform` behavior is represented declaratively in
   registry metadata instead of operation-specific engine branching.
2. ADR: lock payload fencing semantics replacing bare lock directories with
   identity-bearing canonical JSON lock payloads plus deterministic liveness
   fencing checks for break-glass unlock.
3. ADR: serialization of resolved Assertion/Mutation scope topology in
  orchestration artifacts so consumer jobs can re-evaluate the exact required
  preconditions without depending on potentially drifted local registry logic.

Expected: all ADR tasks are explicitly queued with owner, decision deadline,
and acceptance test strategy before Task 7 handoff completes.

- [ ] **Step 2: Run only when execution is separately authorized - execute the final focused verification**

```bash
python3 -m unittest discover -s tests/environment_orchestration -p 'test_*.py' -v
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
bash -n scripts/provision.sh scripts/destroy.sh \
  scripts/verify-platform-health.sh scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/*.sh \
  scripts/legacy/dev/*.sh
git diff --check
```

Expected: all tests PASS, syntax checks and `git diff --check` exit `0`, and
the mocked command logs prove no live AWS/Terraform/Kubernetes calls occurred.
Do not run Terraform formatting/validation, AWS CLI, kubectl, repository
provision/destroy/verify scripts, or live smoke tests as part of this plan.

- [ ] **Step 3: Run only when execution is separately authorized - prove legacy and UAT source separation with a read-only command**

```bash
if rg -n 'scripts/legacy/dev|provision-platform-prereq\.sh|provision-k8s-components\.sh|provision-signoz-observability\.sh' \
  scripts/lib/environment-contracts.sh scripts/lib/platform-env.sh \
  scripts/lib/platform-guards.sh scripts/lib/orchestration-paths.sh \
  scripts/lib/scope-registry.sh scripts/lib/orchestrator.sh \
  scripts/lib/packages/10-foundation-access/internal/access-scopes.sh; then
  echo 'Unified library references a legacy dev implementation' >&2
  exit 1
fi
```

Expected: no matches and exit `0`.

- [ ] **Step 4: Run only when execution is separately authorized - prove no deferred implementation slipped into work packages 1-2**

```bash
python3 - <<'PY'
from pathlib import Path

registry = Path("scripts/lib/scope-registry.sh").read_text(encoding="utf-8")
if 'printf \'%s\\n\' "external-existing-platform"' not in registry:
  raise SystemExit("missing implementation requirement token: external-existing-platform")

for scope, work_package in {
  "platform-controllers": 3,
  "workload-identity": 3,
    "mongodb": 4,
    "postgresql-core": 4,
    "postgresql-brand": 4,
    "mongodb-access": 4,
    "database-access-core": 4,
    "database-access-brand": 4,
    "signoz": 4,
    "signoz-observability": 4,
    "boomi-runtime": 5,
}.items():
    required = f'_scope_registry_fail_work_package "{scope}" {work_package}'
    if required not in registry:
        raise SystemExit(f"missing closed dependency declaration: {required}")
print("Deferred scope dependency declarations are complete")
PY
```

Expected: prints `Deferred scope dependency declarations are complete` and
exits `0`.

- [ ] **Step 5: Run only when execution is separately authorized - commit final review corrections only when needed**

If static review required code/test corrections, commit only those corrections:

```bash
git add scripts config/environments tests/environment_orchestration tests/uat_access .gitignore
git commit -m "fix: close orchestration review gaps"
```

Expected: omit this commit when no correction was necessary. Do not create an
empty commit.

## Exact Downstream Handoff Contract

Every later Phase 2 plan consumes this foundation under the following exact
contract. A downstream plan that conflicts with this section must be corrected
before implementation; it does not override the foundation implicitly.

### Files Later Plans May Add Or Modify

- Add one owned declarative file under
  `config/environment-schema/fragments/NN-domain.manifest`; add matching
  values to both `config/environments/dev.env` and
  `config/environments/uat.env`. Never edit `platform-env.sh` parser logic.
- Add checked-in local examples only at
  `config/environments/<env>.local/*.json.example`; runtime values use ignored
  `.json` siblings.
- Add one `scripts/lib/scope-handlers.d/NN-domain.sh` and one
  `scripts/lib/scope-verifiers.d/NN-domain.sh` when the domain has assigned
  slots. Package implementation libraries live only beneath the matching
  `scripts/lib/packages/NN-domain/internal/` directory. Each fragment may
  source only those package-owned libraries, only through
  `source_package_internal_library` after foundation path/file/mode validation,
  and then define the exact canonical handler wrappers and the exact canonical
  read-only pre-destroy guard/verifier wrappers already mapped to that package
  by the fixed registry. Guard implementation libraries and verifier
  implementation libraries must remain distinct. It may not directly use `source`/`.`,
  call a registration API (none exists), contain other top-level execution,
  alter graph/order/mode/slot/mapping data, or introduce public verification
  modes/executables.
- Append reviewed rows to
  `docs/operations/imported-code-review-matrix.md` using the stable
  `ID | Domain | Source | Target | Disposition | Evidence | Status` schema.
- Add implementation roots, tests, and documentation owned by that work
  package without creating another public orchestration path or lock.

### Files And Contracts Later Plans Must Not Change

- Downstream plans never modify `scripts/lib/platform-env.sh`,
  `scripts/lib/environment-contracts.sh`, `scripts/lib/scope-registry.sh`,
  `scripts/lib/orchestrator.sh`, `scripts/lib/orchestration-paths.sh`,
  `scripts/lib/confirmation-artifact.py`, `scripts/lib/destroy-evidence.py`, or the
  public `scripts/provision.sh`, `scripts/destroy.sh`, and
  `scripts/verify-platform-health.sh`. Their orchestration extensions are only
  the numbered manifests and handler/verifier fragments above.
- Do not change registry dependency data, provision `all` order, reverse
  destroy order, internal verification order, or canonical provision/destroy/
  pre-destroy-guard/verifier symbol mappings.
- Do not add a scope, alias, dependency, state-key mapping, second registry,
  second environment lock, component lock, or component-specific dispatcher.
  The registry already contains the complete final design graph.
- Do not rename or wrap `load_platform_env`,
  `verify_aws_identity_and_region`, `verify_kubernetes_context`,
  `initialize_orchestration_paths`,
  `require_environment_mutation_authorized` or `dispatch_scope_handler` with
  competing APIs. There is no public runtime registration API.
- Do not parse `--auto-approve`, `--confirmation-artifact`, or `--confirm` in a
  package. The foundation accepts the destroy-only artifact option exactly
  once on a complete second pass plus repeatable exact values using
  `destroy:<env>:<account-id>:<scope>:<resource>:<consequence>`, validates
  colon-free/non-empty safe tokens, and computes the ordered expected set from
  its closed immutable per-persistent-scope map. `all` requires the union for
  selected persistent scopes, never a literal `all` value. A missing or
  incomplete set creates only the canonical mode-`0600`, 15-minute artifact
  and exits nonzero after printing exact follow-up arguments. The foundation
  path/artifact API generates PostgreSQL final snapshot IDs, validates the
  artifact through canonical no-follow same-descriptor reads, and atomically
  renames it consumed after all guards/approval and immediately before
  dispatch. Reuse, expiry, tamper, stale/cross-environment/account/scope/
  operation content, symlinks, and path swaps fail closed; a post-consumption
  retry requires a new preparation pass. Packages do not receive the artifact
  path or operation metadata and do not register, persist, parse, normalize,
  or synthesize artifacts or confirmations.
  Canonical handlers receive only their ordered subsets, unchanged from the
  validated CLI values. Confirmation and auto-approval remain separate;
  neither weakens environment/promotion/account/Region/backend/context,
  approval, retention, or protection gates, and handlers may still refuse.
  After artifact validation, the orchestrator invokes every immutable
  registry-mapped pre-destroy guard in exact reverse destroy order. Each
  read-only wrapper must call
  `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>`
  with exactly those five arguments exactly once during its active
  expected-scope phase; stdout/stderr is never
  parsed as evidence, and missing, duplicate, wrong-scope, out-of-phase,
  malformed, out-of-order, or return-status-disagreeing results fail closed.
  Any failed, missing, duplicate, or invalid result causes only the foundation
  to write the separate canonical mode-`0600`, operation-bound
  `destroy-guard-failure.<operation-id>.json` record with ordered received
  results and closed failure metadata; it writes no all-pass evidence, leaves
  confirmation unconsumed, and performs no approval or dispatch. After all
  guards pass, only the foundation writes canonical mode-`0600` all-pass
  operation-bound evidence beneath `.local/<env>/evidence/`, binding exact
  ordered results and confirmation bytes. Evidence must exist before approval;
  final revalidation binds its digest/operation ID before confirmation
  consumption and dispatch. Foundation-only atomic consumed/success/failure
  status files and retention preserve the audit trail. Packages never write,
  receive, update, or clean evidence, status, confirmation, or other foundation
  files. Absent selected-scope symbols use fail-closed foundation placeholders.
  Each destroy handler rechecks critical identity immediately before mutation,
  but that check cannot replace or defer the mapped retention/protection guard.
- Do not register or add a public verification mode. Accepted forms remain
  exactly `--preflight`, `--full`, no mode flag as exact `--full`, and
  `--smoke-test`; packages implement only their pre-mapped internal slots.
- Do not introduce any `MUTATION_ENABLED` variant. `PROMOTION_MODE` remains the
  sole environment mutation gate with exact values `modeled` and `uat-build`;
  only selected UAT plus `uat-build` authorizes mutation now, and unified dev
  remains blocked even if a downstream plan supplies handlers.
- Do not change dev namespace constants to environment-suffixed inventions.
  In particular, `BOOMI_NAMESPACE=boomi` is canonical dev behavior and
  `boomi-dev` is prohibited.
- Do not create another imported-code matrix or defer classification to the
  documentation/UAT plan. The canonical matrix and validator exist before
  implementation; zero unclassified or `PROPOSED` candidates is a hard gate
  before a UAT plan may be authorized for execution.
- Do not invoke no-`--env` legacy dev compatibility commands from unified UAT
  code, handlers, tests, examples, or lifecycle automation.

### Work-Package Canonical Symbols

| Work package | Canonical symbols it may supply through fragments | Required retained preconditions |
|---|---|---|
| 3, EKS platform/backend/controllers/identity | Canonical `eks-platform`, `platform-controllers`, and `workload-identity` provision/destroy symbols, assigned read-only pre-destroy guard symbols, and assigned internal platform verifier symbols; concrete backend lifecycle behavior | Loaded contract, promotion authorization, AWS identity/Region, backend ownership, saved plan, one environment lock; publish platform outputs without weakening context/auth-mode checks. |
| 4, data/telemetry/access | Canonical provision/destroy symbols, assigned read-only pre-destroy guard symbols, and assigned verifier symbols for `mongodb`, `postgresql-core`, `postgresql-brand`, `mongodb-access`, `database-access-core`, `database-access-brand`, `signoz`, `signoz-observability` | Existing graph order, selected state-key mapping, environment paths, single lock, canonical guards, no legacy dispatch; keep core/brand state separate. |
| 5, Boomi runtime | Canonical `boomi-runtime` provision/destroy, read-only pre-destroy guard, and verifier symbols | Existing dependencies on `eks-platform`, `platform-controllers`, and `workload-identity`; canonical namespace values and local-input paths. |
| 6-7, docs/UAT/adoption | No implementation handler slot unless a separately approved design says otherwise | Document current status; enforce matrix gate; remove temporary UAT wrapper only after migration; preserve retention/break-glass controls; do not claim runtime evidence from static results. |

Each fragment must have focused tests proving exact assigned symbol names,
rejection of unavailable/unassigned symbols, dispatch through the unchanged
resolved order, reverse-order read-only pre-destroy guards with exactly one
valid five-argument callback result per active expected scope, a separate
canonical operation-bound guard-failure record and no all-pass
evidence/consumption/dispatch for every failed, missing, duplicate, or invalid
result, foundation all-pass evidence before approval and artifact consumption,
fail-closed selected-scope placeholders,
canonical guards before commands/files, no package foundation-file writes,
containment beneath `.local/<env>/`, and no route to legacy dev code. A later
plan may strengthen a handler's own preconditions but may not weaken or bypass
foundation preconditions.

## Completion Gate

This plan is complete only when the static review traces every work-package 1-2
requirement to code and tests, the canonical matrix is established, and, once
execution is separately authorized, all
mocked/static tests and Bash syntax checks pass. Completion does **not** mean
EKS platform, MongoDB, PostgreSQL, SigNoz, Boomi, database access, workload
identity, destroy, full verification, UAT lifecycle testing, or dev adoption is
implemented. It means those scopes are represented accurately, fail clearly,
and cannot accidentally route through legacy dev behavior while the reviewed
UAT access foundation is available through the unified explicit interface.