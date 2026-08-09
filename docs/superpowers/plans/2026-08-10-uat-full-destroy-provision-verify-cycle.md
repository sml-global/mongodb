# Plan: Full UAT destroy → provision → verify cycle for every live scope

**Status:** Draft — awaiting review before execution. No commands run yet.

## Purpose

Before real UAT/Prod deployment work continues, verify that this repo's deployment scripts (`scripts/provision.sh`, `scripts/destroy.sh`, `scripts/verify-platform-health.sh`, all via `--env uat`) actually work correctly end-to-end — not just "currently healthy because it was provisioned once, weeks ago, by an unknown sequence of manual fixes." A destroy → re-provision → verify cycle proves both directions of each script work for real, which a read-only health check alone cannot.

This absorbs and extends the intent of #77/#81 (which scoped MongoDB destroy specifically) into a full-repo pass, and follows the same "plan first, review, then execute" discipline used for #103.

## Scope: which scopes get the full cycle

Per `scripts/lib/scope-registry.sh`'s canonical provision/destroy orders, the scopes currently live and healthy in UAT (confirmed via `verify-platform-health.sh --env uat --full` on 2026-08-09) are:

```
backend, access-governance, eks-platform, workload-identity,
platform-controllers, mongodb, mongodb-access, signoz, signoz-observability
```

**Excluded from the destroy/reprovision cycle, verify-only:**
- `backend`, `access-governance` — their destroy handlers are hard-blocked by design (`foundation_destroy_backend_blocked`/`foundation_destroy_access_governance_blocked`: "break-glass procedure required" / "retained-control procedure required"). These are never meant to be destroyed as part of ordinary testing — only a live health check applies to them here.

**Excluded entirely (not provisioned, not in today's scope):**
- `eks-access` — externally blocked on an Identity Center handoff (unrelated to this repo's code).
- `boomi-runtime`, `database-access-core`, `database-access-brand` — genuinely unimplemented work packages.
- `postgresql-core`, `postgresql-brand` — just had their dead CNPG-shaped IAM policy removed (#100/PR #105, merged). Not yet live-tested even once in UAT. These need a **first-time provision + verify** (no destroy, since nothing exists yet to destroy) as a separate, earlier step — see "Sequencing" below.

**Gets the full destroy → provision → verify cycle:**
```
eks-platform, workload-identity, platform-controllers, mongodb, mongodb-access,
signoz, signoz-observability
```

## Sequencing

Order matters — each scope's destroy/provision must respect its dependency chain (`dependencies_for_scope` in `scope-registry.sh`):

```
eks-platform            (depended on by: eks-access, workload-identity, platform-controllers, mongodb, signoz)
  workload-identity     (depends on: eks-platform)
  platform-controllers  (depends on: eks-platform)
    mongodb             (depends on: eks-platform, platform-controllers)
      mongodb-access    (depends on: mongodb)
    signoz              (depends on: eks-platform, platform-controllers)
      signoz-observability (depends on: signoz)
```

Given `eks-platform` is the root dependency for everything else, **destroying and recreating it would cascade-destroy every downstream scope** (new cluster = new OIDC provider = every IRSA/Pod-Identity binding invalidated). That is a MUCH bigger, higher-blast-radius operation than what's needed to validate "does destroy/provision work correctly" — and risks a multi-hour rebuild if anything goes wrong partway.

**Recommendation: do NOT destroy/reprovision `eks-platform` itself in this pass.** Verify it (read-only) and leave it running. Test destroy → reprovision for everything **downstream** of it, in leaf-first destroy order, root-first provision order:

**Destroy order (leaves first):**
```
signoz-observability → signoz → mongodb-access → mongodb → platform-controllers → workload-identity
```

**Provision order (roots first, reverse of above):**
```
workload-identity → platform-controllers → mongodb → mongodb-access → signoz → signoz-observability
```

After each destroy: run `verify-platform-health.sh --env uat --full` and confirm the scope (and only that scope, plus its now-torn-down dependents) reports failing/not-found — nothing upstream/unrelated should be affected.

After each provision: run the same verify and confirm the scope reports `PASS` again, with no regressions in scopes already confirmed.

**First-time provision for `postgresql-core`/`postgresql-brand`** happens separately, before or after this cycle (order doesn't matter relative to the above, since nothing else depends on them): apply `eks-platform` once to expose `cluster_kms_key_arn` (already documented as a follow-up from #105), rebuild `postgresql-core`'s tfvars with real values, then `provision.sh --env uat postgresql-core` / `postgresql-brand` for the **first time** and verify. No destroy step for these two yet, since there's nothing live to destroy.

## Test matrix (one row per scope, in the order above)

| Scope | Destroy command | Expected after destroy | Provision command | Expected after provision |
|---|---|---|---|---|
| signoz-observability | `bash scripts/destroy.sh --env uat signoz-observability` | verify: FAIL (not found); signoz itself still PASS | `bash scripts/provision.sh --env uat signoz-observability --auto-approve` | verify: PASS, same as before |
| signoz | `bash scripts/destroy.sh --env uat signoz` | verify: FAIL; mongodb/mongodb-access still PASS (independent branch) | `bash scripts/provision.sh --env uat signoz --auto-approve` | verify: PASS |
| mongodb-access | `bash scripts/destroy.sh --env uat mongodb-access` | verify: FAIL; mongodb itself still PASS | `bash scripts/provision.sh --env uat mongodb-access --auto-approve` (re-run `create-audit-writer-user.sh --namespace mongodb-uat` if the handler is still a no-op stub, per current `mongodb_internal_provision_mongodb_access` — see note below) | verify: PASS |
| mongodb | `bash scripts/destroy.sh --env uat mongodb` | verify: FAIL; mongodb-access now also FAIL (dependent) | `bash scripts/provision.sh --env uat mongodb --auto-approve` | verify: PASS for mongodb; re-run mongodb-access provision after (its data was wiped by mongodb's destroy) |
| platform-controllers | `bash scripts/destroy.sh --env uat platform-controllers` | verify: FAIL; mongodb/signoz still PASS (already-provisioned resources aren't retroactively broken, but future provisions of anything depending on Flux/cert-manager/Kyverno would fail) | `bash scripts/provision.sh --env uat platform-controllers --auto-approve` | verify: PASS |
| workload-identity | `bash scripts/destroy.sh --env uat workload-identity` | verify: FAIL; low risk, tfvars ship with `identities = {}` (no real resources to destroy) | `bash scripts/provision.sh --env uat workload-identity --auto-approve` | verify: PASS |

**Note on `mongodb-access`:** per earlier investigation (#103), the unified orchestrator's `mongodb_internal_provision_mongodb_access()` handler is currently just an info-log stub — it does not actually create the `oms-audit-writer` secret. The real creation step is the standalone `scripts/create-audit-writer-user.sh --namespace mongodb-uat` (already run once today, live). This test matrix should treat `mongodb-access`'s "provision" step as **both** commands run together, and this gap itself is worth flagging as a follow-up issue (the unified provision handler for `mongodb-access` should probably call `create-audit-writer-user.sh` itself, not leave it as a separate manual step) — not fixed as part of this test pass, just noted.

## Safety notes

- Every command above targets `--env uat` explicitly. Per CLAUDE.md, DEV and SIT remain off-limits regardless.
- `mongodb` destroy wipes real data in the `oms_audit` database (test/placeholder data only, presumably, but confirm before destroying if any real audit records have been written there since this is UAT, not dev).
- Between each destroy/provision pair, capture the full command output as evidence (this doc or a follow-up comment on the tracking issue) — matching #28's own evidence-capture convention for certification passes.
- Any command failing unexpectedly (not matching the "Expected" column) — stop, do not proceed to the next scope, investigate/file an issue first (same discipline as today's #93/#94/#95/#100/#101/#103 findings).
- I (the agent) will not run any of these commands myself — every provision/destroy command in the matrix above is a real write action against live UAT infrastructure, and per today's established pattern, the user runs live commands while I guide, verify output, and file/fix any bugs found.

## Open questions for review

1. Confirm the destroy/reprovision cycle should stop at `workload-identity`/`platform-controllers` and NOT include `eks-platform` itself (recommended above due to cascade-destroy blast radius) — agree, or do you want `eks-platform` included too (accepting the full-rebuild risk)?
2. Confirm okay to proceed scope-by-scope in the order above, one at a time, verifying after each — rather than destroying everything first and reprovisioning after (the latter has a longer window with more of UAT down at once).
3. Any known real (non-test) data in `mongodb-uat`'s `oms_audit` database that destroying `mongodb` would lose? (Expect "no, still integration-testing" given where we are in issue #28's certification pass, but confirming before wiping anything.)
