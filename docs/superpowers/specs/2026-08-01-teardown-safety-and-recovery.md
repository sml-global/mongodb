# Teardown Safety & Recovery Documentation — Design Spec

**Date:** 2026-08-01
**Status:** Approved for planning (no infrastructure has been provisioned; this
spec covers script/documentation authoring only, no live execution)

## Context

`scripts/legacy/dev/destroy.sh` — the destroy script actually documented and
used by this repo (`bash scripts/destroy.sh <scope>` routes here by default,
with no `--env` flag) — has no confirmation gate and no backup-before-destroy
option for either database. A separate, more sophisticated pre-destroy guard
system exists (`scripts/lib/packages/{30-mongodb,40-postgresql}/internal/pre-destroy-guards.sh`),
but it only runs through the unified orchestrator (`--env dev|uat`), which is
not part of the documented default workflow, and even there it only verifies
that a backup mechanism is *configured* — it doesn't trigger one.

Both databases already have continuous backup infrastructure (PBM for
MongoDB, CNPG WAL archival to S3 for PostgreSQL), but:
- Nothing in the legacy destroy path forces an operator to acknowledge what
  they're about to remove.
- There's no on-demand way to take an immediate, ad-hoc backup independent of
  the continuous stream (useful for Day-2 operations: pre-migration
  snapshots, cloning data to a new environment, ad-hoc safety copies).
- `docs/references/recovery-procedures.md`'s "PostgreSQL Recovery" section
  only covers Aurora (UAT/Prod) restore — there is no Dev/SIT CNPG restore
  guidance anywhere in the repo.
- Nothing documents how an operator recovers data from an orphaned/`Released`
  EBS volume after a `Retain`-policy PVC/Cluster is deleted.

## Goal

Give operators (a) a hard confirmation gate before the legacy destroy script
removes anything, (b) a standalone, reusable on-demand backup tool usable for
Day-2 operations independent of destroy, (c) an opt-in flag wiring that tool
into the destroy flow, and (d) the two missing recovery guides — all as
reviewable scripts/docs, no live infrastructure execution.

## Key Design Decisions

### D1: Standalone On-Demand Export Tool

**Problem:** No on-demand backup capability exists independent of the
continuous PBM/WAL streams, and the user explicitly wants this as a general
Day-2 tool, not a destroy-only feature.

**Decision:** Create `scripts/export-database-snapshot.sh <mongodb|postgresql> [--wait-timeout-seconds N]`.
It triggers each database's **native** on-demand backup mechanism — verified
directly against each tool's official documentation rather than assumed:

- **MongoDB:** `kubectl -n mongodb exec <pbm-agent-pod> -- pbm backup --wait --wait-time <timeout>`.
  `--wait` is a real, documented PBM flag ("Wait for the backup to finish. The
  flag blocks the shell session," available since PBM 2.6.0) — the command
  itself blocks until the backup finishes or the wait-time elapses.
- **PostgreSQL:** apply an on-demand `Backup` custom resource
  (`apiVersion: postgresql.cnpg.io/v1`, `kind: Backup`, `spec.method: barmanObjectStore`,
  `spec.cluster.name: oms-postgresql`), then poll
  `kubectl get backup <name> -o jsonpath='{.status.phase}'` until it reports
  `completed` (success) or `failed` (error), matching CNPG's documented
  `Backup` resource lifecycle (`running` → `completed`).
  **Caveat, flagged honestly:** the reference docs for this describe CNPG's
  current/devel version; this repo pins the operator chart to `0.22.x`, an
  older major version. The `barmanObjectStore`-method `Backup` CR is
  documented as the backward-compatible default, but the exact CRD schema for
  `0.22.x` should be verified against the installed CRD (`kubectl explain backup.spec`)
  during implementation rather than assumed identical to the devel docs.

Both paths write into the **existing, predefined S3 destinations already
configured for continuous backup** (`s3://oms-postgresql-backup` for
PostgreSQL; PBM's already-configured remote storage for MongoDB) — no new S3
bucket, no local file leaves the cluster. This was an explicit, deliberate
choice: pulling a `pg_dump`/`mongodump`-style file to an operator's laptop via
`kubectl exec` was considered and rejected (data-exfiltration risk, bypasses
existing KMS-at-rest encryption on the S3 destination, and doesn't scale to
large datasets) in favor of reusing the secure, already-encrypted destination.

### D2: Destroy-Script Safety Gate

**Problem:** `scripts/legacy/dev/destroy.sh` runs every `kubectl delete` call
immediately with zero confirmation, for any scope, and its own documented
"Full Environment Rebuild" runbook instructs running it with `--auto-approve`
and no backup-first step.

**Decision:**
1. Add a hard, typed confirmation gate: before any destructive action for
   any scope, if `--auto-approve` was not passed, print what will be
   destroyed and require the operator to type the literal word `DESTROY`
   (case-sensitive) to proceed; any other input (including empty) aborts
   with a non-zero exit and touches nothing. `--auto-approve` bypasses this
   prompt (as it already bypasses Terraform's own destroy prompt), preserving
   existing automation call sites that already pass `--auto-approve`.
2. Add an opt-in `--export-first` flag. When present, `destroy.sh` calls
   `scripts/export-database-snapshot.sh` for every database scope about to be
   destroyed (`mongodb`/`mongo` → mongodb export; `pg` → postgresql export;
   `all` → both) **before** any teardown step runs for that scope, and aborts
   the whole destroy run if an export fails (a failed safety snapshot should
   block teardown, not be silently ignored).
3. Both are additive and off-by-default in the sense that existing
   `--auto-approve` automation is unaffected (no new prompt) and
   `--export-first` must be explicitly requested — no change to default
   destroy behavior beyond the new confirmation prompt for interactive
   (non-`--auto-approve`) use, which is the actual safety gap being closed.

### D3: Dev/SIT CNPG Restore Guide

**Problem:** `docs/references/recovery-procedures.md`'s "PostgreSQL Recovery"
section is Aurora-only; there is no committed guidance for restoring the
Dev/SIT CNPG cluster from its continuous WAL archive or an on-demand backup.

**Decision:** Add a "Dev/SIT PostgreSQL Recovery (CNPG)" subsection to
`docs/references/recovery-procedures.md` covering: restoring into a new
`Cluster` via `.spec.bootstrap.recovery` pointing at the existing
`s3://oms-postgresql-backup` archive, and point-in-time recovery via
`recoveryTarget.targetTime`. Cross-link from
`docs/references/postgresql-platform-contract.md`.

### D4: EBS Orphaned-Volume Recovery Runbook

**Problem:** Both `gp3-mongodb` and `gp3-postgresql` StorageClasses use
`reclaimPolicy: Retain`. Deleting a PVC/Cluster moves the PV to `Released`,
not `Available` — the volume and its data survive, but nothing documents how
an operator gets it back.

**Decision:** Add an "Orphaned EBS Volume Recovery" section to
`docs/references/recovery-procedures.md` (or a dedicated file, cross-linked,
if it grows large) covering: identifying a `Released` PV
(`kubectl get pv | grep Released`), clearing `spec.claimRef` to move it back
to `Available`, and binding it to a new PVC (matching `storageClassName` and
`accessModes`) to mount and read the data — explicitly noting this is a
Kubernetes-side operation (`claimRef` is a PV field), not an AWS-console
action.

## Out of Scope

- Modifying the unified orchestrator's existing `pre-destroy-guards.sh`
  system — this spec only touches the legacy path, per prior agreement.
- Any live `kubectl`/`pbm`/`terraform` execution — this spec and its plan
  produce reviewable scripts/docs only; all tests are structural (mocked
  binaries, text/argument-parsing assertions), matching the pattern already
  established in `tests/environment_orchestration/test_entrypoints.py`.
- A literal local-file (`pg_dump`/`mongodump`) export path — deliberately
  rejected per D1.
