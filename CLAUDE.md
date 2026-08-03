# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Provisions the data-layer infrastructure for the OMS (Order Management System) dev/UAT environment on EKS: PostgreSQL (Aurora, primary app DB), MongoDB (Percona/PSMDB, audit-trail DB), and SigNoz (application telemetry). Three independently provisioned scopes with independent lifecycles — see `README.md` § "Why These Scopes Are Separate" before assuming they should be merged or run together.

Full documentation hub: `docs/index.md`. Read `AGENTS.md` first — it defines scope/safety rules for this repo (edits restricted to this repo; sibling repos `../boomi-infra/`, `../oms-backend/`, `../oms-frontend/` are read-only references).

## Commands

Provision/destroy/verify (legacy dev flow, no `--env` flag — this is the default/current path):
```bash
scripts/verify-platform-health.sh --preflight     # environment/identity sanity before anything else
bash scripts/provision.sh all --auto-approve      # MongoDB + PostgreSQL core data layer
bash scripts/provision.sh signoz --auto-approve
bash scripts/provision.sh signoz-observability --auto-approve
scripts/verify-platform-health.sh --smoke-test
```
Narrower scopes: `scripts/provision.sh mongodb`, `scripts/provision.sh pg`. Teardown: `scripts/destroy.sh <scope>`.

There is a second, newer `--env <dev|uat>` unified orchestration entrypoint (`scripts/lib/orchestrator.sh`, dispatched via the scope registry in `scripts/lib/scope-registry.sh`). `scripts/provision.sh`/`destroy.sh`/`verify-platform-health.sh` are thin routers: a leading `--env` argument routes to the unified orchestrator; anything else execs the frozen `scripts/legacy/dev/*.sh` implementation unchanged. Many unified scopes are still placeholder-only pending work packages — check `scope-registry.sh` before assuming a `--env` scope is implemented.

Tests (pytest, `unittest.TestCase`-based, run from repo root):
```bash
python -m pytest tests/ -q                                    # full suite
python -m pytest tests/postgresql/test_documentation.py -v    # one file
python -m pytest tests/postgresql/test_documentation.py -k devsit_cnpg -v  # one case
env -u TF_DATA_DIR python -m pytest tests/ -q                  # unset TF_DATA_DIR if set in shell — some tests assume it's unset
```
Note: the committed `.venv` does not have pytest installed — install it (`pip install pytest`) before running tests locally.

Terraform lives under `platform-prerequisites/terraform/<root>/` (one root per scope: `mongodb`, `postgresql`, `signoz-observability`, `eks-platform`, `eks-access`, `access-governance`, `workload-identity`, `dr-drill`, etc.), each with its own state key under the S3 backend (`platform-prerequisites/terraform/backend.tf`). Don't `cd` and run raw `terraform apply` by hand for routine work — use the wrapper scripts (`provision-platform-prereq.sh`, `provision.sh`) so state-key selection and account/region guards stay correct.

Kubernetes manifests: `k8s/` (Kustomize, dev overlay only) is applied by `scripts/provision-k8s-components.sh`. `gitops/` holds the equivalent ArgoCD/Flux-style structure with `uat` overlays for several components — check which of `k8s/` vs `gitops/` is authoritative for the environment/scope you're touching; they are not the same deployment path.

## Architecture

**Scope separation is the central design decision.** `all` (MongoDB + PostgreSQL) is the core data layer; `signoz` (telemetry platform) and `signoz-observability` (dashboards/alerts as code) are separate because SigNoz has independent failure modes and `signoz-observability` requires a live, authenticated SigNoz API that doesn't exist until `signoz` is healthy. Never fold these together without understanding this dependency chain (README.md has the full rationale and a dependency diagram).

**Legacy vs. unified orchestration.** `scripts/legacy/dev/` holds the original, frozen dev-only provision/destroy/verify implementations — these are the current production path and must not change behavior. A newer unified orchestration layer (`scripts/lib/orchestrator.sh`, `scope-registry.sh`, `environment-contracts.sh`, `platform-env.sh`, `platform-guards.sh`, `orchestration-paths.sh`) is being built alongside it to eventually support both `dev` and `uat` through one code path, gated behind an explicit `--env` argument on the public wrappers. `environment-contracts.sh` hardcodes immutable per-environment constants (AWS account IDs, regions, Terraform state prefixes, promotion mode) as a `case` statement — these are compiled-in, not read from env vars or dotenv files, and are the single source of truth the rest of the orchestrator fails closed against. When working in this area, check `docs/superpowers/plans/` for the dated plan doc that owns the file you're touching — file headers reference their owning plan/task explicitly.

**Destroy safety.** Destructive operations go through a two-pass confirmation-artifact + guard-evidence protocol (`scripts/lib/confirmation-artifact.py`, `scripts/lib/destroy-evidence.py`, both stdlib-only Python invoked via CLI, never imported as a package) before the unified orchestrator will execute a destroy. `record_pre_destroy_guard_result` in `orchestrator.sh` is the sole channel a guard uses to report results. Never bypass this by calling Terraform/kubectl destroy commands directly for anything beyond your own personal dev sandbox.

**Scripts are organized by responsibility, not by scope**, and most are intentionally thin:
- `provision.sh` / `destroy.sh` / `verify-platform-health.sh` — public routers only (dispatch to legacy or unified path)
- `provision-platform-prereq.sh` — Terraform root/state-key selection per scope
- `provision-k8s-components.sh` — Kustomize apply per scope (`mongodb`, `signoz`, `operators`, `policies`, `overlay`)
- `scripts/lib/` — shared bash libraries (sourced, not executed directly); `scope-handlers.d/` and `scope-verifiers.d/` are fragment directories other work packages drop scope-specific provision/verify functions into
- `scripts/groovy/boomi/BoomiAuditLogLibrary.groovy` — the reusable library Boomi processes call to write audit records; `scripts/write-auditlog-and-telemetry.sh`/`.groovy` is the test harness that exercises it end-to-end (not the library itself — don't conflate the two when debugging)

**Config layering:** `config/environments/<env>.env` holds configurable per-environment values; `config/environment-schema/base.manifest` + `fragments/` define what's allowed/required in those files. This is distinct from `environment-contracts.sh`'s hardcoded immutable constants — a dotenv value that disagrees with its corresponding immutable constant is a fail-closed error, not an override.

**Tests mirror scope structure**: `tests/<scope>/` (e.g. `postgresql/`, `signoz/`, `dr_drill/`, `network_cidr/`, `environment_orchestration/`). Many tests validate documentation content (e.g. `test_documentation.py` asserts required sections/keywords exist in `docs/references/*.md`) rather than runtime behavior — when changing a platform-contract doc, check whether a corresponding test enforces its structure.

## Key Docs (don't duplicate content from these into responses)

- `docs/index.md` — navigation hub, start here for anything not covered above
- `docs/references/component-catalog.md` — what every component is/does/depends on
- `docs/references/audit-log-contract.md` — canonical audit document shape; keep Boomi-related changes aligned with this
- `docs/references/verification-commands.md` — per-component health checks
- `docs/references/recovery-procedures.md` — rollback/DR/credential rotation
- `docs/guides/architect-reference.md` — architecture and state model for day-2 maintenance
- `docs/superpowers/plans/` — dated plan docs; a file's own header usually names the plan/task that owns it

## Agent skills

### Issue tracker

Issues live in GitHub (`sml-global/mongodb`), managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), unchanged. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Working Conventions

- Prefer repository scripts over ad-hoc raw Terraform/kubectl command chains — the wrappers encode account/region/identity guards that raw commands skip.
- Before declaring a provisioning or destroy task successful, run the relevant verification command (`verify-platform-health.sh` or a scope-specific verifier) and report the concrete result, not just "command exited 0".
- When editing docs, preserve cross-links and keep `docs/index.md` navigation accurate.
- Bash library files under `scripts/lib/` target Bash 3.2 compatibility: no associative arrays, no `declare -g`, no namerefs.
