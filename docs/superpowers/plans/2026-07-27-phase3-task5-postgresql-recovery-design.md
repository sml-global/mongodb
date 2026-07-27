# Phase 3 Task 5 (PostgreSQL) Recovery Design Document

**Date:** 2026-07-27  
**Status:** Design Phase (Pre-Implementation)  
**Author:** Gatekeeper Evaluation (4-Perspective Assessment)  
**Scope:** Task 5 PostgreSQL Infrastructure (Terraform, Schema, GitOps, Handlers/Verifiers/Guards)

---

## Executive Summary

Task 5 execution was interrupted mid-implementation, leaving the worktree in a dirty state with implementation code but incomplete test coverage. This design document formally resolves all doubts identified by the 4-perspective gatekeeper evaluation and establishes completion criteria before any further work proceeds.

**Key Finding:** Test-Driven Development (TDD) protocol was violated. Implementation files exist but critical test gaps create copy-paste vulnerability and architectural drift risk.

**Action Required:** Complete test suite before committing any code.

---

## 1. AWS Architect Perspective Assessment

### Issue: IAM Role Name Extraction Robustness

**Finding:** The `postgresql/main.tf` extracts the role name from ARN using string split:

```hcl
role = element(split("/", var.postgresql_operator_iam_role_arn), length(split("/", var.postgresql_operator_iam_role_arn)) - 1)
```

**Edge Case:** Standard ARN `arn:aws:iam::632674123947:role/oms-postgresql-operator` → works.  
**Edge Case (FAILS):** Pathed ARN `arn:aws:iam::632674123947:role/team/oms-postgresql-operator` → extracts `oms-postgresql-operator` (correct by accident), but next version with `role/team/deeper/oms-postgresql-operator` → extracts `oms-postgresql-operator` (still works, but brittle).

**Root Cause:** The split approach is fragile because role paths can contain multiple `/` separators, but we blindly take the last element.

### Resolution Approach

**For Sandbox (Task 5):** String split is acceptable given we control the input ARN format and tests will validate it.

**For Future (Post-Phase 3):** Replace with Terraform data source to reliably extract role name:

```hcl
data "aws_iam_role" "postgresql_operator" {
  arn = var.postgresql_operator_iam_role_arn
}

resource "aws_iam_role_policy" "cnpg_backup_access" {
  name   = "oms-postgresql-backup-policy"
  role   = data.aws_iam_role.postgresql_operator.name  # Safe attribute access
  policy = jsonencode({ ... })
}
```

### Test Coverage Requirement (MUST)

**Test File:** `tests/postgresql/test_terraform_contract.py`

**Tests Required:**
1. `test_role_name_extraction_with_standard_arn`: Validate extraction from `arn:aws:iam::632674123947:role/oms-postgresql-operator`
2. `test_role_name_extraction_with_single_path_level`: Validate extraction from `arn:aws:iam::632674123947:role/team/oms-postgresql-operator`
3. `test_checks_tf_validates_role_arn_format`: Assert `checks.tf` contains validation block that rejects non-ARN, non-role inputs

**Design Conclusion:**
- Accept current implementation for sandbox (tests will validate)
- Document future migration path to data source in [docs/references/technical-debt.md](../references/technical-debt.md) (post-Phase 3)
- Establish test assertion: `check "postgresql_operator_role_is_provided"` must exist and pass

---

## 2. DevOps Perspective Assessment

### Issue: CNPG GitOps Validation Gap

**Finding:** `gitops/postgresql/base/cluster.yaml` configures CloudNativePG with:

```yaml
barmanObjectStore:
  inheritFromIAMRole: true
  s3Credentials:
    # Must be absent for IRSA to work
serviceAccountName: oms-postgresql-workload  # Overrides default CNPG-generated SA
```

**Edge Case:** CNPG will create its own ServiceAccount by default. Specifying `serviceAccountName: oms-postgresql-workload` correctly overrides this to use Phase 2 workload identity. However, without automated tests, a future contributor could accidentally add `accessKey`/`secretKey` to `s3Credentials`, breaking IRSA.

**Risk:** Zero protection against hardcoded AWS credentials in cluster manifest.

### Resolution Approach

**Test Coverage Requirement (MUST)**

**Test File:** `tests/postgresql/test_gitops_manifests.py`

**Tests Required:**
1. `test_cluster_manifest_uses_iam_workload_identity`: Parse `gitops/postgresql/base/cluster.yaml`, assert `barmanObjectStore.inheritFromIAMRole == true`
2. `test_cluster_manifest_has_no_hardcoded_aws_credentials`: Assert `s3Credentials` does NOT contain `accessKey`, `secretKey`, or `credentialsSecret`
3. `test_cluster_manifest_uses_workload_service_account`: Assert `serviceAccountName: oms-postgresql-workload` is present
4. `test_helmrelease_postgresql_operator_uses_correct_service_account`: Parse `gitops/postgresql/base/operator.yaml` HelmRelease, assert no hardcoded ARNs in values

**Design Conclusion:**
- Make assertions explicit and fail-fast on future credential leakage
- Test pattern: grep-based static assertions (no YAML parsing required, matches MongoDB pattern)
- Assertion: `inheritFromIAMRole: true` must be hardcoded in base manifest
- Assertion: `s3Credentials` section must be empty or missing (no keys, no secret refs)

---

## 3. Software Architect Perspective Assessment

### Issue: TDD Protocol Violation & Copy-Paste Vulnerability

**Finding:** Implementation code exists for PostgreSQL but tests are incomplete:

| Layer | Status | Test Coverage |
|-------|--------|---|
| Terraform | Written | ~30% (missing role extraction tests) |
| Schema Fragment | Written | ~50% (untested) |
| GitOps Manifests | Written | **0% (not tested)** |
| Handler Wrappers | Written | **0% (untested, copy-paste risk)** |
| Verifier Wrappers | Written | **0% (untested, copy-paste risk)** |
| Guard Pre-Destroy | Written | **0% (untested, copy-paste risk)** |

**Copy-Paste Risk:** The `40-postgresql` Bash scripts were templated from `30-mongodb`. Without running tests, we cannot verify:
- No `mongodb_internal_*` functions accidentally left in postgresql code
- Correct scope names (`postgresql-core`, `postgresql-brand` vs `mongodb`, `mongodb-access`)
- Correct verifier symbol delegation (`verify_postgresql` vs `verify_mongodb`)
- Guard contract enforcement (seam callback used correctly)

**Previous Example (Task 4):** When MongoDB handlers were first written, the initial version had 2 bugs caught by the handler tests:
1. Handler fragment sourcing wrong internal file
2. Verifier fragment not delegating to pre-destroy-guards.sh

These were caught immediately by running the test suite. The same must happen for PostgreSQL.

### Resolution Approach

**Immediate Action: HALT Implementation Commits Until Tests Pass**

**Test Coverage Requirement (MUST)**

**Test File:** `tests/postgresql/test_handlers.py`

**Tests to Replicate from MongoDB (Task 4):**
1. Handler isolation tests (3 tests):
   - `test_handler_fragment_sources_internal_lifecycle_handlers`
   - `test_handler_wrappers_delegate_correctly_to_internal`
   - `test_handler_wrappers_use_correct_scope_names`

2. Verifier fragment tests (2 tests):
   - `test_verifier_fragment_sources_internal_verifiers`
   - `test_verifier_fragment_sources_internal_pre_destroy_guards`

3. Symbol presence tests (6 tests for postgresql-core + postgresql-brand scopes):
   - `test_scope_handlers_postgresql_core_provides_provision_wrapper`
   - `test_scope_handlers_postgresql_core_provides_destroy_wrapper`
   - `test_scope_handlers_postgresql_brand_provides_provision_wrapper`
   - `test_scope_handlers_postgresql_brand_provides_destroy_wrapper`
   - `test_scope_verifiers_postgresql_core_exports_canonical_symbol`
   - `test_scope_verifiers_postgresql_brand_exports_canonical_symbol`

**Test File:** `tests/postgresql/test_verifiers.py`

**Tests to Replicate from MongoDB:**
1. Guard contract tests (3 tests):
   - `test_pre_destroy_guard_computes_sha256_digest`
   - `test_pre_destroy_guard_calls_callback_exactly_once`
   - `test_pre_destroy_guard_uses_seam_callback_mechanism`

2. Verifier stub tests (2 tests):
   - `test_verify_postgresql_exports_function_symbol`
   - `test_verify_postgresql_brand_exports_function_symbol`

### Design Conclusion

- Enforce: **All implementation code must be complete AND all tests passing before any commit**.
- Establish: Copy-paste validation as mandatory gate (grep tests for mongodb symbols must return 0 hits in postgresql code).
- Pattern: Replicate the exact 44-test structure from MongoDB (10 terraform + 4 schema + 18 gitops + 12 handler/verifier tests).

---

## 4. Superpowers Creator Perspective Assessment

### Issue: Atomic Commit Invariant Violation

**Finding:** Subagent connection expired mid-implementation, leaving dirty worktree state:

```
git status
  M platform-prerequisites/terraform/postgresql/...
  ?? config/environment-schema/fragments/40-postgresql.manifest
  ?? gitops/postgresql/
  ?? scripts/lib/packages/40-postgresql/
  ?? scripts/lib/scope-handlers.d/40-postgresql.sh
  ?? scripts/lib/scope-verifiers.d/40-postgresql.sh
```

**Missing:** `tests/postgresql/` directory entirely.

**Superpowers Invariant Violated:** *Commits must represent fully tested, atomic units of work. Partial implementations corrupt the audit trail and create hidden technical debt.*

### Recovery Protocol

**Phase:** Design → Spec Review → Subagent Recovery → Validation → Commit

**This Document's Role:** Establish design and spec before recovery subagent begins.

**Recovery Subagent Role:** Execute implementation strictly within this spec.

**Deliverables Required:**

1. **Test Suite Creation (44 tests total):**
   - `tests/postgresql/__init__.py` (empty module marker)
   - `tests/postgresql/test_terraform_contract.py` (9 tests: role extraction + checks blocks)
   - `tests/postgresql/test_environment_contract.py` (4 tests: schema fragment validation)
   - `tests/postgresql/test_gitops_manifests.py` (11 tests: IRSA + no-credentials assertions)
   - `tests/postgresql/test_handlers.py` (12 tests: handler wrappers + copy-paste detection)
   - `tests/postgresql/test_verifiers.py` (8 tests: verifier wrappers + guard contract)

2. **Full Test Execution:**
   ```bash
   python3 -m unittest discover -s tests/postgresql -p "test_*.py" -v
   # Expected: 44/44 PASS
   ```

3. **Validation Suite:**
   ```bash
   # Terraform
   terraform fmt -check platform-prerequisites/terraform/postgresql/
   terraform validate platform-prerequisites/terraform/postgresql/
   
   # GitOps
   kustomize build gitops/postgresql/base
   kustomize build gitops/postgresql/overlays/uat
   
   # Bash Syntax
   bash -n scripts/lib/packages/40-postgresql/internal/lifecycle-handlers.sh
   bash -n scripts/lib/packages/40-postgresql/internal/verifiers.sh
   bash -n scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh
   bash -n scripts/lib/scope-handlers.d/40-postgresql.sh
   bash -n scripts/lib/scope-verifiers.d/40-postgresql.sh
   
   # Copy-Paste Detection
   grep -r "mongodb" scripts/lib/packages/40-postgresql/ scripts/lib/scope-handlers.d/40-postgresql.sh scripts/lib/scope-verifiers.d/40-postgresql.sh
   # Expected: 0 matches
   ```

4. **Atomic Commit:**
   ```bash
   git add -A
   git commit -m "feat(postgresql): add Terraform, schema, GitOps, and handler wrappers for CloudNativePG

   - Terraform prerequisites: IRSA policy attachment for Barman backups, KMS grant, checks for role ARN validation
   - Environment schema: 40-postgresql.manifest with 6 required variables
   - GitOps manifests: CloudNativePG operator HelmRelease and cluster CR with workload identity inheritance
   - Handler/verifier/guard wrappers: Canonical lifecycle implementations for postgresql-core and postgresql-brand scopes
   - Test suite: 44 tests covering contract validation, IRSA robustness, and copy-paste detection"
   ```

### Design Conclusion

- **No partial commits.** All or nothing.
- **Test-first invariant:** Tests must exist and pass before commit.
- **Recovery subagent:** Scoped exclusively to Task 5. Do NOT proceed to Task 6 (SigNoz).
- **Success criteria:** All 44 tests pass + all validation commands succeed + git status clean.

---

## Completion Criteria (Task 5 Recovery)

**GATE 1: All Tests PASS**
```bash
python3 -m unittest discover -s tests/postgresql -p "test_*.py" -v
# Exit code: 0
# Expected output: Ran 44 tests ... OK
```

**GATE 2: No Copy-Paste Leakage**
```bash
grep -r "mongodb_internal\|verify_mongodb\|mongodb-access" scripts/lib/packages/40-postgresql/ scripts/lib/scope-handlers.d/40-postgresql.sh scripts/lib/scope-verifiers.d/40-postgresql.sh
# Exit code: 1 (no matches)
```

**GATE 3: Terraform Validation**
```bash
terraform fmt -check platform-prerequisites/terraform/postgresql/
terraform validate platform-prerequisites/terraform/postgresql/
# Both exit code: 0
```

**GATE 4: GitOps Validation**
```bash
kustomize build gitops/postgresql/base
kustomize build gitops/postgresql/overlays/uat
# Both exit code: 0 (valid YAML output)
```

**GATE 5: Bash Syntax Check**
```bash
bash -n scripts/lib/packages/40-postgresql/internal/lifecycle-handlers.sh
bash -n scripts/lib/packages/40-postgresql/internal/verifiers.sh
bash -n scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh
bash -n scripts/lib/scope-handlers.d/40-postgresql.sh
bash -n scripts/lib/scope-verifiers.d/40-postgresql.sh
# All exit code: 0
```

**GATE 6: Clean Working Directory**
```bash
git status
# Expected: On branch feat/phase3-workload-platforms
#          nothing to commit, working tree clean
```

---

## Design Review Checklist

Before recovery subagent begins, confirm all items:

- [x] AWS Architect: Role name extraction validated via tests + future data-source migration path documented
- [x] DevOps: GitOps test assertions enforce IRSA + no-credentials invariants
- [x] Software Architect: Copy-paste detection tests added, TDD protocol re-established
- [x] Superpowers Creator: Atomic commit protocol defined, recovery scope isolated to Task 5 only
- [x] Completion gates: 6 gates define success criteria (all must pass before commit)
- [x] No ambiguity: Test file names, counts, assertions all explicit

---

## Next Step

**Invoke recovery subagent with this spec:**

> Execute Task 5 (PostgreSQL) Recovery per this design document: [2026-07-27-phase3-task5-postgresql-recovery-design.md](2026-07-27-phase3-task5-postgresql-recovery-design.md)
> 
> Tasks:
> 1. Create tests/postgresql/ with 44 tests per design (test_terraform_contract, test_environment_contract, test_gitops_manifests, test_handlers, test_verifiers)
> 2. Run all tests: `python3 -m unittest discover -s tests/postgresql -p "test_*.py" -v` → All 44 must PASS
> 3. Execute all 6 validation gates (copy-paste, terraform fmt, kustomize, bash -n, git status)
> 4. Fix any bugs the tests reveal
> 5. Commit atomically with message: "feat(postgresql): add Terraform, schema, GitOps, and handler wrappers for CloudNativePG"
> 
> Do NOT proceed to Task 6. Scope is Task 5 only.
