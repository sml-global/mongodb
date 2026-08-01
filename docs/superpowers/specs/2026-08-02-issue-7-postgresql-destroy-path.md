# Issue #7: PostgreSQL Destroy Path — Design Spec

**Date:** 2026-08-02
**Status:** Approved for planning (no infrastructure has been provisioned; this
spec covers script/test authoring only, no live execution)

## Context

`scripts/legacy/dev/destroy.sh`'s `pg` scope currently only runs
`terraform_destroy_scope pg` (destroying the Terraform-managed AWS
prerequisites — IAM role/policy, S3 WAL bucket, KMS key). It never removes the
in-cluster CNPG `Cluster` resource or operator, unlike `mongodb`, which has a
`destroy_mongodb_k8s()` step before its Terraform destroy. This is exactly the
gap tracked in GitHub Issue #7.

Consequence: destroying the `pg` scope today leaves the CNPG `Cluster`
(`oms-postgresql` in the `postgresql` namespace) and the CNPG operator
(`HelmRelease/cloudnative-pg` in `postgresql-operator`) running while their
AWS-side prerequisites (WAL archive bucket, IAM role) are deleted out from
under them — the cluster keeps trying (and failing) to archive WAL to a
bucket that no longer exists.

## Goal

Add a `destroy_postgresql_k8s()` function mirroring `destroy_mongodb_k8s()`'s
pattern, wire it into the `pg` and `all` destroy scopes before their
Terraform teardown step, and update tests accordingly.

## Key Design Decisions

### D1: Resources To Delete

**Confirmed via direct inspection of `gitops/postgresql/`:** unlike MongoDB,
PostgreSQL's GitOps manifests define no `Secret`, `Certificate`, or `Issuer`
resources (verified via repo-wide search — zero matches). The only resources
to remove are:
- The CNPG `Cluster` resource: `oms-postgresql` in namespace `postgresql`.
- The operator `HelmRelease`: `cloudnative-pg` in namespace `postgresql-operator`.

### D2: Deletion Order

**Decision:** delete the `Cluster` resource **before** the operator
`HelmRelease`, mirroring `destroy_mongodb_k8s()`'s exact order (CR, then
operator). This order is safe regardless of whether CNPG's `Cluster` resource
uses a finalizer that requires a live operator to clear it: if it does, only
this order avoids a `Cluster` stuck in `Terminating` forever; if it doesn't,
this order is no worse than the reverse. The reverse order (operator first)
has no safety advantage and a plausible failure mode, so it's not considered.

### D3: Namespace Handling

**Decision (per explicit answer to this spec's clarifying question):**
mirror `destroy_mongodb_k8s()` — leave the `postgresql` and
`postgresql-operator` namespaces in place; only remove the `Cluster` and
`HelmRelease` resources within them. This avoids the finalizer-clearing loop
`destroy_signoz()` needs (which exists specifically because SigNoz's
ClickHouse installation can get stuck on namespace deletion) and keeps
MongoDB/PostgreSQL teardown behavior symmetric, as this repo already does for
every other aspect of the two databases' provisioning/destroy lifecycle.

### D4: Wiring Into `pg` and `all` Scopes

**Decision:** mirror `destroy_mongodb()`'s exact pattern:
```bash
destroy_pg() {
  destroy_postgresql_k8s
  terraform_destroy_scope pg
}
```
No changes needed to the `all` scope's dispatch — it already calls
`destroy_pg` (which will now include the k8s step transparently), matching
how `all` already gets MongoDB's k8s teardown for free via `destroy_mongodb`.

### D5: Interaction With The Confirmation Gate And `--export-first`

**No changes needed.** `confirm_destruction` and `export_scope_if_requested`
already run before the scope dispatch and already recognize the `pg` scope
(the `export_scope_if_requested` case statement already maps `pg` to
`scripts/export-database-snapshot.sh postgresql`, from the
teardown-safety-and-recovery epic). Adding `destroy_postgresql_k8s` inside
`destroy_pg()` means an operator who passes `--export-first` will already get
a fresh on-demand backup before this new k8s teardown step runs, for free.

## Test Impact

`tests/environment_orchestration/test_entrypoints.py`'s
`LegacyDestroyRegressionTests` (or equivalent) test suite exercises `pg` and
`all` destroy scopes against a mocked-binary fixture and asserts the exact
command log. Any test asserting the `pg` scope's command log currently
expects only a `terraform destroy`-shaped call; these must be updated to
expect the new `kubectl delete cluster` / `kubectl delete helmrelease` calls
first, matching the same style already used for the equivalent MongoDB
assertions.

## Out of Scope

- Any live `kubectl`/`terraform` execution — this spec and its plan produce
  reviewable script/test changes only.
- Changing the unified orchestrator's pre-destroy guard system
  (`scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh`) — out
  of scope per this repo's established boundary between the legacy and
  unified destroy paths.
- `--export-first` behavior itself — already implemented and unaffected by
  this change (see D5).
