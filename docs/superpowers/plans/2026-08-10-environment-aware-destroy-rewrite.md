# Plan: environment-aware destroy for mongodb/mongodb-access/postgresql-core/postgresql-brand/signoz/signoz-observability

**Status:** Draft — awaiting review before implementation. No code changes yet.

## Why this is needed now

Live-testing #107's destroy/provision/verify cycle against UAT hit the fail-safe guard added in #95/#96/#97: every one of these six scopes' `*_internal_destroy_*` handlers shells out unconditionally to `scripts/legacy/dev/destroy.sh` (frozen, hardcoded to DEV's account/cluster/state), and refuses to run for any account other than DEV's `815402439714`. That guard is working exactly as designed — it is not a bug, it's the reason destroy is currently impossible against UAT for these scopes. This plan is the deferred "real rewrite" #95/#96/#97 always described as future work.

## What's actually true today (verified by reading code, not assumed)

**Provision may already be closer to environment-aware than expected for some scopes** — this surprised me mid-investigation, worth stating precisely:

- `scripts/provision-platform-prereq.sh` (used by mongodb/postgresql-core/postgresql-brand provision) already has a real per-environment tfvars mechanism: `if [[ -n "${ENVIRONMENT:-}" && -f "$TF_DIR/terraform.${ENVIRONMENT}.tfvars" ]]; then TFVARS_FILE="terraform.${ENVIRONMENT}.tfvars"`. Confirmed live: `platform-prerequisites/terraform/mongodb/terraform.uat.tfvars` **exists**. This is consistent with mongodb having actually provisioned correctly into `mongodb-uat` earlier in this session.
- It also sources `scripts/legacy/dev/load-env-config.sh`, but that loader only fills in variables that are **not already set** (`if [[ -z "${!key:-}" ]]; then export ...; fi`) — since the unified orchestrator's `load_platform_env` runs first and exports the real environment's values, dev.env's values are skipped, not applied. This is NOT the env-var-clobbering bug it might look like at a glance.
- `postgresql-core` has **no** `terraform.uat.tfvars` yet — expected, since #100 found its whole tfvars shape needs fixing first (still pending the design decision + `eks-platform` apply follow-up).
- `signoz`/`signoz-observability` don't use `provision-platform-prereq.sh` at all — they go through `scripts/provision-k8s-components.sh` (no dev.env sourcing, inherits whatever the orchestrator already exported) and `scripts/provision-signoz-observability.sh` (does source `load-env-config.sh`, same non-clobbering behavior as above).

**Conclusion: provision-side environment-awareness is inconsistent across scopes and needs live verification per-scope, not an assumption that it's broken everywhere (per #51) or working everywhere.** This plan's primary, certain scope is **destroy** — which has zero environment-awareness mechanism of any kind, confirmed for all six targets (all call `scripts/legacy/dev/destroy.sh` directly, no per-environment tfvars/dispatch equivalent exists on the destroy side at all).

## Scope of this plan: destroy only

Per-scope current behavior (`scripts/lib/packages/{30-mongodb,40-postgresql,50-signoz}/internal/lifecycle-handlers.sh`):

| Scope | Current destroy handler |
|---|---|
| mongodb | `bash scripts/legacy/dev/destroy.sh mongodb --auto-approve` |
| mongodb-access | `printf 'INFO: ...'` (no-op stub, nothing to make environment-aware) |
| postgresql-core | `bash scripts/legacy/dev/destroy.sh pg --auto-approve` |
| postgresql-brand | `bash scripts/legacy/dev/destroy.sh pg-brand --auto-approve` |
| signoz | `bash scripts/legacy/dev/destroy.sh signoz --auto-approve` |
| signoz-observability | `bash scripts/legacy/dev/destroy.sh signoz-observability --auto-approve` |

`scripts/legacy/dev/destroy.sh` (the target of all four real shellouts) is a single frozen script whose functions (`destroy_mongodb_k8s`, `destroy_postgresql_k8s`, `destroy_signoz`, etc.) hardcode namespace names (`mongodb`, not `$MONGODB_NAMESPACE`), Terraform state keys (`oms/dev/mongo.tfstate`), and account context via `scripts/legacy/dev/load-env-config.sh`'s dev.env default. None of this can simply be parameterized in place without touching the "frozen, must not change behavior" legacy script CLAUDE.md describes — the correct approach is what `eks-platform`/`workload-identity` already do: **real handlers in `internal/lifecycle-handlers.sh` that call Terraform/kubectl directly with environment-resolved values, never shelling out to the legacy script at all.**

## Design: destroy_mongodb() rewrite (representative; same shape for postgresql/signoz)

Looking at `destroy_mongodb_k8s()` in `scripts/legacy/dev/destroy.sh` (already hardened by #93/#94/#98 — AWS CLI error handling, kubectl timeouts), the environment-aware rewrite should:

1. **Not modify the legacy script at all** — it stays frozen, exactly as CLAUDE.md requires, and DEV's own `bash scripts/destroy.sh mongodb` (no `--env`) keeps calling it unchanged.
2. **Port the same logic into `mongodb_internal_destroy_mongodb()`** in `scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh`, parameterized on already-exported orchestrator variables instead of hardcoded literals:
   - `$MONGODB_NAMESPACE` instead of literal `mongodb`
   - Terraform state key from `$MONGODB_STATE_KEY` (already exported by `load_platform_env`) instead of the legacy script's own `oms/dev/mongo.tfstate` literal
   - `$AWS_REGION`/`$TF_STATE_BUCKET`/`$TF_STATE_REGION` from the environment, not dev's hardcoded defaults
   - Reuse `terraform_destroy_scope`-equivalent logic (state bucket bootstrap, backend init) — likely needs its own small helper library shared between provision and destroy paths, not copy-pasted twice
3. **Remove the `destroy_account_id_forbidden_for_legacy_shellout` guard call** for each scope once its rewrite lands (per the comment already in each handler: "Do not remove this guard without that rewrite" — this is that rewrite).
4. **Verify live against UAT** for each scope individually before assuming the pattern generalizes — per #29/#35's own history (referenced in #50's investigation), the equivalent provision-side environment-aware rewrite for `eks-platform`/`workload-identity` needed several additional live-discovered fixes beyond the initial dispatch-wiring change. Budget for the same here.

## Suggested sequencing (smallest safe slice first)

1. **mongodb** — most already-instrumented (namespace/replica-set already parameterized elsewhere in the same package, e.g. `verifiers.sh`/`pre-destroy-guards.sh`/`live-observations.sh` already use `$MONGODB_NAMESPACE` throughout). Smallest gap to close.
2. **mongodb-access** — no destroy handler logic exists at all beyond the info-log stub; once mongodb's rewrite pattern is proven, mongodb-access likely just needs the real `create-audit-writer-user.sh`-equivalent teardown (delete the k8s Secret) with no legacy-script shellout at all.
3. **signoz** / **signoz-observability** — next, since `provision-k8s-components.sh`/`provision-signoz-observability.sh` already show a partially-environment-aware pattern to extend from.
4. **postgresql-core** / **postgresql-brand** — last, and gated on #100's open design question (does Aurora need any of the removed CNPG-shaped variables) being resolved first; no point building destroy for a scope whose provision path is still an open design question.

## Safety

- Every live verification step in this plan is a real destroy/provision command against UAT infrastructure — run by the user, not the agent, matching every other live step in today's session.
- Do not attempt all six scopes in one PR — per-scope PRs (or at most, one PR per sequencing step above), each independently live-verified before moving to the next, matching how #93/#94/#95/#100/#101/#103/#108 were each handled as separate, independently-verified changes.
- `scripts/legacy/dev/destroy.sh` itself must not change behavior — CLAUDE.md is explicit that this file is frozen and is the current production path for DEV.

## Open questions for review

1. Confirm sequencing: mongodb first, mongodb-access second, signoz/signoz-observability third, postgresql-core/brand last (gated on #100)?
2. Should the Terraform backend-bootstrap logic currently embedded in `scripts/legacy/dev/destroy.sh`'s `terraform_destroy_scope()` function be extracted into a shared library callable by both the legacy script (unchanged behavior) and the new environment-aware handlers, or should the environment-aware handlers each re-implement their own equivalent backend init? (Recommend: extract to a shared library — avoids the same class of copy-paste drift #100 found between `postgresql-core`'s CNPG-shaped variables and Aurora's actual needs.)
3. Confirm scope: this plan is destroy-only. Should a parallel pass verify provision is actually environment-aware for every scope (not just mongodb, which we've now confirmed), before assuming provision is "already fine" everywhere?
