# PostgreSQL Dev/SIT Orchestration & IaC Cleanup — Design Spec

**Date:** 2026-07-31
**Status:** Approved for planning (no infrastructure has been provisioned; this
spec covers IaC/orchestration authoring only)

## Context

`gitops/postgresql/base/` already contains a complete CNPG (CloudNativePG)
Cluster definition for Dev/SIT, but nothing in this repository's provisioning
scripts ever applies it — Issue #6 originally assumed the manifest was
missing; it exists but is unwired. Separately, `gitops/postgresql/overlays/uat/`
is dead code superseded by the Aurora RDS migration (PR #3), and several
docs/tests reference incorrect resource names or missing files. Nothing in
any environment has been provisioned yet (confirmed by the repo owner), so
all changes described here are IaC-authoring and orchestration-wiring only —
no live infrastructure is touched.

## Goal

Wire the existing CNPG PostgreSQL manifests into the provisioning automation
for Dev/SIT, fix a real multi-AZ storage anti-pattern, eliminate a CRD race
condition in the GitOps layering, delete the dead UAT overlay, and correct
documentation/test drift — all as reviewable, testable IaC changes.

## Key Design Decisions

### D1: Storage Class Safety (WaitForFirstConsumer)

**Problem:** `gitops/postgresql/base/cluster.yaml` references `storageClass: gp3`.
No StorageClass named `gp3` is defined anywhere in this repo (confirmed via
repo-wide search — the only committed StorageClass is `gp3-mongodb`), and the
EKS EBS CSI driver add-on (installed via `bootstrap_ebs_csi_driver` in
`scripts/provision-k8s-components.sh`) does not create a default StorageClass.
Dev/SIT's EKS cluster is genuinely multi-AZ (`ap-east-1a`, `ap-east-1b`,
confirmed in `platform-prerequisites/terraform/environments/dev/eks-platform.tfvars`).
Even if a `gp3` class existed with `Immediate` binding, a PVC could bind in a
different AZ than the scheduler later places the pod, leaving it permanently
`Pending`.

**Decision:** Introduce a dedicated `gp3-postgresql` StorageClass with
`volumeBindingMode: WaitForFirstConsumer`, structurally identical to the
existing `k8s/base/storageclass-gp3-mongodb.yaml`, plus a Kyverno
`ClusterPolicy` enforcing it — mirroring `policies/kyverno/require-wffc-storageclass.yaml`
exactly (match by StorageClass **name**; `StorageClass` is cluster-scoped,
so there is no namespace field to match against).

### D2: CRD Race Condition Avoidance

**Problem:** `gitops/postgresql/base/kustomization.yaml` currently bundles
`operator.yaml` (a Flux `HelmRelease` that asynchronously installs the CNPG
operator and its CRDs) together with `cluster.yaml` (a `Cluster` custom
resource requiring the `clusters.postgresql.cnpg.io` CRD to already exist).
Applying both in one `kubectl apply -k` would fail on a fresh cluster because
Flux's helm-controller hasn't reconciled the HelmRelease yet. MongoDB avoids
this exact problem by keeping its operator (`gitops/operators/base/`,
containing only `helmreleases.yaml`/`helmrepositories.yaml`) fully separate
from its Cluster CR (`k8s/base/psmdb-cluster.yaml`, applied via
`k8s/overlays/dev/`), with an explicit CRD-wait in between.

**Decision:** Remove `cluster.yaml` from `gitops/postgresql/base/kustomization.yaml`
(base becomes operator-only: `namespace.yaml`, `helmrepository.yaml`,
`operator.yaml`). Create `gitops/postgresql/overlays/dev/` containing
`cluster.yaml` (moved from base, with `storageClass: gp3-postgresql`) as a
standalone `resources:` entry (not a `patches:` entry — there's nothing left
in base to patch against). The orchestrator applies base, waits for the CRD,
then applies the dev overlay.

### D3: Orchestration Wiring (Minimal Blast Radius)

**Problem:** Neither `scripts/provision-k8s-components.sh` nor
`scripts/legacy/dev/provision.sh` has any path that applies
`gitops/postgresql/*`. `scripts/legacy/dev/provision.sh`'s existing `pg` scope
only runs `run_platform pg` (Terraform prerequisites — already fully wired
against `platform-prerequisites/terraform/postgresql`); it never applies the
GitOps layer.

**Decision — corrected from the initial draft:**
1. Add a `postgresql` scope to `scripts/provision-k8s-components.sh` with
   **new, distinctly-named functions** — `apply_postgresql_operator`
   (applies `gitops/postgresql/base`) and `apply_postgresql_overlay` (applies
   `gitops/postgresql/overlays/dev`). The existing `apply_operators()` and
   `apply_overlay()` functions are hardcoded to MongoDB-specific paths
   (`gitops/operators/base` = the Percona operator; `k8s/overlays/dev` =
   MongoDB's cluster overlay) and must **not** be reused for PostgreSQL —
   doing so would silently re-apply MongoDB's manifests instead.
2. Sequence for the `postgresql` scope: `preflight_scope` → `apply_postgresql_operator`
   → `apply_policies` → `wait_for_postgresql_crd` → `apply_postgresql_overlay`.
   `apply_policies` (applies `policies/kyverno`) must be included — it was
   missing from the initial draft, which would have meant the new WFFC
   policy from D1 never actually gets applied.
3. Add a `postgresql` case to `preflight_scope()` requiring the Flux
   `helmreleases.helm.toolkit.fluxcd.io` / `helmrepositories.source.toolkit.fluxcd.io`
   CRDs (same as the `signoz|operators` case) and, when
   `--bootstrap-platform-controllers` is passed, bootstrapping both Flux and
   Kyverno (Kyverno is needed here because of the new WFFC policy — the
   existing `mongodb|mongo` case is the precedent for bootstrapping Kyverno
   alongside Flux).
4. Update `scripts/legacy/dev/provision.sh`: the `pg` scope calls
   `run_k8s postgresql` after `run_platform pg`; the `all` scope calls
   `run_k8s postgresql` after `run_k8s mongodb`.
5. *Minimal blast radius:* `scripts/provision-k8s-components.sh`'s own
   internal `all` scope (currently `mongodb` + `signoz`) is left untouched —
   it is not on the documented critical path (`legacy/dev/provision.sh`'s
   `all` calls `run_k8s mongodb` specifically, never `run_k8s all`).

### D4: Dead Code Elimination (UAT Overlay)

**Problem:** `gitops/postgresql/overlays/uat/` (patching `instances: 3` and
`wal.compression: gzip` — both already the literal defaults in base, confirmed
by direct diff) is superseded now that UAT uses Aurora RDS. Nothing has been
provisioned, so no live teardown runbook is needed — this is pure dead-code
removal.

**Decision:** Delete `gitops/postgresql/overlays/uat/` entirely.

### D5: Test and Documentation Alignment

**Problem (tests):** `tests/postgresql/test_gitops_manifests.py` has 4
existing tests referencing `BASE_DIR / "cluster.yaml"` that will break once
`cluster.yaml` moves (`test_cluster_manifest_exists_and_valid_yaml`,
`test_cluster_manifest_uses_iam_workload_identity`,
`test_cluster_manifest_has_no_hardcoded_aws_credentials`,
`test_cluster_manifest_uses_workload_service_account`), plus 2 tests
targeting the UAT overlay that must be removed
(`test_kustomize_build_uat_overlay_succeeds`, `test_uat_overlay_applies_cluster_patches`).

**Problem (docs):** `docs/references/postgresql-platform-contract.md` and
`docs/references/verification-commands.md` reference a pod/cluster name of
`postgresql`/`postgresql-1`, but the real resource is named `oms-postgresql`
(pod `oms-postgresql-1`, per CNPG's 1-indexed pod numbering). Both docs and
`docs/references/component-catalog.md` reference a `gp3-postgresql`
StorageClass file at `k8s/base/storage-classes.yaml`, which doesn't exist,
and `component-catalog.md` documents the provisioning command as
`scripts/provision.sh postgresql`, but the real scope name is `pg`. The
UAT "manual decommission step" warning in both `postgresql-platform-contract.md`
and `docs/index.md` is obsolete once the UAT overlay is deleted pre-deployment.

**Decision:**
- Update `test_gitops_manifests.py`: point the 4 cluster.yaml tests at the
  new `gitops/postgresql/overlays/dev/cluster.yaml` location; delete the 2
  UAT-specific tests; add tests asserting the dev overlay kustomize-builds
  successfully and that base no longer contains a `Cluster` resource.
- Add a structural test (Python, no execution of live infra) asserting
  `scripts/provision-k8s-components.sh` defines the `postgresql` scope and
  calls its apply functions in the correct order (operator → policies → CRD
  wait → overlay), by parsing the script's text.
- Correct pod/cluster names, StorageClass name/location, and the
  provisioning command reference across `postgresql-platform-contract.md`,
  `component-catalog.md`, and `verification-commands.md`; remove the UAT
  manual-decommission warning from `postgresql-platform-contract.md` and
  `docs/index.md`.
- Update GitHub Issue #6 to reflect the corrected premise (manifest exists,
  orchestration was missing) once the fix lands.

## Out of Scope

- Any live `kubectl apply` / `terraform apply` execution — this spec and its
  implementation plan produce reviewable code only.
- `scripts/provision-k8s-components.sh`'s own internal `all` scope (see D3.5).
- SIT-specific overlay (the `dev` overlay serves both Dev and SIT per the
  existing single-environment-tier convention used by MongoDB's `k8s/overlays/dev`).
