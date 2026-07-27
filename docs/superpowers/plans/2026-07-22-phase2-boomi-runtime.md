# Phase 2 Boomi Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a support-recognizable, UAT-first standard private Boomi runtime cluster with guarded installation-token bootstrap, stable three-node identities, shared EFS storage, secure service boundaries, telemetry, lifecycle integration, and recovery evidence while keeping live dev unchanged.

**Architecture:** Versioned Kustomize manifests under `gitops/boomi-runtime/` define one invariant `boomi/molecule` v5 StatefulSet and environment overlays. Bash 3.2-compatible lifecycle functions in `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` own rendering, bootstrap transitions, diagnostics, and graceful removal; `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh` owns runtime verification, while `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh` separately owns pre-destroy guards. Both read-only internal libraries are artifact-free and use disjoint `boomi_internal_verifier_*` and `boomi_internal_pre_destroy_guard_*` names. The handler fragment sources only the lifecycle implementation; the numbered scope-verifiers fragment foundation-validates and sources both read-only internal libraries and alone defines the exact canonical verification and pre-destroy guard wrapper symbols already mapped by the foundation. Before confirmation-artifact consumption, the Boomi guard performs live runtime, graceful-removal, EFS-retention, and dependency checks, computes its closed in-memory result, and records it once through the foundation callback without reading or writing evidence. Guard failure preserves the artifact and prevents destroy dispatch. After all guards pass and foundation writes evidence and consumes confirmation, the destroy handler immediately rechecks canonical identity before graceful mutation. The foundation-owned parser, immutable contracts, guards, registry mappings, environment-local paths, single orchestration lock, graph resolution, public two-pass destroy confirmation-artifact protocol, and `PROMOTION_MODE` gate remain authoritative; no parser, shared schema, registry mapping, orchestrator, public script, mode, or graph change is permitted. The Boomi communication decision is a readiness prerequisite only: it can keep UAT acceptance blocked, but it cannot authorize dev or bypass foundation promotion and execution authorization.

**Tech Stack:** Bash 3.2-compatible shell, Python 3 `unittest`, Kubernetes `apps/v1` StatefulSet, Kustomize, AWS EFS CSI, `kubectl`, official `boomi/molecule:release` v5 image, SigNoz/OpenTelemetry, Terraform SigNoz provider.

**Normative pre-destroy evidence ownership:** This rule supersedes any later reference in this plan to Boomi consuming, looking up, validating, confirming, or requiring an already-existing pre-destroy evidence/status record. The read-only internal Boomi guard computes a secret-safe closed summary and its SHA-256 digest entirely in memory from the current live runtime, graceful-removal, EFS retain-contract, and dependency checks. The foundation-mapped Boomi wrapper invokes exactly `record_pre_destroy_guard_result boomi-runtime <PASS|FAIL> runtime/boomi-uat <sha256:<64-lowercase-hex-characters>> <summary-code>` once per guard invocation, on both pass and fail paths, after computation; raw hex is invalid. Foundation alone writes the all-pass evidence artifact or separate failure record. No Boomi fragment, internal library, lifecycle handler, verifier, or guard requests an evidence path or writes, reads, validates, consumes, refreshes, or confirms an evidence artifact.

---

## Guardrails And File Map

This plan implements only Phase 2 of the approved UAT consolidation design. It starts only after `2026-07-22-phase2-environment-orchestration-foundation.md` provides the canonical closed parser, foundation-loaded schema fragments, immutable environment contracts, shared guards, immutable scope registry mappings, environment-local path helpers, one `.local/<env>/locks/orchestration.lock`, graph dispatcher, generic public two-pass destroy confirmation-artifact protocol, and promotion gate. It also depends on the EKS platform output APIs for the canonical UAT EKS ARN and EFS filesystem/access-point handle. Consume those APIs without extending their mappings; do not fork the parser, create a second lock, source dotenv files, or revive legacy no-`--env` behavior.

The following foundation contracts are invariants for every task in this plan:

- `load_platform_env <env>` and foundation-loaded schema fragments are the only configuration parser path.
- `PROMOTION_MODE` plus the foundation's operation authorization API is the only environment mutation gate. No Boomi variable, document, support decision, or handler may grant mutation authority.
- `initialize_orchestration_paths`, canonical artifact helpers, and the already-held orchestration lock own all `.local/<env>/` paths. Boomi handlers must not acquire a component lock.
- `dependencies_for_scope`, `provision_handler_for_scope`, `destroy_handler_for_scope`, and `verification_handler_for_slot` remain the canonical registry APIs, and their mappings are immutable. Boomi fragments define only the exact pre-mapped canonical wrapper symbols; they do not edit registry, graph, mode, slot, or mapping data.
- Public `scripts/provision.sh`, `scripts/destroy.sh`, and `scripts/verify-platform-health.sh` remain thin foundation wrappers. This plan does not add a public provisioner or rewrite the public `all` graph.
- The foundation-owned generic public destroy parser requires two passes. The mandatory first pass validates repeatable `--confirm <exact-value>` arguments, computes their required union for the selected scope set, prepares the foundation-owned confirmation artifact, reports its repository-relative path, and performs no destroy dispatch. The second pass must repeat the exact same confirmations and add `--confirmation-artifact <repository-relative-path>`; the foundation alone parses and validates the artifact before dispatch. It passes only the unchanged Boomi confirmation subset to the mapped Boomi destroy handler. Boomi code never receives or parses the artifact path or artifact content and must not parse, normalize, synthesize, or reinterpret destroy confirmation.
- The immutable environment contract is exact: UAT uses `PROMOTION_MODE=uat-build` and `BOOMI_NAMESPACE=boomi-uat`; dev uses `PROMOTION_MODE=modeled` and `BOOMI_NAMESPACE=boomi`.
- The canonical operator-local example layout is `config/environments/<env>.local/*.json.example`; actual local JSON files are ignored.

## Uniform Execution Boundary

**No command in this plan is authorized for execution now.** Every test, formatter, linter, `bash -n`, Kustomize render, `kubectl` client dry-run, Terraform command, repository scan, script invocation, commit, and AWS/Kubernetes/SigNoz command shown below is **AUTHORIZED ONLY**. An implementing agent may write code and tests, but must stop before running any command until the platform owner explicitly authorizes that exact execution class. Labels such as offline, read-only, dry-run, mocked, or non-mutating describe expected behavior; they do not grant authorization.

The implementation creates or changes these files:

- Modify `docs/operations/imported-code-review-matrix.md`: add the canonical Boomi legacy-source disposition rows.
- Create `docs/references/boomi-runtime-official-evidence.md`: focused official evidence supporting the canonical matrix; it is not a second disposition authority.
- Create `docs/references/boomi-runtime-communication-decision.md`: readiness decision record; it never grants mutation authority.
- Create only `config/environment-schema/fragments/40-boomi-runtime.manifest` for the Boomi schema. Do not edit parser code, the base manifest, a shared schema registry, or any other schema file.
- Create `config/environments/dev.local/boomi-runtime.json.example` and `config/environments/uat.local/boomi-runtime.json.example`: non-secret examples using the canonical local layout. Dev namespace is `boomi`.
- Create `gitops/boomi-runtime/base/kustomization.yaml`: invariant manifest inventory.
- Create `gitops/boomi-runtime/base/serviceaccount.yaml`: namespace-local identity without AWS credentials.
- Create `gitops/boomi-runtime/base/services.yaml`: headless cluster discovery and internal administration services.
- Create `gitops/boomi-runtime/base/storage.yaml`: retained RWX EFS PV/PVC contract.
- Create `gitops/boomi-runtime/base/statefulset.yaml`: steady-state three-node v5 runtime without an install token.
- Create `gitops/boomi-runtime/base/pdb.yaml`: prevent voluntary simultaneous disruption.
- Create `gitops/boomi-runtime/base/networkpolicy.yaml`: default deny plus explicit runtime, telemetry, DNS, and cluster communication paths.
- Create `gitops/boomi-runtime/overlays/dev/kustomization.yaml` and `patch-runtime.yaml`: render-only modeled dev configuration.
- Create `gitops/boomi-runtime/overlays/uat/kustomization.yaml` and `patch-runtime.yaml`: UAT namespace, runtime name, resources, and EFS handle.
- Create `gitops/boomi-runtime/components/tcp-7800/kustomization.yaml` and `patch-communication.yaml`: approved unicast candidate.
- Create `gitops/boomi-runtime/components/multicast-45588/kustomization.yaml` and `patch-communication.yaml`: approved multicast candidate.
- Create `gitops/boomi-runtime/bootstrap/kustomization.yaml` and `patch-bootstrap.yaml`: transient ordinal-0 token reference and one-replica state.
- Create `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`: internal `boomi_internal_lifecycle_*` provision, bootstrap, rendering, diagnostics, and destroy functions plus lifecycle-private helpers. It defines no verification/guard implementation and no canonical wrapper symbol.
- Create `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh`: internal, read-only `boomi_internal_verifier_*` runtime verification functions plus verifier-private helpers. It defines no lifecycle or pre-destroy guard implementation, creates no package artifact or evidence, and defines no canonical wrapper symbol.
- Create `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh`: internal, read-only `boomi_internal_pre_destroy_guard_*` guard functions plus guard-private helpers. It computes only an in-memory closed summary and digest from live checks, defines no lifecycle or runtime verification implementation, creates or reads no package artifact or evidence, and defines no canonical wrapper symbol.
- Create `scripts/lib/scope-handlers.d/40-boomi-runtime.sh`: source only the Boomi-owned mode-safe lifecycle implementation (plus any exact foundation-validated helper library it demonstrably needs) under foundation validation and define the exact pre-mapped canonical provision and destroy wrapper symbols.
- Create `scripts/lib/scope-verifiers.d/40-boomi-runtime.sh`: foundation-validate and source both Boomi-owned read-only internal libraries, `verifiers.sh` and `pre-destroy-guards.sh`, and alone define the exact pre-mapped canonical verification wrapper symbols used by public unified verification plus the exact foundation-pre-mapped pre-destroy guard wrapper. That wrapper records the computed in-memory result through foundation `record_pre_destroy_guard_result` exactly once; the guard is not a public verification mode.
- Implement secret-safe diagnostic collection as a lifecycle function in `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`; verifier and pre-destroy guard paths never create diagnostics or other artifacts.
- Modify `platform-prerequisites/terraform/signoz-observability/alerts.tf`: add Boomi runtime availability and restart alerts.
- Modify `platform-prerequisites/terraform/signoz-observability/variables.tf`: add environment and Boomi namespace selectors if Phase 3 has not already added them.
- Create `docs/references/boomi-runtime-contract.md`: component-owned runtime, operation, verification, recovery, and evidence contract. Shared README, runbook, setup, verification, recovery, and index edits belong to the final documentation work package and are excluded here.
- Create `tests/boomi_runtime/__init__.py`, `test_manifest_contract.py`, `test_runtime_script.py`, and `test_orchestration_contract.py`: offline/static regression suite.

Read-only comparison sources are never modified:

- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_statefulset.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_service.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pv.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pvclaim.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_secret.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_storageclass.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_hpa.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_cluster.yaml`
- `/Users/frank/sml/Boomi/boomi-infra/infra/`
- Official sources listed in `docs/superpowers/specs/2026-07-21-uat-platform-consolidation-design.md`, accessed again on the implementation date.

Command classifications used throughout this plan; every class remains **AUTHORIZED ONLY** under the uniform boundary above:

- **OFFLINE, AUTHORIZED ONLY:** reads files, renders manifests, runs unit tests, formats, lints, or validates schemas; no AWS or Kubernetes mutation.
- **UAT READ-ONLY, AUTHORIZED ONLY:** requires `--env uat`, `PROMOTION_MODE=uat-build`, `BOOMI_NAMESPACE=boomi-uat`, account `672172129937`, Region `ap-east-1`, and canonical cluster ARN; may read AWS/Kubernetes/SigNoz state only after explicit authorization.
- **UAT MUTATION, AUTHORIZED ONLY:** may run only after the platform owner approves the exact step and all fail-closed preflight checks pass. Never substitute `dev`.
- **FORBIDDEN IN PHASE 2:** any `--env dev` provision, bootstrap, scale, delete, apply, patch, rollout, or destroy command; any modification beneath `/Users/frank/sml/Boomi/`; any Boomi-local attempt to override `PROMOTION_MODE` or foundation authorization.

### Task 1: Add Boomi Rows To The Canonical Imported-Code Matrix

**Files:**
- Modify: `docs/operations/imported-code-review-matrix.md`
- Create: `docs/references/boomi-runtime-official-evidence.md`
- Create: `docs/references/boomi-runtime-communication-decision.md`
- Test: `tests/boomi_runtime/test_manifest_contract.py`

- [ ] **Step 1: Write the failing documentation-contract test**

Create `tests/boomi_runtime/__init__.py` as an empty file. Create `tests/boomi_runtime/test_manifest_contract.py` with this initial test:

```python
import unittest
import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MATRIX = REPO_ROOT / "docs/operations/imported-code-review-matrix.md"
EVIDENCE = REPO_ROOT / "docs/references/boomi-runtime-official-evidence.md"
DECISION = REPO_ROOT / "docs/references/boomi-runtime-communication-decision.md"
VALIDATOR = REPO_ROOT / "scripts/validate-imported-code-review-matrix.py"

SPEC = importlib.util.spec_from_file_location("matrix_validator", VALIDATOR)
matrix_validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(matrix_validator)


class BoomiReferenceContractTests(unittest.TestCase):
    def test_matrix_classifies_every_legacy_runtime_file(self):
        text = MATRIX.read_text(encoding="utf-8")
        expected = {
          "BOOMI-0001": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_statefulset.yaml", "REWRITE", "REVIEWED"),
          "BOOMI-0002": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_service.yaml", "REPLACE", "REVIEWED"),
          "BOOMI-0003": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pv.yaml", "REWRITE", "REVIEWED"),
          "BOOMI-0004": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pvclaim.yaml", "REWRITE", "REVIEWED"),
          "BOOMI-0005": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_secret.yaml", "REJECT", "REVIEWED"),
          "BOOMI-0006": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_storageclass.yaml", "REPLACE", "REVIEWED"),
          "BOOMI-0007": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_hpa.yaml", "REJECT", "REVIEWED"),
          "BOOMI-0008": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_cluster.yaml", "REPLACE", "REVIEWED"),
          "BOOMI-0009": ("/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_ca.yaml", "REPLACE", "REVIEWED"),
          "BOOMI-0010": ("/Users/frank/sml/Boomi/boomi-infra/infra/", "REJECT", "REVIEWED"),
        }
        parsed = matrix_validator.parse_matrix(MATRIX)
        matrix_validator.validate_rows(parsed)
        rows = {
            row["ID"]: row
            for row in parsed
            if row["Domain"] == "BOOMI"
        }
        self.assertEqual(set(rows), set(expected))
        for row_id, (source, disposition, status) in expected.items():
            with self.subTest(row_id=row_id):
                self.assertEqual(rows[row_id]["Source"], source)
                self.assertEqual(rows[row_id]["Disposition"], disposition)
                self.assertEqual(rows[row_id]["Status"], status)

    def test_communication_decision_starts_blocked(self):
        text = DECISION.read_text(encoding="utf-8")
        self.assertIn("**Status:** Decision required", text)
        self.assertIn("`tcp-7800`", text)
        self.assertIn("`multicast-45588`", text)
        self.assertIn("UAT acceptance readiness is blocked", text)

    def test_focused_evidence_is_supporting_only(self):
        text = EVIDENCE.read_text(encoding="utf-8")
        self.assertIn("**Status:** Supporting evidence only", text)
        self.assertIn("docs/operations/imported-code-review-matrix.md", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract -v
```

Expected: failure because the canonical matrix lacks the Boomi rows and the supporting evidence file is absent.

- [ ] **Step 3: Add exact comparison rows to the canonical matrix**

Load `parse_matrix` and `validate_rows` from the foundation-owned `scripts/validate-imported-code-review-matrix.py` with `importlib`, as shown. Do not parse Markdown with a second regex or alternate column reader. The foundation validator enforces the exact `ID | Domain | Source | Target | Disposition | Evidence | Status` header; validate all rows through it, then select the `Domain == "BOOMI"` rows for the assertions above.

Append the Boomi legacy-source rows to `docs/operations/imported-code-review-matrix.md` using exactly its seven columns. Use stable IDs `BOOMI-0001` through `BOOMI-0010`, domain `BOOMI`, uppercase disposition values, non-empty evidence, and status `REVIEWED`. Do not create another matrix or change the foundation validator:

**Boomi Runtime Imported-Code Review Rows**

**Reviewed:** 2026-07-22
**Target:** Standard private Boomi runtime cluster on UAT EKS
**Image family:** Official `boomi/molecule` version 5

Create `docs/references/boomi-runtime-official-evidence.md` for the following precedence, invariants, baseline decisions, and official links. Begin it with:

```markdown
# Boomi Runtime Official Evidence

**Status:** Supporting evidence only
**Canonical imported-code decisions:** `docs/operations/imported-code-review-matrix.md`
```

Then preserve:

**Precedence**

1. Current Boomi Help and the `officialboomi/runtime-containers` EKS reference.
2. Current Kubernetes and AWS EKS/EFS documentation where Boomi is silent.
3. Proven behavior in `/Users/frank/sml/Boomi/boomi-infra/`.
4. Existing repository conventions.
5. `/Users/frank/sml/Boomi/boomi-infra/infra/` only as an untrusted review input.

**Official Invariants**

| Invariant | Target implementation | Verification |
|---|---|---|
| Standard private runtime, not Runtime Cloud | `boomi/molecule:release`; no runtime-cloud Helm chart | Rendered image and absence tests |
| Three stable identities | StatefulSet replicas `3`; `ATOM_LOCALHOSTID` from `metadata.name` | Manifest test and live ordinal check |
| One runtime name | Overlay sets one `BOOMI_ATOMNAME` for all ordinals | Render and live env check |
| Shared installation | One EFS CSI RWX PVC at `/mnt/boomi` | Render, mount, and concurrent marker test |
| Filesystem ownership | Pod/container UID, GID, and `fsGroup` are `1000`; EFS access point root is `1000:1000` | Manifest and UAT write test |
| Short-lived token | Token exists only in `boomi-install-token` during ordinal-0 bootstrap | Mocked shell and live Secret-absence check |
| Health endpoints | `/_admin/readiness` and `/_admin/liveness` on `9090` | Manifest and live HTTP probe checks |
| Graceful shutdown | `terminationGracePeriodSeconds: 900` | Manifest and timed drain test |
| No all-node restart | Ordered StatefulSet rolling update plus PDB `minAvailable: 2` | Manifest and drain/upgrade tests |
| JVM headroom | UAT request `4Gi`, limit `6Gi`; no heap override above request | Render and runtime evidence |
| Explicit communication mode | Apply blocked until decision is `tcp-7800` or `multicast-45588` | Script unit test and decision record |
| No initial Flux ownership | Boomi path is absent from Flux Kustomizations/HelmReleases | Static ownership test |
| Fixed baseline size | No HPA; steady state is exactly three replicas | Static and live tests |

**Required Canonical Matrix Rows**

| ID | Domain | Source | Target | Disposition | Evidence | Status |
|---|---|---|---|---|---|---|
| BOOMI-0001 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_statefulset.yaml` | `gitops/boomi-runtime/base/statefulset.yaml` | REWRITE | Preserve official image, probes, pod-derived host ID, RWX mount, and 900-second grace; remove hard-coded runtime name and steady-state token reference; add UID/GID 1000, safe updates, topology, and telemetry labels. | REVIEWED |
| BOOMI-0002 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_service.yaml` | `gitops/boomi-runtime/base/services.yaml` | REPLACE | Reject default public NLB; use headless cluster discovery and internal ClusterIP administration services. External ingress requires a separate approved exposure design. | REVIEWED |
| BOOMI-0003 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pv.yaml` | `gitops/boomi-runtime/base/storage.yaml` | REWRITE | Preserve EFS CSI, RWX, and Retain; source the UAT filesystem/access-point handle from the approved platform output, never a copied ID. | REVIEWED |
| BOOMI-0004 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_pvclaim.yaml` | `gitops/boomi-runtime/base/storage.yaml` | REWRITE | Preserve one shared RWX claim; environment-qualify names and labels. | REVIEWED |
| BOOMI-0005 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_secret.yaml` | `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` | REJECT | Legacy file contains a plaintext consumed token; create the transient Secret from protected stdin only and remove it before scale-out. | REVIEWED |
| BOOMI-0006 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_storageclass.yaml` | `gitops/boomi-runtime/base/storage.yaml` | REPLACE | EFS and CSI ownership belongs to `eks-platform`; the workload must not create a second storage owner. | REVIEWED |
| BOOMI-0007 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_hpa.yaml` | `gitops/boomi-runtime/base/statefulset.yaml` | REJECT | HPA and scale-down remain disabled until queue behavior and Boomi support guidance are separately approved. | REVIEWED |
| BOOMI-0008 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_cluster.yaml` | `platform-prerequisites/terraform/eks-platform/` | REPLACE | Cluster, VPC, nodes, IAM, and add-ons are Phase 1 Terraform ownership; do not apply legacy `eksctl` configuration. | REVIEWED |
| BOOMI-0009 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/boomi_molecule_eks_ca.yaml` | `gitops/operators/base/` | REPLACE | Reject node-role credentials and copied cluster settings; use platform-controller ownership and Pod Identity. | REVIEWED |
| BOOMI-0010 | BOOMI | `/Users/frank/sml/Boomi/boomi-infra/infra/` | `gitops/boomi-runtime/` | REJECT | Untested AI-assisted migration is review evidence only and is not copied or applied. | REVIEWED |

**Intentional Baseline Decisions**

- Service exposure is cluster-internal only. Port `9090` is not internet-facing.
- TLS termination is not fabricated at the workload. Internal `9090` traffic remains inside the UAT VPC/cluster; any external endpoint requires a separate ingress, certificate, DNS, source-CIDR, and Boomi topology approval.
- Flux does not own or reconcile any Boomi runtime resource in this phase.
- `boomi/molecule:release-rhel` is excluded unless SAP JCo is confirmed and the image choice is separately reviewed.
- Image digest evidence is recorded at UAT apply time because the official moving `release` selector is required by the approved design; unattended image updates are disabled.

**Official Sources**

Use the exact official links and access date listed under “Official Boomi References” in `docs/superpowers/specs/2026-07-21-uat-platform-consolidation-design.md`. Record changed official behavior in this supporting evidence and update the canonical imported-code matrix row in the same reviewed change before changing manifests.

Create `docs/references/boomi-runtime-communication-decision.md`:

```markdown
# Boomi Runtime Cluster Communication Decision

**Status:** Decision required
**Decision owner:** Infra Admin / Enterprise Architect
**Required evidence:** Current Boomi Support response plus current official EKS reference behavior

UAT acceptance readiness is blocked until this record is changed in a reviewed commit to exactly one approved value:

- `tcp-7800`: unicast TCP on port `7800` through the headless StatefulSet service.
- `multicast-45588`: multicast UDP on port `45588`, only with evidence that the selected EKS CNI/network path supports the required multicast behavior.

The approval commit must record the support case/reference, decision date, selected value, EKS/Kubernetes version, CNI version, and rollback value. Absence of evidence is not readiness. This decision cannot authorize mutation, cannot change `PROMOTION_MODE`, and cannot enable dev. The implementation must not infer the mode from a live cluster, legacy manifest, or default container behavior.
```

- [ ] **Step 4: Run the contract test**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract -v
```

Expected: both tests pass with `OK`.

- [ ] **Step 5: Commit the reference baseline**

```bash
git add docs/operations/imported-code-review-matrix.md docs/references/boomi-runtime-official-evidence.md docs/references/boomi-runtime-communication-decision.md tests/boomi_runtime/__init__.py tests/boomi_runtime/test_manifest_contract.py
git commit -m "docs: define Boomi runtime reference baseline"
```

### Task 2: Add The Runtime Configuration Fragment

**Files:**
- Create: `config/environment-schema/fragments/40-boomi-runtime.manifest`
- Create: `config/environments/dev.local/boomi-runtime.json.example`
- Create: `config/environments/uat.local/boomi-runtime.json.example`
- Create: `tests/boomi_runtime/test_configuration_contract.py`

- [ ] **Step 1: Add failing fragment, readiness, and promotion-boundary tests**

Use the foundation test fixture and parser APIs. Assert that:

```python
class BoomiRuntimeConfigurationTests(unittest.TestCase):
  def test_configuration_fragment_loads_uat_runtime_contract(self):
    values = self.load_environment_with_local_example("uat", "boomi-runtime")
    self.assertEqual(values["BOOMI_RUNTIME_NAME"], "oms-uat-runtime")
    self.assertEqual(values["BOOMI_STEADY_REPLICAS"], "3")
    self.assertEqual(values["BOOMI_COMMUNICATION_MODE"], "decision-required")

  def test_dev_uses_canonical_namespace_and_remains_modeled(self):
    values = self.load_environment_with_local_example("dev", "boomi-runtime")
    self.assertEqual(values["BOOMI_NAMESPACE"], "boomi")
    self.assertEqual(values["PROMOTION_MODE"], "modeled")

  def test_uat_uses_canonical_namespace_and_promotion_mode(self):
    values = self.load_environment_with_local_example("uat", "boomi-runtime")
    self.assertEqual(values["BOOMI_NAMESPACE"], "boomi-uat")
    self.assertEqual(values["PROMOTION_MODE"], "uat-build")

  def test_communication_decision_is_readiness_not_authorization(self):
    result = self.run_internal_handler(
      environment="dev",
      promotion_mode="modeled",
      communication_mode="tcp-7800",
    )
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("PROMOTION_MODE=modeled", result.stderr)
    self.assertFalse(self.command_log.exists())

  def test_fragment_defines_no_component_mutation_flag(self):
    text = self.schema_fragment.read_text(encoding="utf-8")
    self.assertNotIn("BOOMI_MUTATION_ENABLED", text)
```

Also assert that the fragment cannot declare or replace immutable `ENVIRONMENT`, account, Region, namespace, state, or `PROMOTION_MODE` values; duplicate/unknown keys fail through the canonical parser; and neither example contains a token, EFS ID, cluster ARN, credential, or executable value. Tests exercise the existing parser as a consumer but do not modify parser tests or shared schema files.

- [ ] **Step 2: Run only after explicit test authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_configuration_contract -v
```

Expected: new tests fail because the Boomi fragment and examples are absent. No AWS, Kubernetes, local lock, or mutation command is invoked.

- [ ] **Step 3: Add a closed Bash 3.2-compatible schema fragment**

Create exactly `config/environment-schema/fragments/40-boomi-runtime.manifest` using the declarative grammar delivered by the foundation. The fragment owns only these non-secret component keys and foundation validator names:

```text
BOOMI_RUNTIME_NAME
BOOMI_IMAGE
BOOMI_STEADY_REPLICAS
BOOMI_CPU_REQUEST
BOOMI_CPU_LIMIT
BOOMI_MEMORY_REQUEST
BOOMI_MEMORY_LIMIT
BOOMI_COMMUNICATION_MODE
BOOMI_SERVICE_EXPOSURE
BOOMI_TLS_MODE
BOOMI_TERMINATION_GRACE_SECONDS
```

Do not add `BOOMI_MUTATION_ENABLED`, a second environment selector, account/Region values, namespace values, EFS output values, authorization state, executable shell, or new validator code. Do not edit `config/environment-schema/base.manifest`, `scripts/lib/platform-env.sh`, any shared parser/schema registry, or any other schema fragment.

Validate exact enums and fixed invariants: image `boomi/molecule:release`, replicas `3`, communication `decision-required|tcp-7800|multicast-45588`, exposure `cluster-internal`, TLS mode `cluster-internal-plain-http`, and grace period `900`. Runtime handlers obtain namespace from canonical `BOOMI_NAMESPACE`, EFS handles from the EKS platform output API, and mutation permission from the foundation's `PROMOTION_MODE` and authorization APIs.

- [ ] **Step 4: Create canonical local JSON examples**

Create both files at `config/environments/<env>.local/boomi-runtime.json.example`. They use the schema-fragment API's exact JSON shape. UAT models `oms-uat-runtime`; dev models `oms-dev-runtime`. Dev's namespace remains the foundation-owned `BOOMI_NAMESPACE=boomi` and is not repeated or overridden in JSON. Both examples use `decision-required` and contain no EFS handle or mutation flag.

Actual operator inputs, when separately authorized, are copied to `config/environments/<env>.local/boomi-runtime.json`, mode `0600`, and remain ignored. The examples themselves are committed and non-secret.

- [ ] **Step 5: Run focused configuration checks only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_configuration_contract -v
```

Expected: syntax and tests pass; approved communication can satisfy a readiness predicate, but dev still fails at the foundation promotion gate and no component flag can authorize it.

- [ ] **Step 6: Commit only after commit authorization**

```bash
git add config/environment-schema/fragments/40-boomi-runtime.manifest config/environments/dev.local/boomi-runtime.json.example config/environments/uat.local/boomi-runtime.json.example tests/boomi_runtime/test_configuration_contract.py
git commit -m "feat: add Boomi runtime configuration"
```

### Task 3: Build The Invariant Kubernetes Base

**Files:**
- Create: `gitops/boomi-runtime/base/kustomization.yaml`
- Create: `gitops/boomi-runtime/base/serviceaccount.yaml`
- Create: `gitops/boomi-runtime/base/services.yaml`
- Create: `gitops/boomi-runtime/base/storage.yaml`
- Create: `gitops/boomi-runtime/base/statefulset.yaml`
- Create: `gitops/boomi-runtime/base/pdb.yaml`
- Modify: `tests/boomi_runtime/test_manifest_contract.py`

- [ ] **Step 1: Add failing base-manifest tests**

Append a `BoomiManifestContractTests` class. Use `subprocess.run(["kustomize", "build", str(self.base)], text=True, capture_output=True, check=True)` and `yaml.safe_load_all` only if PyYAML is already a declared repository dependency; otherwise inspect the rendered YAML as text to avoid adding an unnecessary package. Assert all of these exact tokens:

```python
class BoomiManifestContractTests(unittest.TestCase):
    def setUp(self):
        self.base = REPO_ROOT / "gitops/boomi-runtime/base"

    def test_statefulset_preserves_official_runtime_invariants(self):
        text = (self.base / "statefulset.yaml").read_text(encoding="utf-8")
        for token in (
            "image: boomi/molecule:release",
            "replicas: 3",
            "terminationGracePeriodSeconds: 900",
            "mountPath: /mnt/boomi",
            "runAsUser: 1000",
            "runAsGroup: 1000",
            "fsGroup: 1000",
            "path: /_admin/readiness",
            "path: /_admin/liveness",
            "fieldPath: metadata.name",
            "podManagementPolicy: OrderedReady",
            "type: RollingUpdate",
        ):
            self.assertIn(token, text)
        self.assertNotIn("INSTALL_TOKEN", text)
        self.assertNotIn("boomi/cloud", text)

    def test_storage_is_shared_retained_efs(self):
        text = (self.base / "storage.yaml").read_text(encoding="utf-8")
        for token in (
            "driver: efs.csi.aws.com",
            "ReadWriteMany",
            "persistentVolumeReclaimPolicy: Retain",
            "volumeHandle: BOOMI_EFS_VOLUME_HANDLE",
        ):
            self.assertIn(token, text)

    def test_pdb_keeps_two_nodes_available(self):
        text = (self.base / "pdb.yaml").read_text(encoding="utf-8")
        self.assertIn("minAvailable: 2", text)
```

- [ ] **Step 2: Run the test to verify it fails**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract.BoomiManifestContractTests -v
```

Expected: `ERROR` because `gitops/boomi-runtime/base/statefulset.yaml` is absent.

- [ ] **Step 3: Create the base inventory and identity**

Create `gitops/boomi-runtime/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - serviceaccount.yaml
  - services.yaml
  - storage.yaml
  - statefulset.yaml
  - pdb.yaml
  - networkpolicy.yaml
commonLabels:
  app.kubernetes.io/name: boomi-runtime
  app.kubernetes.io/part-of: oms-platform
```

Create `gitops/boomi-runtime/base/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: boomi-runtime
automountServiceAccountToken: false
```

- [ ] **Step 4: Create internal services and retained EFS storage**

Create `gitops/boomi-runtime/base/services.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: boomi-runtime-headless
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: boomi-runtime
  ports:
    - name: admin
      port: 9090
      targetPort: admin
---
apiVersion: v1
kind: Service
metadata:
  name: boomi-runtime-admin
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: boomi-runtime
  ports:
    - name: admin
      port: 9090
      targetPort: admin
```

Create `gitops/boomi-runtime/base/storage.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: boomi-runtime-shared
spec:
  capacity:
    storage: 25Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: boomi-runtime-efs
  mountOptions:
    - tls
  csi:
    driver: efs.csi.aws.com
    volumeHandle: BOOMI_EFS_VOLUME_HANDLE
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: boomi-runtime-shared
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: boomi-runtime-efs
  volumeName: boomi-runtime-shared
  resources:
    requests:
      storage: 25Gi
```

The Phase 1 EFS access point must enforce POSIX user/group `1000:1000` and root permissions `0770`; verify that output before applying this PV. Do not create EFS or its access point from Kubernetes.

- [ ] **Step 5: Create the steady-state StatefulSet and PDB**

Create `gitops/boomi-runtime/base/statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: boomi-runtime
spec:
  serviceName: boomi-runtime-headless
  replicas: 3
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: boomi-runtime
  template:
    metadata:
      labels:
        app.kubernetes.io/name: boomi-runtime
        app.kubernetes.io/component: runtime-node
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
    spec:
      serviceAccountName: boomi-runtime
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 900
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app.kubernetes.io/name: boomi-runtime
              topologyKey: kubernetes.io/hostname
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: boomi-runtime
                topologyKey: topology.kubernetes.io/zone
      containers:
        - name: runtime
          image: boomi/molecule:release
          imagePullPolicy: Always
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          ports:
            - name: admin
              containerPort: 9090
              protocol: TCP
          env:
            - name: BOOMI_ATOMNAME
              value: BOOMI_RUNTIME_NAME
            - name: ATOM_LOCALHOSTID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              cpu: 1000m
              memory: 4Gi
            limits:
              cpu: 2000m
              memory: 6Gi
          readinessProbe:
            httpGet:
              path: /_admin/readiness
              port: admin
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /_admin/liveness
              port: admin
            initialDelaySeconds: 60
            periodSeconds: 60
            timeoutSeconds: 5
            failureThreshold: 5
          volumeMounts:
            - name: installation
              mountPath: /mnt/boomi
      volumes:
        - name: installation
          persistentVolumeClaim:
            claimName: boomi-runtime-shared
```

Create `gitops/boomi-runtime/base/pdb.yaml`:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: boomi-runtime
spec:
  minAvailable: 2
  unhealthyPodEvictionPolicy: IfHealthyBudget
  selector:
    matchLabels:
      app.kubernetes.io/name: boomi-runtime
```

- [ ] **Step 6: Run focused tests and render the base**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract.BoomiManifestContractTests -v
kustomize build gitops/boomi-runtime/base >/dev/null
```

Expected: tests report `OK`; Kustomize exits `0`.

- [ ] **Step 7: Commit the invariant base**

```bash
git add gitops/boomi-runtime/base tests/boomi_runtime/test_manifest_contract.py
git commit -m "feat: add Boomi runtime Kubernetes base"
```

### Task 4: Add Dev/UAT Overlays And Communication Readiness

**Files:**
- Create: `gitops/boomi-runtime/overlays/dev/kustomization.yaml`
- Create: `gitops/boomi-runtime/overlays/dev/patch-runtime.yaml`
- Create: `gitops/boomi-runtime/overlays/uat/kustomization.yaml`
- Create: `gitops/boomi-runtime/overlays/uat/patch-runtime.yaml`
- Create: `gitops/boomi-runtime/components/tcp-7800/kustomization.yaml`
- Create: `gitops/boomi-runtime/components/tcp-7800/patch-communication.yaml`
- Create: `gitops/boomi-runtime/components/multicast-45588/kustomization.yaml`
- Create: `gitops/boomi-runtime/components/multicast-45588/patch-communication.yaml`
- Modify: `tests/boomi_runtime/test_manifest_contract.py`

- [ ] **Step 1: Add failing overlay and ownership tests**

Add tests that run `kustomize build` for both overlays and assert:

```python
    def test_uat_overlay_has_only_uat_identity(self):
        rendered = subprocess.run(
            ["kustomize", "build", str(REPO_ROOT / "gitops/boomi-runtime/overlays/uat")],
            text=True, capture_output=True, check=True,
        ).stdout
        self.assertIn("namespace: boomi-uat", rendered)
        self.assertIn("value: oms-uat-runtime", rendered)
        self.assertNotIn("namespace: boomi\n", rendered)
        self.assertNotIn("INSTALL_TOKEN", rendered)

    def test_dev_overlay_is_renderable_without_live_identifiers(self):
        rendered = subprocess.run(
            ["kustomize", "build", str(REPO_ROOT / "gitops/boomi-runtime/overlays/dev")],
            text=True, capture_output=True, check=True,
        ).stdout
        self.assertIn("namespace: boomi", rendered)
        self.assertIn("value: oms-dev-runtime", rendered)
        self.assertIn("model-only-no-live-resolution", rendered)

    def test_flux_does_not_own_boomi_runtime(self):
        flux_text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (REPO_ROOT / "gitops").rglob("*.yaml")
            if "boomi-runtime" not in path.parts
        )
        self.assertNotIn("path: ./gitops/boomi-runtime", flux_text)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract.BoomiManifestContractTests -v
```

Expected: overlay tests fail because the overlay directories do not exist.

- [ ] **Step 3: Create exact environment overlays**

Each overlay references `../../base`, sets `namespace`, creates the Namespace, replaces `BOOMI_RUNTIME_NAME` and the render-time EFS placeholder, and sets the approved resource values. UAT uses `boomi-uat`, `oms-uat-runtime`, and the concrete EFS `filesystem-id::access-point-id` returned by the EKS platform output API. The committed patch must never contain a live identifier. Register the generated patch with the foundation artifact API under `.local/uat/generated/boomi-runtime.<pid>.patch-platform-output.yaml`, mode `0600`, and include it only in the temporary render directory. Dev uses namespace `boomi` and a model-only placeholder.

The committed UAT `patch-runtime.yaml` is:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: boomi-runtime
spec:
  template:
    metadata:
      labels:
        environment: uat
    spec:
      containers:
        - name: runtime
          env:
            - name: BOOMI_ATOMNAME
              value: oms-uat-runtime
          resources:
            requests:
              cpu: 1000m
              memory: 4Gi
            limits:
              cpu: 2000m
              memory: 6Gi
```

The dev patch is identical except `environment: dev` and `BOOMI_ATOMNAME: oms-dev-runtime`. Its generated platform-output patch always contains `model-only-no-live-resolution` and is used only by offline render tests.

- [ ] **Step 4: Create the two closed communication components**

The TCP component adds named TCP port `7800` to the headless Service and runtime container, and adds the exact Boomi-supported communication property documented in the approved decision record. The multicast component adds UDP port `45588` to the runtime container and NetworkPolicy and adds the exact Boomi-supported property from the same record. Do not merge either component into an environment overlay while the record status is `Decision required`.

Use these component inventories:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
  - path: patch-communication.yaml
```

The plan intentionally does not invent the Boomi property syntax before support evidence exists. The implementation is complete only when the decision record changes to `Approved: tcp-7800` or `Approved: multicast-45588`, includes the exact property/value supplied by Boomi, and the selected component contains that exact value. This is a decision gate, not an implementation placeholder: all offline work may pass while UAT mutation must fail closed.

- [ ] **Step 5: Add the network policy with selected-mode patching**

Create `gitops/boomi-runtime/base/networkpolicy.yaml` with default-deny ingress/egress, DNS egress to `kube-system`, TCP `9090` ingress only from pods in the selected canonical `BOOMI_NAMESPACE` carrying `boomi-runtime-client=true` and from the canonical SigNoz namespace, and same-workload communication supplied only by the selected component. Do not permit `0.0.0.0/0`, create a LoadBalancer/Ingress, or expose the probe endpoint publicly.

- [ ] **Step 6: Run overlay tests only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract -v
kustomize build gitops/boomi-runtime/overlays/dev >/dev/null
kustomize build gitops/boomi-runtime/overlays/uat >/dev/null
rg -n 'LoadBalancer|0\.0\.0\.0/0|INSTALL_TOKEN|boomi/cloud|kind: (HelmRelease|Kustomization).*boomi' gitops/boomi-runtime gitops/operators gitops/signoz
```

Expected: unit tests pass; both renders exit `0`; `rg` finds no forbidden exposure, token, cloud image, or Flux ownership. A literal Kustomize config `kind: Kustomization` inside the runtime directory is expected and must not be confused with a Flux `kustomize.toolkit.fluxcd.io` resource.

- [ ] **Step 7: Commit overlays and communication gates**

```bash
git add gitops/boomi-runtime tests/boomi_runtime/test_manifest_contract.py
git commit -m "feat: add guarded Boomi runtime overlays"
```

### Task 5: Implement Secret-Safe Internal Runtime Handlers

**Files:**
- Create: `gitops/boomi-runtime/bootstrap/kustomization.yaml`
- Create: `gitops/boomi-runtime/bootstrap/patch-bootstrap.yaml`
- Create: `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`
- Create: `scripts/lib/scope-handlers.d/40-boomi-runtime.sh`
- Create: `tests/boomi_runtime/test_runtime_script.py`

- [ ] **Step 1: Write failing mocked bootstrap tests**

Create `tests/boomi_runtime/test_runtime_script.py` using the existing `TemporaryDirectory`, mock-bin, and command-log pattern from `tests/uat_access/test_platform_env.py`. Cover these exact cases:

```python
class BoomiRuntimeScriptTests(unittest.TestCase):
  def assert_rejected_before_kubectl(self, result, message):
    self.assertNotEqual(result.returncode, 0)
    self.assertIn(message, result.stderr)
    self.assertFalse(self.kubectl_log.exists())

  def test_missing_token_fails_before_kubectl_mutation(self):
    result = self.run_runtime(token=None)
    self.assert_rejected_before_kubectl(result, "BOOMI_INSTALL_TOKEN is required")

  def test_sample_token_fails_before_kubectl_mutation(self):
    result = self.run_runtime(token="sample-token-value-not-valid")
    self.assert_rejected_before_kubectl(result, "sample or placeholder token")

  def test_unapproved_communication_mode_fails_before_kubectl_mutation(self):
    result = self.run_runtime(token=self.valid_token, mode="decision-required")
    self.assert_rejected_before_kubectl(result, "communication decision is not approved")

  def test_wrong_account_fails_before_kubectl_mutation(self):
    result = self.run_runtime(token=self.valid_token, account="815402439714")
    self.assert_rejected_before_kubectl(result, "expected 672172129937")

  def test_wrong_cluster_arn_fails_before_kubectl_mutation(self):
    result = self.run_runtime(
      token=self.valid_token,
      cluster_arn="arn:aws:eks:ap-east-1:815402439714:cluster/EKS-boomi-runtime-cluster",
    )
    self.assert_rejected_before_kubectl(result, "does not target UAT")

  def test_bootstrap_creates_secret_without_token_in_arguments_or_log(self):
    result = self.run_runtime(token=self.valid_token)
    self.assertEqual(result.returncode, 0, result.stderr)
    log = self.kubectl_log.read_text(encoding="utf-8")
    self.assertIn("--from-file=install_token=/dev/stdin", log)
    self.assertNotIn(self.valid_token, log + result.stdout + result.stderr)

  def test_bootstrap_applies_one_replica_before_waiting_for_ordinal_zero(self):
    result = self.run_runtime(token=self.valid_token)
    self.assertEqual(result.returncode, 0, result.stderr)
    log = self.kubectl_log.read_text(encoding="utf-8")
    self.assertLess(log.index("apply -f -"), log.index("rollout status statefulset/boomi-runtime"))
    self.assertLess(log.index("rollout status statefulset/boomi-runtime"), log.index("--replicas=3"))

  def test_success_removes_token_reference_before_secret_deletion(self):
    result = self.run_runtime(token=self.valid_token)
    self.assertEqual(result.returncode, 0, result.stderr)
    actions = self.action_log.read_text(encoding="utf-8").splitlines()
    self.assertLess(actions.index("apply-steady-one"), actions.index("delete-bootstrap-secret"))

  def test_success_restarts_ordinal_zero_without_token_before_scaling_to_three(self):
    result = self.run_runtime(token=self.valid_token)
    self.assertEqual(result.returncode, 0, result.stderr)
    actions = self.action_log.read_text(encoding="utf-8").splitlines()
    self.assertLess(actions.index("restart-ordinal-zero"), actions.index("scale-steady-three"))
    self.assertLess(actions.index("verify-ordinal-zero-no-token"), actions.index("scale-steady-three"))

  def test_failure_never_scales_past_one_and_collects_diagnostics(self):
    result = self.run_runtime(token=self.valid_token, ordinal_zero_ready=False)
    self.assertNotEqual(result.returncode, 0)
    log = self.kubectl_log.read_text(encoding="utf-8")
    self.assertNotIn("--replicas=3", log)
    self.assertIn("collect-diagnostics", self.action_log.read_text(encoding="utf-8"))

  def test_dev_bootstrap_is_always_rejected(self):
    result = self.run_runtime(token=self.valid_token, environment="dev")
    self.assert_rejected_before_kubectl(
      result,
      "ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled",
    )
```

The test harness defines `self.valid_token = "molecule-unit-test-token-0123456789"`, `self.kubectl_log`, and `self.action_log`. Its `run_runtime` helper loads the foundation fixture and sources the Boomi handler fragment under foundation validation. Mapping-dispatch tests invoke the fragment-owned canonical `provision_boomi_runtime_scope` wrapper; focused phase tests invoke the distinctly named internal `boomi_internal_lifecycle_bootstrap_runtime` function with an already validated environment and already-held orchestration lock. Tests assert the canonical wrapper delegates to `boomi_internal_lifecycle_provision_runtime`, that the handler fragment does not source `verifiers.sh` or `pre-destroy-guards.sh`, and that `lifecycle.sh` defines no canonical provision, verification, pre-destroy guard, or destroy wrapper symbol and no `boomi_internal_verifier_*` or `boomi_internal_pre_destroy_guard_*` function. Mock `aws` and `kubectl` return the requested canonical identities and deterministic readiness responses. The production lifecycle library writes phase names to `BOOMI_RUNTIME_ACTION_LOG` only when that variable is set by tests; normal runs do not create this test trace.

Tests must additionally prove the handlers reject direct invocation without the foundation dispatch context, never call `acquire_environment_lock`, never parse `--env`, never inspect or alter `PROMOTION_MODE`, and contain only Bash 3.2-compatible syntax.

The successful command log must have this order and must not contain the token value:

```text
aws sts get-caller-identity --query Account --output text
kubectl config current-context
kubectl config view --minify -o jsonpath={.contexts[0].context.cluster}
kubectl -n boomi-uat create secret generic boomi-install-token --from-file=install_token=/dev/stdin --dry-run=client -o yaml
kubectl apply -f -
kubectl apply -f -
kubectl -n boomi-uat rollout status statefulset/boomi-runtime --timeout=30m
kubectl -n boomi-uat get pod boomi-runtime-0 -o jsonpath={.status.containerStatuses[0].ready}
kubectl apply -f -
kubectl -n boomi-uat delete secret boomi-install-token --ignore-not-found=true
kubectl -n boomi-uat delete pod boomi-runtime-0 --wait=true --timeout=20m
kubectl -n boomi-uat rollout status statefulset/boomi-runtime --timeout=30m
kubectl -n boomi-uat scale statefulset/boomi-runtime --replicas=3
kubectl -n boomi-uat rollout status statefulset/boomi-runtime --timeout=45m
```

- [ ] **Step 2: Run tests to verify they fail**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_runtime_script -v
```

Expected: tests fail because `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` and the fragment-owned exact pre-mapped lifecycle wrapper symbols do not exist.

- [ ] **Step 3: Create the transient bootstrap patch**

Create `gitops/boomi-runtime/bootstrap/kustomization.yaml` as a Kustomize Component and `patch-bootstrap.yaml` as:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: boomi-runtime
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: runtime
          env:
            - name: INSTALL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: boomi-install-token
                  key: install_token
```

The steady-state render never includes this component.

- [ ] **Step 4: Implement the guarded bootstrap phases**

In `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`, implement these internal handlers and private helpers with `set -euo pipefail` inherited from the foundation orchestrator. Every function defined by this library uses the distinct `boomi_internal_lifecycle_*` namespace; it must never define a canonical wrapper symbol or a `boomi_internal_verifier_*` or `boomi_internal_pre_destroy_guard_*` function:

```bash
boomi_internal_lifecycle_provision_runtime
boomi_internal_lifecycle_bootstrap_runtime
boomi_internal_lifecycle_destroy_runtime
boomi_internal_lifecycle_require_uat_preflight
boomi_internal_lifecycle_resolve_platform_output_patch
boomi_internal_lifecycle_render_steady_state
boomi_internal_lifecycle_render_bootstrap_state
boomi_internal_lifecycle_validate_rendered_identity
boomi_internal_lifecycle_validate_empty_installation_or_registered_runtime
boomi_internal_lifecycle_create_install_token_secret
boomi_internal_lifecycle_wait_for_ordinal_zero
boomi_internal_lifecycle_remove_bootstrap_material
boomi_internal_lifecycle_restart_without_token
boomi_internal_lifecycle_scale_steady_state
boomi_internal_lifecycle_collect_diagnostics
boomi_internal_lifecycle_destroy_runtime_resources
```

`boomi_internal_lifecycle_require_uat_preflight` must assert the foundation dispatch context, then call the canonical guard and dependency APIs without reloading configuration or inventing authorization. Provision/bootstrap/destroy handlers require the foundation to have validated `ENVIRONMENT=uat`, immutable account `672172129937`, Region, canonical cluster ARN, operation authorization, and non-dev `PROMOTION_MODE`. All lifecycle handlers reuse the foundation override guard and EKS platform output API; they do not implement duplicate account, context, parser, promotion, public verification, or pre-destroy guard logic.

`boomi_internal_lifecycle_create_install_token_secret` must read `BOOMI_INSTALL_TOKEN` without `set -x`, reject empty values, values containing whitespace/newlines, `changeme`, `example`, `sample`, and values shorter than 20 characters, and use stdin:

```bash
printf '%s' "$BOOMI_INSTALL_TOKEN" \
  | kubectl -n "$BOOMI_NAMESPACE" create secret generic boomi-install-token \
      --from-file=install_token=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f -
```

The bootstrap sequence is exact:

1. Assert the foundation already holds `.local/uat/locks/orchestration.lock`; refuse direct/unlocked invocation and never acquire another lock.
2. Run communication-readiness and dependency checks and verify EFS CSI plus the EKS platform output API's access point `1000:1000` contract.
3. Refuse bootstrap if ordinals `1` or `2` exist.
4. Render and validate the one-replica bootstrap manifest.
5. Create the Secret from protected input and apply the bootstrap render.
6. Wait at most 30 minutes for ordinal `0` readiness and runtime registration evidence.
7. Apply the steady-state manifest at replicas `1`, proving its pod template has no `INSTALL_TOKEN` or Secret reference.
8. Delete `boomi-install-token`.
9. Delete/recreate ordinal `0` once, wait for readiness without the token, and verify it reused the same `ATOM_LOCALHOSTID` and runtime registration.
10. Scale to exactly `3`, wait at most 45 minutes, verify ordinals `0`, `1`, and `2`, and confirm one shared `BOOMI_ATOMNAME` with three unique host IDs.

On any failure, do not delete EFS/PV/PVC or scale above one. Delete the token Secret only after the pod-template token reference is removed; if that cannot be proven, leave the Secret in place, lock the StatefulSet at one replica, collect diagnostics, and print the exact recovery command without the token.

- [ ] **Step 5: Define the pre-mapped wrappers without adding a public command**

Create only `scripts/lib/scope-handlers.d/40-boomi-runtime.sh` for lifecycle wrappers. Under foundation validation, it may source only `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` plus any exact foundation-validated helper library it demonstrably needs, and define the exact canonical `provision_boomi_runtime_scope` and `destroy_boomi_runtime_scope` wrapper symbols already referenced by the immutable foundation mappings. It must not source `verifiers.sh` or `pre-destroy-guards.sh`. Those wrappers delegate only to `boomi_internal_lifecycle_provision_runtime` and `boomi_internal_lifecycle_destroy_runtime`; the lifecycle library never defines canonical wrapper symbols. It must not write, extend, or conditionally alter any mapping. `boomi_internal_lifecycle_bootstrap_runtime` remains a private phase called by `boomi_internal_lifecycle_provision_runtime`; it is not a scope, wrapper, public mode, public option, or standalone executable. Verification wrappers are not defined by this handler fragment. Keep the existing `boomi-runtime` dependency list and canonical `all`/destroy order unchanged without editing either.

The public mutating route remains exactly `bash scripts/provision.sh --env uat boomi-runtime`. The mapped provision handler selects its private bootstrap phase from validated installation state; there is no bootstrap scope, public option, public component mode, or standalone executable. `scripts/provision.sh` remains the sole public mutating entrypoint. Component-only render tests call a pure internal render helper in the test fixture and do not create a public render script.

- [ ] **Step 6: Run focused bootstrap tests**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
bash -n scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/scope-handlers.d/40-boomi-runtime.sh
python3 -m unittest tests.boomi_runtime.test_runtime_script -v
```

Expected: shell syntax exits `0`; all mocked bootstrap tests pass; command logs contain no fixture token.

- [ ] **Step 7: Commit secure bootstrap lifecycle**

```bash
git add gitops/boomi-runtime/bootstrap scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/scope-handlers.d/40-boomi-runtime.sh tests/boomi_runtime/test_runtime_script.py
git commit -m "feat: bootstrap Boomi runtime from ordinal zero"
```

### Task 6: Add Verification, Pre-Destroy Guards, Telemetry, And Failure Diagnostics

**Files:**
- Modify: `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`
- Create: `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh`
- Create: `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh`
- Create: `scripts/lib/scope-verifiers.d/40-boomi-runtime.sh`
- Modify: `platform-prerequisites/terraform/signoz-observability/alerts.tf`
- Modify: `platform-prerequisites/terraform/signoz-observability/variables.tf`
- Modify: `tests/boomi_runtime/test_runtime_script.py`

- [ ] **Step 1: Add failing verification and redaction tests**

Add mocked tests asserting that verification fails for: fewer/more than three pods, non-ready ordinal, duplicate `ATOM_LOCALHOSTID`, inconsistent `BOOMI_ATOMNAME`, missing RWX mount, Secret still present, token reference in StatefulSet, unavailable `/_admin/readiness`, EFS write failure, or simultaneous restart count above one. Add a diagnostic test that seeds `INSTALL_TOKEN=secret-value-never-log` and asserts the generated archive index and captured files do not contain that string or any Kubernetes Secret `.data`/`.stringData` content.

- [ ] **Step 2: Run focused tests to verify they fail**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_runtime_script -v
```

Expected: new tests fail because live verification and diagnostic collection are incomplete.

- [ ] **Step 3: Implement separate read-only verifier and pre-destroy guard libraries**

Create `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh` as the only package implementation for runtime verification. Every function in it uses the distinct `boomi_internal_verifier_*` namespace, performs read-only inspection, and defines no canonical wrapper, `boomi_internal_lifecycle_*`, or `boomi_internal_pre_destroy_guard_*` symbol. It must not source `lifecycle.sh` or `pre-destroy-guards.sh`, call `boomi_internal_lifecycle_collect_diagnostics`, request an artifact/evidence path, create a directory or file, write a report, or mutate AWS/Kubernetes state. Implement these functions and verifier-private read-only helpers there:

```bash
boomi_internal_verifier_verify_runtime
boomi_internal_verifier_verify_runtime_predicates
```

Create `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh` as the only package implementation for Boomi pre-destroy guards. Every function in it uses the disjoint `boomi_internal_pre_destroy_guard_*` namespace, performs read-only inspection, and defines no canonical wrapper, `boomi_internal_lifecycle_*`, or `boomi_internal_verifier_*` symbol. It must not source `lifecycle.sh` or `verifiers.sh`, call lifecycle diagnostics or `record_pre_destroy_guard_result`, request an artifact/evidence path, create a directory or file, read or write a report, or mutate AWS/Kubernetes state. Implement these functions and guard-private read-only helpers there:

```bash
boomi_internal_pre_destroy_guard_verify_boomi_runtime
boomi_internal_pre_destroy_guard_verify_graceful_removal_readiness
boomi_internal_pre_destroy_guard_verify_efs_retain_contract
boomi_internal_pre_destroy_guard_verify_dependencies
boomi_internal_pre_destroy_guard_build_closed_summary
boomi_internal_pre_destroy_guard_digest_closed_summary
```

`boomi_internal_pre_destroy_guard_verify_boomi_runtime` runs all live runtime, graceful-removal, EFS retain-contract, and canonical dependency checks and returns their result through package-owned in-memory variables `BOOMI_PRE_DESTROY_GUARD_RESULT`, `BOOMI_PRE_DESTROY_GUARD_SUMMARY`, and `BOOMI_PRE_DESTROY_GUARD_DIGEST`. It clears all three variables on entry. The summary is a canonical, single-line, secret-safe closed schema containing exactly `schema`, `scope`, `environment`, `result`, `runtime_identity`, `graceful_removal`, `efs_retain`, and `dependencies`; each predicate value is from a closed enum and carries no free-form command output. The digest is the lowercase SHA-256 of the exact summary bytes. The function performs no persistence and returns success only when `result=pass`; failed or indeterminate checks still produce a complete `result=fail` summary and digest for the wrapper to record.

Create only the numbered `scripts/lib/scope-verifiers.d/40-boomi-runtime.sh` fragment for verification and read-only guard wrappers. Under foundation validation, it must validate and source both `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh` and `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh`, plus only any exact foundation-validated read-only helper library they demonstrably need. It alone defines the exact canonical verification wrapper symbols already referenced by immutable `verification_handler_for_slot` mappings plus the foundation-pre-mapped `verify_boomi_runtime_pre_destroy` symbol. It must not source `lifecycle.sh`. The fragment-owned verification wrappers delegate only to `boomi_internal_verifier_verify_runtime`. `verify_boomi_runtime_pre_destroy` invokes `boomi_internal_pre_destroy_guard_verify_boomi_runtime` once, captures its in-memory result without allowing `set -e` to bypass recording, maps the result to exact uppercase `PASS|FAIL`, and calls foundation `record_pre_destroy_guard_result "boomi-runtime" "$BOOMI_PRE_DESTROY_GUARD_STATUS" "runtime/boomi-uat" "$BOOMI_PRE_DESTROY_GUARD_DIGEST" "$BOOMI_PRE_DESTROY_GUARD_SUMMARY_CODE"` exactly once on both pass and fail paths before returning the internal status. It does not call the recorder before computation, from a trap, loop, predicate helper, or retry path. Neither internal library defines canonical wrapper symbols or calls the recorder. The fragment must not write, extend, register, or conditionally alter any mapping. The pre-destroy guard is not a verification slot or public mode, and the fragment adds no `boomi-runtime` public mode or standalone verifier executable. Public verification remains mode-based through exactly all four forms:

```text
bash scripts/verify-platform-health.sh --env <dev|uat> --preflight
bash scripts/verify-platform-health.sh --env <dev|uat> --full
bash scripts/verify-platform-health.sh --env <dev|uat>
bash scripts/verify-platform-health.sh --env <dev|uat> --smoke-test
```

The no-mode form is exactly equivalent to `--full`; it resolves the same immutable verification slots and handlers with no Boomi-owned defaulting or mode branch.

The pre-mapped Boomi preflight wrapper performs only foundation-approved modeled configuration and render checks. The pre-mapped Boomi full and smoke-test wrappers perform the applicable runtime predicates below for UAT as **UAT READ-ONLY, AUTHORIZED ONLY** checks; dev remains modeled and performs no live command:

```text
Namespace boomi-uat exists and is labeled environment=uat
StatefulSet boomi-runtime desired/current/ready replicas are 3/3/3
Pods are exactly boomi-runtime-0, -1, -2 and each Ready
Each pod's ATOM_LOCALHOSTID equals its pod name
All pods use BOOMI_ATOMNAME=oms-uat-runtime
All pods mount the same PVC at /mnt/boomi and can read one shared marker
PVC is Bound, RWX, and backed by the expected EFS volume handle
StatefulSet and pods contain no INSTALL_TOKEN reference
Secret boomi-install-token is absent
Readiness and liveness endpoints return success inside each pod
PDB allows at most one voluntary disruption
Image repository is boomi/molecule and resolved image IDs/digests are recorded
Service types are ClusterIP/headless; no Ingress or LoadBalancer selects the runtime
Selected communication port/protocol matches the approved decision record
SigNoz has recent pod CPU/memory/restart and runtime log data labeled environment=uat and namespace=boomi-uat
```

Do not print environment blocks, Secret YAML, token-bearing process arguments, or `/proc/*/environ`.

- [ ] **Step 4: Implement secret-safe diagnostics**

The private lifecycle `boomi_internal_lifecycle_collect_diagnostics <reason>` function accepts only `bootstrap|readiness|mount|shutdown|upgrade` and is **UAT READ-ONLY, AUTHORIZED ONLY** through foundation lifecycle dispatch. It obtains an evidence directory from the foundation artifact API beneath `.local/uat/evidence/boomi-runtime/<UTC timestamp>-<reason>/`, mode `0700`, files mode `0600`, then captures:

```text
aws-identity.json
eks-cluster.json
nodes.txt
namespace.yaml
statefulset.yaml
pdb.yaml
services.yaml
pvc.yaml
pv.yaml
pods-wide.txt
pod-0-describe.txt
pod-1-describe.txt
pod-2-describe.txt
pod-0-current.log
pod-0-previous.log
pod-1-current.log
pod-1-previous.log
pod-2-current.log
pod-2-previous.log
events.txt
efs-csi-pods.txt
rendered-redacted.yaml
image-ids.txt
sha256sums.txt
```

Before writing YAML, remove every object of kind `Secret`, every `env.value` for names matching `TOKEN|PASSWORD|SECRET|KEY`, all `.data` and `.stringData`, and bearer/cookie/authorization lines. Run `rg -n -i 'install[_-]?token|authorization:|bearer |password:|stringData:|^[[:space:]]*data:'` over the directory; if it matches, delete the archive and fail. Never automatically upload diagnostics. Tests statically and behaviorally prove both `verifiers.sh` and `pre-destroy-guards.sh` have no artifact API call, artifact-path lookup, evidence read, `mkdir`, file redirection, diagnostic collection call, or mutating command. They also prove `pre-destroy-guards.sh` never calls `record_pre_destroy_guard_result`; only the fragment wrapper makes that exact-once in-memory API call, and only foundation code writes the resulting evidence artifact.

- [ ] **Step 5: Add SigNoz runtime alerts**

Add Terraform alerts filtered by `k8s_namespace_name = '${var.boomi_namespace}'` and `environment = '${var.environment}'`:

- Critical no-data alert when no `k8s_pod_cpu_usage` series for `boomi-runtime-*` is seen for 10 minutes.
- Critical availability alert when ready pod count is below `3` for 10 minutes.
- Warning restart alert when restart delta exceeds `0` in 15 minutes.
- Warning log alert matching Boomi runtime `ERROR`/`SEVERE` log severity for 5 minutes, grouped by pod.

Use the existing SigNoz provider v5/schema v2alpha1 structure in `alerts.tf`; include labels `team = "platform"`, `component = "boomi-runtime"`, and `environment = var.environment`. Do not add a separate dashboard: the existing Kubernetes pod dashboard is the baseline view, filtered by namespace and pod.

- [ ] **Step 6: Run verification only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
bash -n scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh scripts/lib/scope-verifiers.d/40-boomi-runtime.sh
python3 -m unittest tests.boomi_runtime -v
terraform -chdir=platform-prerequisites/terraform/signoz-observability fmt -check
terraform -chdir=platform-prerequisites/terraform/signoz-observability init -backend=false
terraform -chdir=platform-prerequisites/terraform/signoz-observability validate
```

Expected: shell syntax and all unit tests pass; Terraform format and validation exit `0` without contacting the remote state backend.

- [ ] **Step 7: Commit verification and telemetry**

```bash
git add scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh scripts/lib/scope-verifiers.d/40-boomi-runtime.sh platform-prerequisites/terraform/signoz-observability/alerts.tf platform-prerequisites/terraform/signoz-observability/variables.tf tests/boomi_runtime/test_runtime_script.py
git commit -m "feat: verify and observe Boomi runtime"
```

### Task 7: Define Provision, Verification, And Graceful Destroy Wrappers

**Files:**
- Modify: `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh`
- Modify: `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh`
- Modify: `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh`
- Modify: `scripts/lib/scope-handlers.d/40-boomi-runtime.sh`
- Modify: `scripts/lib/scope-verifiers.d/40-boomi-runtime.sh`
- Create: `tests/boomi_runtime/test_orchestration_contract.py`

- [ ] **Step 1: Write failing registry-extension tests**

Use the foundation registry and entrypoint fixtures. Assert:

```python
class BoomiOrchestrationContractTests(unittest.TestCase):
    def test_canonical_catalog_and_all_orders_are_unchanged(self):
        self.assertEqual(self.list_scopes(), FOUNDATION_SCOPES)
        self.assertEqual(self.resolve_provision("all"), FOUNDATION_ALL_ORDER)
        self.assertEqual(self.resolve_destroy("all"), FOUNDATION_DESTROY_ORDER)

    def test_boomi_lifecycle_mappings_resolve_exact_wrapper_symbols(self):
        self.assertEqual(self.provision_handler("boomi-runtime"), "provision_boomi_runtime_scope")
        self.assertEqual(self.destroy_handler("boomi-runtime"), "destroy_boomi_runtime_scope")
      self.assertEqual(self.pre_destroy_guard("boomi-runtime"), "verify_boomi_runtime_pre_destroy")

    def test_boomi_verifier_mappings_resolve_without_public_mode(self):
      self.assert_boomi_verification_mappings("verify_boomi_runtime_scope")
      self.assertEqual(self.public_verification_modes(), ("preflight", "full", "smoke-test"))
      self.assertEqual(self.verification_slots_for_args(), self.verification_slots_for_args("--full"))

    def test_fragments_alone_define_canonical_wrappers(self):
      self.assert_fragment_wrapper_delegates("provision_boomi_runtime_scope", "boomi_internal_lifecycle_provision_runtime")
      self.assert_fragment_wrapper_delegates("destroy_boomi_runtime_scope", "boomi_internal_lifecycle_destroy_runtime")
      self.assert_fragment_wrapper_delegates("verify_boomi_runtime_scope", "boomi_internal_verifier_verify_runtime")
      self.assert_pre_destroy_wrapper_computes_then_records_exactly_once()
      self.assert_handler_sources_only_lifecycle_implementation()
      self.assert_numbered_verifier_fragment_validates_and_sources_both_readonly_implementations()
      self.assert_numbered_verifier_fragment_alone_defines_readonly_canonical_wrappers()
      self.assert_internal_libraries_define_disjoint_boomi_internal_namespaces()
      self.assert_readonly_internal_libraries_create_no_package_artifacts()
      self.assert_boomi_code_has_no_evidence_artifact_reads_or_writes()

      def test_pre_destroy_guard_records_closed_result_exactly_once_on_failure(self):
        artifact = self.prepare_boomi_destroy()
        result = self.execute_boomi_destroy(
          artifact,
          pre_destroy_guard_result="graceful-removal-not-ready",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.guard_compute_log.read_text().splitlines(), ["live-checks"])
        self.assertEqual(self.guard_record_log.read_text().splitlines(), ["boomi-runtime"])
        self.assert_foundation_evidence_matches_closed_summary_and_digest(result="fail")
        self.assertTrue(artifact.exists())
        self.assertEqual(self.artifact_log.read_text().splitlines(), ["validate"])
        self.assertFalse(self.handler_log.exists())

      def test_pre_destroy_guard_records_closed_result_exactly_once_on_success(self):
        artifact = self.prepare_boomi_destroy()
        result = self.execute_boomi_destroy(artifact)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.guard_compute_log.read_text().splitlines(), ["live-checks"])
        self.assertEqual(self.guard_record_log.read_text().splitlines(), ["boomi-runtime"])
        self.assert_foundation_evidence_matches_closed_summary_and_digest(result="pass")

      def test_successful_guard_precedes_artifact_consumption_and_destroy_dispatch(self):
        artifact = self.prepare_boomi_destroy()
        result = self.execute_boomi_destroy(artifact)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
          self.destroy_order_log.read_text().splitlines(),
            ["validate-artifact", "pre-destroy-guard", "record-pre-destroy-guard-result", "approval", "consume-artifact", "destroy-dispatch"],
        )
        self.assertFalse(artifact.exists())

    def test_public_wrappers_are_not_modified_for_boomi(self):
        for path in self.public_wrappers:
            self.assertNotIn("boomi-runtime", path.read_text(encoding="utf-8"))

    def test_dev_fails_at_foundation_promotion_gate_before_handler(self):
        result = self.run_public("provision", "--env", "dev", "boomi-runtime")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PROMOTION_MODE=modeled", result.stderr)
        self.assertFalse(self.handler_log.exists())

    def test_uat_dispatch_uses_one_foundation_lock(self):
        result = self.run_public("provision", "--env", "uat", "boomi-runtime")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lock_log.read_text().splitlines(), ["acquire", "release"])
        self.assertEqual(self.handler_log.read_text(), "provision_boomi_runtime_scope\n")
```

Retain detailed mocked tests for failure stop behavior, exact destroy confirmation, `3 -> 2 -> 1 -> 0` ordering, three 900-second waits, retained PV/PVC/EFS, and no dev reachability. The fixture invokes the existing public wrappers but mocks AWS/Kubernetes and internal handlers with command logs. It must prove the foundation-owned generic public destroy parser enforces a mandatory preparation pass followed by an execution pass. The preparation pass validates repeatable `--confirm <exact-value>` arguments, requires the union of exact confirmations for every selected destructive scope, creates the foundation-owned confirmation artifact, reports a repository-relative artifact path, and never invokes a pre-destroy guard or dispatches a handler. The execution pass repeats the exact same confirmations in the same order and supplies that path through `--confirmation-artifact <repository-relative-path>`. The foundation validates the artifact and repeated confirmation list without consuming the artifact, invokes every selected scope's pre-mapped read-only pre-destroy guard, obtains interactive approval unless separately auto-approved, and consumes the artifact only after all guards and approval succeed; destroy dispatch follows consumption. It rejects a missing preparation pass, missing artifact option, absolute or escaping artifact path, missing artifact, stale or mismatched artifact, and missing, duplicate, extra, reordered, or mismatched repeated confirmations before any guard or dispatch. A Boomi guard failure for runtime identity, graceful-removal readiness, EFS retention, dependencies, or required evidence must leave the artifact present and unchanged, record no approval or consume action, invoke no destroy handler, and perform no mutating AWS or Kubernetes command. For direct `boomi-runtime`, both passes use exactly `destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs`, and the mapped Boomi guard and destroy wrappers receive only the unchanged value, never the artifact path or content. For `all`, both passes repeat the same ordered confirmation list containing that exact Boomi token plus each exact token required by every other selected destructive scope; one package token cannot satisfy another package, all selected guards must succeed before approval and consumption, and the mapped Boomi wrappers receive only their unchanged Boomi confirmation subset. Tests must prove exact order `validate artifact -> run all pre-destroy guards -> approval -> consume artifact -> dispatch destroy handlers`, including preservation and zero dispatch when any guard fails. They must also prove Boomi code has no confirmation-artifact parser or artifact access, and no guard or handler calls a public child provisioner or acquires another lock.

- [ ] **Step 2: Run only after explicit test authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_orchestration_contract -v
```

Expected: failures identify only undefined pre-mapped Boomi lifecycle, verification, and pre-destroy guard wrapper symbols; foundation parsing, immutable mappings, catalog, graph order, artifact ordering, promotion behavior, public modes, and public wrappers already satisfy their contracts.

- [ ] **Step 3: Define exact pre-mapped wrapper semantics**

Complete `scripts/lib/scope-handlers.d/40-boomi-runtime.sh` and the numbered `scripts/lib/scope-verifiers.d/40-boomi-runtime.sh` so that, under foundation validation, the handler fragment sources only `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` plus any exact foundation-validated helper library it demonstrably needs. The numbered verifier fragment separately validates and sources both `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh` and `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh`, plus only any exact foundation-validated read-only helper library they demonstrably need. The handler fragment alone defines canonical lifecycle wrappers; the numbered verifier fragment alone defines canonical verification and pre-destroy guard wrappers. Each wrapper delegates to its distinct implementation namespace; no canonical wrapper symbol appears as a function definition in any package library, and no function name is defined by more than one library. The verifier fragment defines `verify_boomi_runtime_pre_destroy` and delegates only to `boomi_internal_pre_destroy_guard_verify_boomi_runtime`; this is the exact foundation-pre-mapped guard symbol, not a verification slot, registration, or public mode. Both read-only packages use live checks and in-memory callback values only and create or read no evidence artifact, diagnostic archive, status record, or replacement evidence. Preserve the foundation dependency tuple `eks-platform platform-controllers workload-identity`, canonical `all` provision order, reverse destroy order, public verification modes, verification slots, and every mapping byte-for-byte. Do not edit `scripts/lib/scope-registry.sh`, `scripts/lib/orchestrator.sh`, any public script, graph data, scope catalog, mode parser, mapping loader, or foundation library. Do not add a scope, mode, public executable, public option, graph edge, mode branch, or direct call from a public wrapper.

The fragment-owned `provision_boomi_runtime_scope` delegates to `boomi_internal_lifecycle_provision_runtime`, which verifies the EKS platform output contract, EFS CSI, schedulable nodes, controllers, and communication readiness before reconcile/bootstrap. Foundation `--auto-approve` semantics never supply a Boomi token, approve communication, alter promotion, or bypass operation authorization.

The distinct `boomi_internal_pre_destroy_guard_verify_boomi_runtime` is read-only and runs only in the foundation execution-pass dispatch context after artifact metadata and repeated confirmations validate but before approval and artifact consumption. Through canonical read-only guard, dependency, and platform-output APIs, it verifies the current account, Region, cluster ARN/context, `BOOMI_NAMESPACE=boomi-uat`, and runtime resource identity; confirms the runtime can begin graceful highest-ordinal removal without an in-progress rollout, unavailable ordinal, blocked drain, or unrecorded queued-work condition; proves the PVC, PV, EFS filesystem/access point, and backups remain under the `Retain` contract and are excluded from deletion; and verifies `eks-platform platform-controllers workload-identity`. It computes the closed in-memory result from those live observations and requires no pre-existing current-operation evidence or status record. It accepts the unchanged Boomi confirmation subset as an opaque dispatch contract but never receives, reads, removes, or rewrites the confirmation artifact. It must not scale, patch, apply, delete, cordon, drain, invoke lifecycle diagnostics, allocate an evidence path, create, read, or update evidence, or perform any other mutation. Any failed or indeterminate predicate returns nonzero after the wrapper records the exact five-argument failure result, so foundation writes the separate failure record, preserves the unconsumed artifact, performs no approval, and dispatches no selected destroy handler.

- [ ] **Step 4: Implement graceful internal destroy semantics**

The foundation public route requires its canonical operation authorization plus a mandatory preparation pass followed by an artifact-backed execution pass. Direct `boomi-runtime` preparation uses exactly:

```bash
bash scripts/destroy.sh --env uat boomi-runtime
```

That pass prepares the foundation-owned artifact, reports its repository-relative path and exact confirmation, exits nonzero, and performs no destroy dispatch. Direct execution then repeats the foundation-printed exact confirmation and adds the reported path:

```bash
bash scripts/destroy.sh --env uat boomi-runtime --confirm 'destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs' --confirmation-artifact '<repository-relative-path>'
```

The exact Boomi confirmation remains:

```text
destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs
```

The grammar is exactly `destroy:<env>:<account>:boomi-runtime:<runtime-resource>:retain-efs`: colon-delimited with no spaces and with the exact foundation resource `runtime/boomi-uat`, not `BOOMI_RUNTIME_NAME`, a package-local placeholder, or a package parse.

For `all`, preparation supplies no confirmation values; foundation computes and prints the complete canonical ordered union, including the exact Boomi value:

```bash
bash scripts/destroy.sh --env uat all
```

Execution must repeat every exact confirmation from preparation byte-for-byte in the same order and add only the reported artifact path:

```bash
bash scripts/destroy.sh --env uat all --confirm '<exact-confirmation-for-first-selected-destructive-scope>' --confirm 'destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs' --confirm '<exact-confirmation-for-next-selected-destructive-scope>' --confirmation-artifact '<repository-relative-path>'
```

The foundation parser alone creates, reads, validates, and consumes the artifact and validates the repeated exact confirmations. After validation and before approval or consumption, it passes only the unchanged Boomi confirmation subset to `verify_boomi_runtime_pre_destroy`. Only after every selected read-only guard and foundation approval succeed does the foundation consume the artifact and pass the same unchanged subset to `destroy_boomi_runtime_scope`. The Boomi fragments and package libraries never receive or parse the artifact path or artifact content and must not parse, normalize, synthesize, or reinterpret the confirmation value. The fragment-owned destroy wrapper accepts the unchanged foundation confirmation subset as an opaque dispatch contract and delegates to `boomi_internal_lifecycle_destroy_runtime`. As its first operation after dispatch and before any mutation, that lifecycle handler immediately re-verifies account, Region, cluster ARN/context, namespace, and runtime resource identity through canonical guard APIs; a mismatch fails before blocking, scaling, patching, applying, or deleting anything. It then blocks new scheduling/updates, records queue/runtime status, confirms the pre-destroy evidence remains current, and scales `3 -> 2 -> 1 -> 0`, waiting for each highest ordinal to terminate with its 900-second grace period. It deletes StatefulSet, Services, ServiceAccount, NetworkPolicy, and PDB only after zero pods remain. It retains PVC, PV, EFS filesystem/access point, and backups by default and prints identifiers. It refuses data deletion.

If a pod exceeds the grace window, stop, collect diagnostics, and leave remaining nodes running. Never use `--force`, `--grace-period=0`, remove finalizers, or continue to EKS/controller teardown.

- [ ] **Step 5: Run focused checks only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
bash -n scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh scripts/lib/scope-handlers.d/40-boomi-runtime.sh scripts/lib/scope-verifiers.d/40-boomi-runtime.sh
python3 -m unittest tests.boomi_runtime.test_orchestration_contract tests.environment_orchestration.test_scope_registry tests.environment_orchestration.test_entrypoints -v
```

Expected: syntax and tests pass; catalog/order/public wrappers are unchanged; each Boomi guard invocation computes one closed in-memory summary/digest and calls foundation `record_pre_destroy_guard_result` exactly once; only foundation writes guard evidence; Boomi performs no evidence artifact read or write; guard failure preserves the confirmation artifact and produces no approval or destroy dispatch; successful execution orders confirmation-artifact validation, each read-only guard and result recording, approval, confirmation-artifact consumption, then destroy dispatch; one foundation lock surrounds the guard and internal handler dispatch.

- [ ] **Step 6: Commit only after commit authorization**

```bash
git add scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh scripts/lib/scope-handlers.d/40-boomi-runtime.sh scripts/lib/scope-verifiers.d/40-boomi-runtime.sh tests/boomi_runtime/test_orchestration_contract.py
git commit -m "feat: add Boomi runtime lifecycle handlers"
```

### Task 8: Create The Component-Owned Runtime And Recovery Evidence Contract

**Files:**
- Create: `docs/references/boomi-runtime-contract.md`
- Modify: `tests/boomi_runtime/test_manifest_contract.py`

Do not modify `README.md`, `docs/index.md`, environment setup, operator runbook, shared verification commands, shared recovery procedures, or other cross-component navigation. The final documentation work package owns those shared surfaces and will link this component contract.

- [ ] **Step 1: Add failing component-document tests**

Assert `boomi-runtime-contract.md` links the canonical imported-code matrix, official evidence, and communication decision; names `scripts/provision.sh` as the sole public mutating entrypoint; names `scripts/lib/packages/40-boomi-runtime/internal/lifecycle.sh` as the lifecycle implementation, `scripts/lib/packages/40-boomi-runtime/internal/verifiers.sh` as the separate read-only verification implementation, and `scripts/lib/packages/40-boomi-runtime/internal/pre-destroy-guards.sh` as the separate read-only pre-destroy guard implementation; declares that the handler fragment sources only its owning lifecycle implementation and the numbered verifier fragment validates and sources both read-only implementations and alone defines their canonical wrappers; declares that the internal guard computes its digest and closed summary from live runtime, EFS, and dependency checks in memory, the wrapper calls foundation `record_pre_destroy_guard_result` exactly once, foundation alone writes the evidence artifact, and Boomi code never writes or reads an evidence artifact; declares communication readiness non-authorizing; and contains the recovery evidence schema below. Assert shared docs are absent from this task's changed-file allowlist.

Also assert the component contract contains no dev mutation example, direct `kubectl apply` mutation recipe, `kubectl delete pvc`, `--force --grace-period=0`, token literal, second lock path, or public `provision-boomi-runtime.sh` reference.

- [ ] **Step 2: Run only after explicit test authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract -v
```

Expected: the component documentation tests fail because `boomi-runtime-contract.md` is absent.

- [ ] **Step 3: Document the component contract and operator handoff**

Document runtime invariants, internal handler boundaries, canonical registry dependencies, one-lock behavior, promotion and execution authorization prerequisites, communication readiness, protected token handling, verification predicates, diagnostic redaction, and the public command shapes owned by the foundation. Document the pre-destroy evidence flow explicitly: Boomi's internal guard performs live runtime, EFS, and dependency checks and computes a closed summary plus digest in memory; its mapped wrapper calls `record_pre_destroy_guard_result` exactly once; foundation writes the evidence artifact; no Boomi fragment or package library writes or reads that artifact. State that commands are examples for separately authorized execution only and are not authorized by this document.

Preserve this operator sequence as a handoff contract rather than an executable runbook:

1. Review the canonical imported-code rows, official evidence, and approved communication decision.
2. Obtain separate authorization for each offline/read-only/mutating execution class.
3. Run authorized static acceptance and inspect resolved EKS/EFS output evidence.
4. For separately authorized UAT bootstrap, only the operator enters a fresh token directly in the terminal; agents, docs, issue comments, Terraform inputs, command arguments, and committed files never receive it.
5. Verify Secret absence, three stable identities, shared storage, probes, service boundaries, and telemetry.
6. Record image digest, EKS/CNI/EFS CSI versions, Cluster Status, timings, and diagnostic archive checksum.

- [ ] **Step 4: Define the recovery evidence contract**

For each case below, require precondition evidence, authorization ID, command transcript with secrets removed, before/after object state, diagnostics checksum, retained-resource IDs, recovery decision, outcome, and reviewer sign-off:

- **Expired/invalid token before registration:** remain at one replica, remove token reference before Secret deletion, confirm installation state with Boomi Support, never wipe EFS merely to retry.
- **Interrupted bootstrap after registration:** do not supply a second token; restore steady state at one replica, remove Secret, restart ordinal `0`, verify reuse, then scale only under separate authorization.
- **EFS mount failure:** stop scale-out, retain PV/PVC, capture CSI/mount target/security group/access-point evidence, restore connectivity, then restart only the failed ordinal.
- **Readiness/liveness failure:** capture current/previous logs and probe output; never weaken probes to make rollout pass.
- **Stalled rolling update/invalid image:** protect healthy lower ordinals, restore the last recorded image selector/digest, and replace only the failed highest ordinal normally.
- **Node drain blocked by PDB:** preserve two available nodes, repair capacity, then retry; do not delete the PDB.
- **Graceful shutdown exceeds 900 seconds:** stop teardown, retain remaining nodes, collect queue/runtime evidence, and obtain Boomi guidance.
- **EFS restore:** use an isolated access point/path and different recovery StatefulSet name; verify identity with Boomi Support; never run original and restored writers concurrently against one registration.

- [ ] **Step 5: Run component documentation checks only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest tests.boomi_runtime.test_manifest_contract -v
rg -n 'CHANGE_ME|kubectl delete pvc|--force.*--grace-period=0|provision-boomi-runtime\.sh|boomi-runtime/bootstrap\.lock' docs/references/boomi-runtime-contract.md
```

Expected: tests pass and the scan finds no forbidden component contract content.

- [ ] **Step 6: Commit only after commit authorization**

```bash
git add docs/references/boomi-runtime-contract.md tests/boomi_runtime/test_manifest_contract.py
git commit -m "docs: define Boomi runtime component contract"
```

### Task 9: Define Static Acceptance Before Any UAT Mutation

**Files:**
- Modify only files already listed if a check exposes a defect.

- [ ] **Step 1: Run the complete static suite only after authorization**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n scripts/*.sh scripts/lib/*.sh scripts/lib/packages/40-boomi-runtime/internal/*.sh scripts/lib/scope-handlers.d/40-boomi-runtime.sh scripts/lib/scope-verifiers.d/40-boomi-runtime.sh
kustomize build gitops/boomi-runtime/overlays/dev >/tmp/boomi-modeled-dev-render.yaml
kustomize build gitops/boomi-runtime/overlays/uat >/tmp/boomi-uat-render.yaml
kubectl apply --dry-run=client -f /tmp/boomi-modeled-dev-render.yaml >/dev/null
kubectl apply --dry-run=client -f /tmp/boomi-uat-render.yaml >/dev/null
terraform -chdir=platform-prerequisites/terraform/signoz-observability fmt -check
terraform -chdir=platform-prerequisites/terraform/signoz-observability init -backend=false
terraform -chdir=platform-prerequisites/terraform/signoz-observability validate
```

Expected: all tests pass; shell syntax, both renders, client dry-runs, Terraform format, and Terraform validation exit `0`.

- [ ] **Step 2: Run the secret, ownership, and dev-mutation scans**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**):

```bash
rg -n -i 'molecule-[0-9a-f-]{20,}|install_token:[[:space:]]*[^$]|stringData:|kind:[[:space:]]*Secret' docs gitops/boomi-runtime scripts tests/boomi_runtime
rg -n 'kustomize.toolkit.fluxcd.io|helm.toolkit.fluxcd.io|path:.*boomi-runtime' gitops/boomi-runtime gitops/operators gitops/signoz
rg -n -- '--env dev' docs scripts tests gitops/boomi-runtime
git diff --check
```

Expected: no real/sample token or committed Secret manifest; no Flux resource owns the runtime; every dev occurrence is parser rejection, render-only, or test evidence; `git diff --check` is clean.

- [ ] **Step 3: Verify communication readiness cannot grant mutation authority**

Run (**OFFLINE, AUTHORIZED ONLY; DO NOT EXECUTE NOW**, mocks only):

```bash
python3 -m unittest tests.boomi_runtime.test_configuration_contract.BoomiRuntimeConfigurationTests.test_communication_decision_is_readiness_not_authorization -v
python3 -m unittest tests.boomi_runtime.test_runtime_script.BoomiRuntimeScriptTests.test_readiness_failure_prevents_handler_mutation_after_foundation_authorization -v
```

Expected: both tests pass by proving two independent boundaries: the foundation exclusively authorizes operations, and unresolved communication readiness prevents the already-authorized UAT handler from mutating. An approved communication value still cannot authorize dev or bypass `PROMOTION_MODE`.

- [ ] **Step 4: Commit any acceptance-only corrections**

Only if Step 1-3 required fixes:

```bash
git add docs config gitops/boomi-runtime scripts platform-prerequisites/terraform/signoz-observability tests/boomi_runtime tests/uat_access
git commit -m "test: close Boomi runtime acceptance gaps"
```

### Task 10: Handoff To A Separate Authorized UAT Acceptance Execution Plan

**Files:**
- No runtime, configuration, evidence, or execution-status file is created or modified by this task.
- A future, separately reviewed plan will own its own dated `.local/uat/evidence/` path and operation report.

This implementation plan contains no UAT mutation experiment and authorizes no execution. Completion means producing an acceptance handoff specification for a future plan, not running preflight, bootstrap, lifecycle, telemetry, destroy, recovery, dry-run, test, formatter, or script commands.

- [ ] **Step 1: Define prerequisites for the future acceptance plan**

The separate plan must start only after all of these are independently true:

- Foundation parser/schema/registry/path/lock APIs and `PROMOTION_MODE` gates are implemented and verified.
- EKS platform outputs expose the canonical cluster ARN and EFS filesystem/access-point contract.
- The canonical imported-code matrix contains reviewed Boomi rows.
- The communication record contains Boomi Support evidence and exactly one readiness value, while explicitly stating that it grants no authorization.
- Static implementation acceptance has a reviewed result and no unresolved secret, public exposure, dev mutation, Flux ownership, or force-deletion finding.
- The platform owner identifies the operator, execution date/window, exact UAT account/Region/cluster, authorization IDs, rollback owner, stop conditions, and evidence reviewers.

- [ ] **Step 2: Require explicit per-class and per-experiment authorization**

The future plan must mark every command as one of offline, UAT read-only, or UAT mutation and require explicit authorization before each class. Fault injection, bootstrap interruption, node drain, image rollback, EFS isolation, restore, and destroy each require their own approval and rollback checkpoint. Approval of communication readiness, tests, preflight, or one experiment does not authorize any other command. Dev remains forbidden regardless of communication status.

- [ ] **Step 3: Preserve the acceptance experiment inventory**

The separate plan must sequence one experiment at a time, stop on the first unexplained result, and cover:

1. Ordinal-0 bootstrap, token-reference removal, Secret deletion, and token-free restart before scale-out.
2. Exactly three stable pod-derived identities with one runtime name and shared retained EFS.
3. Restart and reschedule behavior across nodes/failure domains without duplicate registration.
4. Concurrent shared-marker read/write evidence.
5. PDB behavior during one-node drain and prevention of simultaneous disruption.
6. Active/queued-work graceful termination measured against 900 seconds.
7. Approved EFS connectivity fault and recovery without deleting storage.
8. One-ordinal reviewed image update and invalid-image rollback preserving healthy lower ordinals.
9. Interrupted bootstrap recovery in an isolated empty test path.
10. Isolated EFS backup restore with identity-safe, non-concurrent validation.
11. SigNoz CPU, memory, restart, readiness, log, no-data, availability, restart, and severe-log evidence.
12. Graceful destroy with retained PV/PVC/EFS and retained-installation recovery.

HPA, unattended updates, Flux ownership, force deletion, public exposure, direct dev mutation, and concurrent original/restored writers remain prohibited.

- [ ] **Step 4: Define mandatory evidence criteria**

For every action, the future plan and report must record:

```text
authorization ID and approver
operator and UTC timestamps
exact command with secrets redacted
account, Region, cluster ARN, PROMOTION_MODE, and selected scope
communication readiness evidence and support reference
before/after Kubernetes object summaries
runtime registration and identity evidence
EKS, Kubernetes, CNI, EFS CSI, and image digest versions
readiness, rollout, and termination durations
EFS, PDB, update, fault-injection, telemetry, and retained-resource outcomes
diagnostic archive path and SHA-256 checksums
stop/rollback decisions, failures, and recovery result
final pass/fail and reviewer sign-off
```

The evidence must contain no Secret values, raw Secret manifests, authorization headers, cookies, bearer tokens, environment dumps, or `/proc/*/environ`. Evidence belongs under the foundation-owned `.local/uat/evidence/` tree while in progress; only the final redacted operation report may be proposed for commit after separate review.

- [ ] **Step 5: Define acceptance exit criteria**

The future plan may declare UAT acceptance only when every invariant has static and live evidence, every experiment passed or has an approved disposition, diagnostics scans are clean, retained resources are identified, rollback was demonstrated where required, and reviewers sign the final report. A failed or skipped experiment cannot be converted to pass by editing the communication decision, local JSON, `PROMOTION_MODE`, or a Boomi handler.

- [ ] **Step 6: Stop without execution**

Do not create the future execution plan, evidence directory, communication approval, operation report, or commit as part of this implementation plan. Hand the criteria above to the platform owner and final documentation owner for a separately authorized planning cycle.

## Final Acceptance Checklist

- [ ] Every official invariant has a matrix row, implementation, and static/live verification.
- [ ] Every legacy Boomi source file is classified `KEEP`, `REWRITE`, `REPLACE`, or `REJECT`; no `infra/` code was copied blindly.
- [ ] Base and dev/UAT overlays render deterministically; dev has no mutation path.
- [ ] Official unmodified `boomi/molecule:release` v5 runs as UID/GID `1000` on retained EFS RWX mounted at `/mnt/boomi`.
- [ ] Steady state is exactly three StatefulSet identities with unique pod-derived `ATOM_LOCALHOSTID` and one `BOOMI_ATOMNAME`.
- [ ] Token reaches ordinal `0` only, is removed from the pod template, and its Secret is deleted before scale-out.
- [ ] Readiness/liveness use `9090` official endpoints; shutdown starts at 900 seconds.
- [ ] PDB, OrderedReady rollout, anti-affinity, and one-ordinal procedures prevent simultaneous restart.
- [ ] Communication mode is approved and explicit as a readiness prerequisite; unresolved mode blocks the internal UAT handler, while approval grants no mutation authority and cannot enable dev.
- [ ] Services are internal; NetworkPolicy is least-path; no public NLB/Ingress or invented TLS termination exists.
- [ ] SigNoz receives runtime signals and owns actionable availability/restart/error alerts.
- [ ] Provision and destroy use the lifecycle-only package; verification uses `verifiers.sh`; the pre-destroy guard uses `pre-destroy-guards.sh`; all three use disjoint `boomi_internal_*` names. The handler fragment sources only lifecycle, while the numbered verifier fragment validates and sources both read-only libraries and alone defines their canonical wrappers. The internal guard computes one closed summary and digest in memory from live runtime, EFS, and dependency checks; its wrapper calls foundation `record_pre_destroy_guard_result` exactly once on pass or fail; foundation alone writes the evidence artifact; Boomi writes or reads no evidence artifact. Immutable foundation mappings and exact pre-mapped canonical wrapper symbols remain environment-aware, ordered, fail-closed, and covered by mocked tests; guard failure preserves the confirmation artifact and dispatches no destroy handler.
- [ ] Diagnostics are complete, redacted, checksummed, local, and useful for Boomi Support.
- [ ] Recovery preserves storage and healthy ordinals; no force deletion is a normal procedure.
- [ ] Flux does not own Boomi runtime resources initially.
- [ ] Authorized static acceptance passes before a separate UAT acceptance execution plan is requested; live experiments and evidence are excluded from this implementation plan and must pass before any dev adoption planning.