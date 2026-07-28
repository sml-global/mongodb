# Phase 4: Day-2 Operations & Data Durability — Design Spec

**Date:** 2026-07-28
**Status:** Approved (converged across 3 gatekeeper review rounds)
**Predecessor:** [PHASE3-PRODUCTION-READINESS-AUDIT.md](../../history/superpowers/PHASE3-PRODUCTION-READINESS-AUDIT.md)

## Goal

Close the 16 production-readiness gaps identified in the Phase 3 audit, prioritized by
risk: prove the platform survives data loss and safe operator upgrades before
addressing cost optimization and observability polish.

## Scope: 16 Findings, 4 Themes

| Theme | Findings | Priority | Depends On |
|---|---|---|---|
| **2. Data Durability & DR** | 3 | **P0 (first)** | none |
| **3. Platform Operations** | 5 | P1 | 1 of 5 tasks depends on Theme 2 |
| **1. Cost & Compliance** | 5 | P2 | none |
| **4. Observability Stability** | 3 | P2 | none |

Themes 1, 3 (except one task), and 4 have no hard dependency on each other and may be
worked in parallel once Theme 2 is underway.

## Key Design Decisions

### D1: ClickHouse backup must be application-consistent, not raw EBS snapshot
**Problem:** ClickHouse (SigNoz's storage engine) shares the `gp3-mongodb` EBS storage
class (`gitops/signoz/base/helmreleases.yaml:18`). A blind EBS/DLM snapshot of a live
ClickHouse volume can capture in-flight merges/inserts and produce an unrecoverable
backup.

**Decision:** Use `clickhouse-backup` (native S3-target backup tool that calls
`FREEZE TABLE` internally) instead of block-level EBS snapshots. If EBS snapshots are
used for cost reasons, they must be triggered only after a scripted `FREEZE TABLE`
pre-hook and scoped to the specific ClickHouse PVC by volume tag — never a blanket
policy that could also touch MongoDB volumes on the same storage class.

### D2: MongoDB and PostgreSQL already have native, application-consistent backup tools — DR validation tests restore, not backup
**Evidence:** MongoDB uses Percona Backup Management (PBM) to S3; PostgreSQL uses
continuous WAL archival with PITR to S3 (both documented in their platform contracts).
Theme 2 does not need new backup mechanisms for these two systems — it needs an
**automated, repeatable restore drill** that proves the existing backups are usable,
measures RTO/RPO, and verifies data integrity post-restore.

### D3: DR drills run in an isolated environment with least-privilege credentials
- Restore drills target **UAT** (`platform-prerequisites/terraform/environments/uat/`),
  never dev or prod.
- A dedicated drill-only IAM role is used: read-only `s3:GetObject` scoped to the
  backup bucket, no write access, not reusable for production restore operations.
- Drills run on a schedule (weekly) and are fully automated (no manual click-through).

### D4: Operator/CRD upgrade runbook depends on DR validation; other Theme 3 tasks do not
Only the CRD/Operator Upgrade task requires Theme 2 to be complete first (you need a
tested rollback path before attempting a risky operator upgrade). The remaining Theme 3
tasks — dashboard import failure recovery, operational alerts, concurrent provision
locking, API quota preflight — have no dependency on Theme 2 and may proceed in
parallel.

### D5: Test convention follows existing repo pattern
Existing tests (e.g. `tests/signoz/test_provision_readiness.py`) assert on **script
content** (e.g. `assertIn('kubectl wait', script)`) rather than executing real
infrastructure in CI. Phase 4 tests follow the same convention: assert that
runbooks/scripts contain the required commands, safety checks, and gates.

> **Superseded by D6** after the superpowers skill library updated to v6.2.0
> mid-implementation (`writing-good-tests.md` formally classifies grep-style
> script-content assertions as a falsifiability anti-pattern). See D6.

### D6: Test methodology is chosen per artifact type, not a single blanket style
Per `writing-good-tests.md` (superpowers v6.2.0): string-presence assertions on
scripts/manifests counterfeit falsifiability (a required command left in a comment
still passes). The fix is artifact-specific, not a single universal pattern:
- **Bash scripts** (drill scripts): executed for real via `subprocess`, with
  `kubectl`/`pbm`/`aws`/`mongosh`/`psql`/`clickhouse-client` replaced by PATH-mocked
  executables. Tests assert on real exit codes and real captured invocation
  arguments (including runtime-generated manifests captured from stdin, parsed
  structurally with PyYAML rather than grepped as text).
- **Terraform** (IAM roles/trust policies): verified with `terraform validate` /
  `terraform fmt -check` — this repo's existing convention — which parses the real
  HCL and catches reference errors (e.g. an `assume_role_policy` pointing at an
  undefined data source) that grep cannot detect.
- **Kubernetes/Helm YAML** (CronJob, HelmRelease values): parsed with PyYAML and
  asserted on structured fields, matching the existing convention in
  `tests/signoz/test_gitops_manifests.py`.

Note: `terraform validate` proves internal HCL consistency, not live AWS behavior.
Live behavior is proven independently by D7 (runtime identity guard) and by the
drills actually passing in UAT.

### D7: Every drill script includes a runtime IRSA identity guard (defense-in-depth)
Each drill script calls `aws sts get-caller-identity` immediately on startup and
fails closed if the assumed identity does not match its expected drill role. This
guards against a misconfigured Kubernetes ServiceAccount IRSA annotation silently
granting the wrong (e.g. production) credentials to the drill pod — a class of bug
that neither script-content grep nor `terraform validate` can catch, since it's a
live runtime binding, not a static property of any single file.

### D8: The ClickHouse drill role has an asymmetric (read+write) scope, unlike MongoDB/PostgreSQL
The MongoDB and PostgreSQL drill roles are read-only (`s3:GetObject`/`ListBucket`) —
they only prove existing backups are restorable. The ClickHouse task both **creates**
(`clickhouse-backup create`/`upload`) and restores a backup, so its drill role
additionally needs `s3:PutObject`, strictly scoped to its own dedicated bucket
(`oms-signoz-clickhouse-backups`) and never the MongoDB/PostgreSQL backup buckets.

### D9: Terraform never creates Kubernetes objects in this repo — a kubectl bootstrap script does
Verified repo-wide: no Terraform root in this repo defines any `kubernetes_*` resource
or `provider "kubernetes"` block; all Kubernetes objects are created via
GitOps/kubectl scripts (e.g. `scripts/create-signoz-root-user-secret.sh`). An earlier
draft of Task 4 used a `kubernetes_config_map` Terraform resource to wire drill-role
ARNs into the CronJob — this violated that boundary and also created a Flux-vs-Terraform
apply-ordering risk. Fixed: Terraform only outputs the role ARNs; a new idempotent
`scripts/bootstrap-dr-drill-role-arns-configmap.sh` (matching the existing bootstrap-script
convention) reads those outputs and `kubectl apply`s the ConfigMap. This is operator-run,
not Flux-reconciled, so there is no ordering dependency at all.

## Task Ordering for Implementation Plan

1. **Theme 2 (P0):** ClickHouse consistent backup, MongoDB PBM restore drill,
   PostgreSQL WAL/PITR restore drill — each with RTO/RPO measurement and automated
   scheduling.
2. **Theme 3 (P1, parallelizable):** Dashboard import failure recovery, operational
   alerts, concurrency lock, API quota preflight — independent of Theme 2. CRD/Operator
   upgrade runbook — gated on Theme 2 completion.
3. **Theme 1 (P2):** Cost monitoring, KMS rotation, S3 lifecycle, network TLS, secrets
   rotation.
4. **Theme 4 (P2):** SigNoz API versioning matrix, dashboard JSON schema validator,
   ClickHouse schema stability docs, data model compatibility.

## Completion Gates for Phase 4

- [ ] MongoDB restore drill succeeds from S3 PBM backup into an isolated UAT namespace,
      with measured RTO/RPO and a data-integrity query check.
- [ ] PostgreSQL restore drill succeeds via WAL/PITR into an isolated UAT namespace,
      with measured RTO/RPO and a data-integrity query check.
- [ ] ClickHouse backup/restore uses `clickhouse-backup` (or flush-hooked EBS snapshot)
      and is drilled at least once successfully.
- [ ] CRD/Operator upgrade runbook exists, is tested in UAT, and is explicitly gated on
      the above 3 drills passing.
- [ ] Remaining Theme 3, 1, 4 tasks each have passing content-assertion tests
      (repo convention) merged to main.
- [ ] All new scripts/runbooks documented in the relevant platform contract doc.
