# Phase 3 Task 6 (SigNoz) Design Document

**Date:** 2026-07-27  
**Status:** Design Phase (Pre-Implementation)  
**Author:** Gatekeeper Evaluation (4-Perspective Assessment)  
**Scope:** Task 6 SigNoz Observability Platform (`signoz` and `signoz-observability` scopes)

---

## Executive Summary

Task 6 deploys the SigNoz observability stack. Unlike MongoDB and PostgreSQL, SigNoz:
- Uses **no AWS IRSA** (internal ClickHouse + Kafka storage only)
- Has **no Terraform prerequisites** (no IAM, no S3 buckets, no KMS grants)
- Already has a **partially complete** `gitops/signoz/base/` directory from Phase 2 work (commit `19306ad`)
- Has **TWO distinct scopes**: `signoz` (platform/Helm) and `signoz-observability` (API-driven alerts/dashboards)

The 4-perspective gatekeeper evaluation identified one **RED** security issue in existing base manifests (hardcoded ClickHouse password) that must be resolved before Task 6 is committed.

---

## 1. AWS Architect Perspective Assessment

### Issue: Hardcoded ClickHouse Password in GitOps Manifest

**Finding:** `gitops/signoz/base/helmreleases.yaml` contains:

```yaml
clickhouse:
  password: "CHANGE_ME_BEFORE_PRODUCTION"
```

This is a **plaintext credential in a version-controlled GitOps manifest**. This is an OWASP A02 (Cryptographic Failures) violation — any repository reader can extract the ClickHouse database password directly from Git history.

**Edge Case:** Even if `CHANGE_ME_BEFORE_PRODUCTION` is clearly a placeholder, SigNoz will install successfully with it and run with a known-weak credential in non-sandbox environments where operators forget to patch it before deployment.

**Resolution:** Replace the hardcoded password with a Kubernetes Secret reference, exactly as the existing `SIGNOZ_USER_ROOT_PASSWORD` pattern already does in the same file:

```yaml
clickhouse:
  password:
    valueFrom:
      secretKeyRef:
        name: signoz-clickhouse
        key: password
```

**Test Coverage Requirement (MUST):**
- `test_helmrelease_has_no_hardcoded_clickhouse_password`: Assert `CHANGE_ME` and `clickhouse.password: "` (literal string) are absent from all base manifests
- `test_helmrelease_clickhouse_password_uses_secret_ref`: Assert `secretKeyRef` is present in helmreleases.yaml for ClickHouse credential

### Issue: Hardcoded EKS Cluster Name in k8s-infra HelmRelease

**Finding:** `gitops/signoz/base/helmrelease-k8s-infra.yaml` contains:

```yaml
global:
  clusterName: EKS-boomi-runtime-cluster
  deploymentEnvironment: dev
```

Both `clusterName` and `deploymentEnvironment` are environment-specific values hardcoded in the base manifest. In UAT this would cause k8s-infra to report incorrect cluster metadata.

**Resolution:** Move these values to the UAT overlay patch (they are already environment-specific). The base should define them as placeholder values that overlays override.

**Test Coverage Requirement:**
- `test_uat_overlay_patches_cluster_name`: Assert UAT overlay patches `clusterName` and `deploymentEnvironment`

---

## 2. DevOps Perspective Assessment

### Issue: No UAT Overlay Exists

**Finding:** `gitops/signoz/overlays/` does not exist. The Phase 3 completion gate requires `kustomize build gitops/signoz/overlays/uat` to succeed.

**Resolution:** Create `gitops/signoz/overlays/uat/` with:
- `kustomization.yaml` — extends base, applies patches
- `helmrelease-patch.yaml` — patches `clusterName` and `deploymentEnvironment` for UAT values

### Issue: `gp3-mongodb` StorageClass Name Assumption

**Finding:** `gitops/signoz/base/helmreleases.yaml` sets:

```yaml
global:
  storageClass: gp3-mongodb
```

`gp3-mongodb` is the StorageClass name defined in Phase 2 (`k8s/base/storageclass-gp3-mongodb.yaml`). This name must be consistent; if Phase 2 StorageClass is renamed, SigNoz PVCs will fail to provision silently.

**Resolution:** This is acceptable for Phase 3 sandbox. Document as a cross-scope dependency.

**Test Coverage Requirement:**
- `test_helmrelease_uses_gp3_storage_class`: Assert `storageClass: gp3-mongodb` is present (locks the value to prevent silent drift)

---

## 3. Software Architect Perspective Assessment

### Issue: gitops/signoz/base Already Exists (Do Not Recreate)

**Finding:** Unlike MongoDB/PostgreSQL where Task 3/5 created new base directories, `gitops/signoz/base/` already exists with 5 files from prior Phase 2 commits. Task 6 must **modify** the existing manifests (credential fix) and **add** the overlay — not recreate from scratch.

**Impact on TDD:** Tests must be written against the actual existing file content. This is different from MongoDB/PostgreSQL where tests were written against files created in the same task.

**Resolution:** The test suite must assert both:
1. What the existing files contain (positive assertions)
2. What the existing files must NOT contain (security assertions — no hardcoded passwords)

### Issue: Two Scope Naming Convention (signoz vs signoz-observability)

**Finding:** The scope registry uses `signoz` and `signoz-observability`. The bash variable naming convention converts hyphens to underscores:
- `scope_registry_deferred_signoz_provision`
- `scope_registry_deferred_signoz_observability_provision`
- `scope_registry_deferred_signoz_destroy`
- `scope_registry_deferred_signoz_observability_destroy`
- `scope_registry_verify_signoz`
- `scope_registry_verify_signoz_observability`
- `scope_registry_pre_destroy_guard_signoz`
- `scope_registry_pre_destroy_guard_signoz_observability`

The internal function naming convention must follow `signoz_internal_*` prefix. Unlike PostgreSQL which had `-core` and `-brand` sub-scopes, SigNoz scopes are top-level: `signoz` and `signoz-observability`.

**Resolution:** Handler fragment exports exactly 4 symbols (2 scopes × provision/destroy). Verifier fragment exports 4 symbols (2 scopes × verify/pre_destroy).

**Copy-Paste Detection:** Tests must assert zero `mongodb` AND zero `postgresql` references in all `50-signoz` bash files (two-language copy-paste check).

---

## 4. Superpowers Creator Perspective Assessment

### Issue: Credential Security Violation in Existing Code Must Be Fixed in Same Task

**Finding:** The ClickHouse password issue is a security violation in committed code (Phase 2 commits). The Superpowers invariant states: **never commit code with known security violations**. Task 6 must include a fix for this as part of the atomic commit, not defer it.

**Design Decision:** Task 6 will:
1. Fix the credential leak (modify `gitops/signoz/base/helmreleases.yaml`)
2. Add the UAT overlay
3. Create `config/environment-schema/fragments/50-signoz.manifest`
4. Create `scripts/lib/packages/50-signoz/` handler/verifier/guard files
5. Create `scripts/lib/scope-handlers.d/50-signoz.sh` and `scripts/lib/scope-verifiers.d/50-signoz.sh`
6. Create `tests/signoz/` with full test suite
7. Commit atomically

**Commit scope:** All 6 areas above in ONE commit.

---

## Complete Deliverables Specification

### A. GitOps Manifests

**Modify (existing, fix credential):**
- `gitops/signoz/base/helmreleases.yaml`: Replace hardcoded ClickHouse password with `secretKeyRef` reference to `signoz-clickhouse` Secret

**Add (new):**
- `gitops/signoz/overlays/uat/kustomization.yaml`
- `gitops/signoz/overlays/uat/helmrelease-patch.yaml` — patches `clusterName: EKS-uat-cluster` and `deploymentEnvironment: uat`

### B. Environment Schema Fragment

**Create:** `config/environment-schema/fragments/50-signoz.manifest`

```
# SigNoz schema fragment.
# @requires eks-platform

SIGNOZ_NAMESPACE|required|fixed:signoz|-
SIGNOZ_VERSION|required|nonempty|-
SIGNOZ_K8S_INFRA_VERSION|required|nonempty|-
SIGNOZ_STORAGE_CLASS|required|fixed:gp3-mongodb|-
SIGNOZ_OTEL_ENDPOINT|required|nonempty|-
SIGNOZ_CLICKHOUSE_SECRET_NAME|required|nonempty|-
```

### C. Handler/Verifier/Guard Bash Files

**Create:** `scripts/lib/packages/50-signoz/internal/lifecycle-handlers.sh`

Exports:
- `signoz_internal_provision_signoz`
- `signoz_internal_destroy_signoz`
- `signoz_internal_provision_signoz_observability`
- `signoz_internal_destroy_signoz_observability`

**Create:** `scripts/lib/packages/50-signoz/internal/verifiers.sh`

Exports:
- `signoz_internal_signoz_verifier`
- `signoz_internal_signoz_observability_verifier`

**Create:** `scripts/lib/packages/50-signoz/internal/pre-destroy-guards.sh`

Exports:
- `signoz_internal_signoz_pre_destroy_guard`
- `signoz_internal_signoz_observability_pre_destroy_guard`

Each guard follows the exact protocol: seam → parse → identity → SHA-256 → callback once → return.

**Create:** `scripts/lib/scope-handlers.d/50-signoz.sh`

```bash
source_package_internal_library "50-signoz/internal/lifecycle-handlers.sh" || return 1

scope_registry_deferred_signoz_provision()                  { signoz_internal_provision_signoz "$@"; }
scope_registry_deferred_signoz_destroy()                    { signoz_internal_destroy_signoz "$@"; }
scope_registry_deferred_signoz_observability_provision()    { signoz_internal_provision_signoz_observability "$@"; }
scope_registry_deferred_signoz_observability_destroy()      { signoz_internal_destroy_signoz_observability "$@"; }
```

**Create:** `scripts/lib/scope-verifiers.d/50-signoz.sh`

```bash
source_package_internal_library "50-signoz/internal/verifiers.sh" || return 1
source_package_internal_library "50-signoz/internal/pre-destroy-guards.sh" || return 1

scope_registry_verify_signoz()                   { signoz_internal_signoz_verifier "$@"; }
scope_registry_verify_signoz_observability()     { signoz_internal_signoz_observability_verifier "$@"; }

verify_signoz_pre_destroy()                      { signoz_internal_signoz_pre_destroy_guard "$@"; }
verify_signoz_observability_pre_destroy()        { signoz_internal_signoz_observability_pre_destroy_guard "$@"; }
```

### D. Test Suite

**Create:** `tests/signoz/__init__.py` (empty)

**Create:** `tests/signoz/test_environment_contract.py` (4 tests)
- `test_signoz_schema_fragment_exists`
- `test_signoz_fragment_registers_all_required_variables`
- `test_signoz_fragment_has_eks_platform_requires_dependency`
- `test_signoz_fragment_validates_variable_constraints`

**Create:** `tests/signoz/test_gitops_manifests.py` (12 tests)
- `test_kustomize_build_base_succeeds`
- `test_kustomize_build_uat_overlay_succeeds`
- `test_helmrepository_uses_correct_signoz_chart_url`
- `test_helmrelease_signoz_uses_pinned_version`
- `test_helmrelease_has_no_hardcoded_clickhouse_password`
- `test_helmrelease_clickhouse_password_uses_secret_ref`
- `test_helmrelease_uses_gp3_storage_class`
- `test_k8s_infra_helmrelease_exists`
- `test_k8s_infra_uses_otel_collector_endpoint`
- `test_uat_overlay_patches_cluster_name`
- `test_uat_overlay_exists`
- `test_namespace_manifest_exists`

**Create:** `tests/signoz/test_handlers.py` (10 tests)
- `test_handler_fragment_sources_internal_lifecycle_handlers`
- `test_handler_wrappers_delegate_to_internal_signoz`
- `test_handler_wrappers_delegate_to_internal_signoz_observability`
- `test_scope_handlers_signoz_provides_provision_wrapper`
- `test_scope_handlers_signoz_provides_destroy_wrapper`
- `test_scope_handlers_signoz_observability_provides_provision_wrapper`
- `test_scope_handlers_signoz_observability_provides_destroy_wrapper`
- `test_handler_fragment_has_no_mongodb_references`
- `test_handler_fragment_has_no_postgresql_references`
- `test_handler_wrappers_bash_syntax_valid`

**Create:** `tests/signoz/test_verifiers.py` (8 tests)
- `test_verifier_fragment_sources_internal_verifiers`
- `test_verifier_fragment_sources_internal_pre_destroy_guards`
- `test_scope_verifiers_signoz_exports_canonical_symbol`
- `test_scope_verifiers_signoz_exports_pre_destroy_symbol`
- `test_scope_verifiers_signoz_observability_exports_canonical_symbol`
- `test_scope_verifiers_signoz_observability_exports_pre_destroy_symbol`
- `test_guard_contract_uses_seam_callback_mechanism`
- `test_pre_destroy_guard_computes_sha256_digest`

**Total: 34 tests** (smaller than MongoDB/PostgreSQL because no Terraform module)

---

## Completion Criteria

**GATE 1: All Tests PASS**
```bash
python3 -m unittest discover -s tests/signoz -p "test_*.py" -v
# Expected: 34/34 PASS
```

**GATE 2: No Cross-Scope Copy-Paste**
```bash
grep -ir "mongodb\|postgresql" scripts/lib/packages/50-signoz/ scripts/lib/scope-handlers.d/50-signoz.sh scripts/lib/scope-verifiers.d/50-signoz.sh
# Expected: 0 matches (checks both prior scopes)
```

**GATE 3: No Credential Leakage**
```bash
grep -r "CHANGE_ME\|password:.*\"" gitops/signoz/base/
# Expected: 0 matches
```

**GATE 4: GitOps Validation**
```bash
kustomize build gitops/signoz/base
kustomize build gitops/signoz/overlays/uat
# Both exit code: 0
```

**GATE 5: Bash Syntax**
```bash
bash -n scripts/lib/packages/50-signoz/internal/lifecycle-handlers.sh
bash -n scripts/lib/packages/50-signoz/internal/verifiers.sh
bash -n scripts/lib/packages/50-signoz/internal/pre-destroy-guards.sh
bash -n scripts/lib/scope-handlers.d/50-signoz.sh
bash -n scripts/lib/scope-verifiers.d/50-signoz.sh
# All exit code: 0
```

**GATE 6: Clean git status**
```bash
git status
# Expected: nothing to commit, working tree clean
```

---

## Security Requirement: Kubernetes Secret for ClickHouse

The `signoz-clickhouse` Secret must be created via operator script (not stored in Git). Add this requirement to `scripts/create-signoz-root-user-secret.sh` or create a separate `scripts/create-signoz-clickhouse-secret.sh`. The test suite must assert the Secret name (`signoz-clickhouse`) is referenced correctly in the HelmRelease values.

This follows the existing pattern for `signoz-root-user` Secret which is already handled by `scripts/create-signoz-root-user-secret.sh`.

---

## Design Review Checklist

- [x] **AWS Architect:** ClickHouse password credential leak resolved via Secret reference; test asserts absence of `CHANGE_ME`
- [x] **DevOps:** UAT overlay created with clusterName patch; gp3-mongodb StorageClass dependency documented and tested
- [x] **Software Architect:** Existing base manifests reused (not recreated); two-scope copy-paste detection (mongodb + postgresql both checked); TDD protocol enforced (tests before commit)
- [x] **Superpowers Creator:** Atomic commit scope defined; credential fix included in same commit; all 6 gates defined

---

## Atomic Commit Message

```
feat(signoz): add GitOps manifests and handler wrappers for SigNoz observability platform

- Fix: replace hardcoded ClickHouse password with secretKeyRef to signoz-clickhouse Secret
- Add: gitops/signoz/overlays/uat with clusterName and deploymentEnvironment patches
- Add: config/environment-schema/fragments/50-signoz.manifest with 6 required variables
- Add: handler/verifier/guard wrappers for signoz and signoz-observability scopes
- Add: test suite - 34 tests covering credential security, GitOps manifests, and scope isolation
```

---

## Recovery Subagent Prompt (Ready to Execute)

```
Execute Phase 3 Task 6 (SigNoz) per design spec at:
docs/superpowers/plans/2026-07-27-phase3-task6-signoz-design.md

Scope: Task 6 ONLY. Do NOT start Task 7.

Working directory: /Users/frank/sml/oms/mongodb/.worktrees/phase3-workload-platforms

CRITICAL SECURITY FIX (do this first):
1. Modify gitops/signoz/base/helmreleases.yaml: replace `password: "CHANGE_ME_BEFORE_PRODUCTION"` with secretKeyRef referencing signoz-clickhouse Secret (matching existing SIGNOZ_USER_ROOT_PASSWORD pattern in same file)

GITOPS ADDITIONS:
2. Create gitops/signoz/overlays/uat/kustomization.yaml (extends base)
3. Create gitops/signoz/overlays/uat/helmrelease-patch.yaml (patches clusterName: EKS-uat-cluster, deploymentEnvironment: uat)

SCHEMA:
4. Create config/environment-schema/fragments/50-signoz.manifest with 6 variables per design

BASH FILES (all 5):
5. Create scripts/lib/packages/50-signoz/internal/lifecycle-handlers.sh
6. Create scripts/lib/packages/50-signoz/internal/verifiers.sh
7. Create scripts/lib/packages/50-signoz/internal/pre-destroy-guards.sh
8. Create scripts/lib/scope-handlers.d/50-signoz.sh (4 canonical handler wrappers)
9. Create scripts/lib/scope-verifiers.d/50-signoz.sh (4 canonical verifier wrappers)

TEST SUITE (34 tests):
10. Create tests/signoz/__init__.py, test_environment_contract.py (4), test_gitops_manifests.py (12), test_handlers.py (10), test_verifiers.py (8)

VALIDATION GATES (all must pass):
- Gate 1: python3 -m unittest discover -s tests/signoz -p "test_*.py" -v → 34/34 PASS
- Gate 2: grep -ir "mongodb|postgresql" scripts/lib/packages/50-signoz/ ... → 0 matches
- Gate 3: grep -r "CHANGE_ME" gitops/signoz/base/ → 0 matches
- Gate 4: kustomize build gitops/signoz/base && kustomize build gitops/signoz/overlays/uat
- Gate 5: bash -n on all 5 bash files
- Gate 6: git status clean

ATOMIC COMMIT:
git add -A
git commit -m "feat(signoz): add GitOps manifests and handler wrappers for SigNoz observability platform

- Fix: replace hardcoded ClickHouse password with secretKeyRef to signoz-clickhouse Secret
- Add: gitops/signoz/overlays/uat with clusterName and deploymentEnvironment patches
- Add: config/environment-schema/fragments/50-signoz.manifest with 6 required variables
- Add: handler/verifier/guard wrappers for signoz and signoz-observability scopes
- Add: test suite - 34 tests covering credential security, GitOps manifests, and scope isolation"

Constraints: All tests PASS before commit. NO partial commits. NO moving to Task 7. 
```
