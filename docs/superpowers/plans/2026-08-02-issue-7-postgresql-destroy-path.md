# Issue #7: PostgreSQL Destroy Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `destroy_postgresql_k8s()` to `scripts/legacy/dev/destroy.sh`, mirroring `destroy_mongodb_k8s()`'s pattern, wire it into the `pg` scope before its Terraform teardown, and update the affected tests.

**Architecture:** One new function deletes the CNPG `Cluster` and operator `HelmRelease` (in that order, per D2), called from `destroy_pg()` before `terraform_destroy_scope pg` — mirroring `destroy_mongodb()`'s exact `destroy_mongodb_k8s(); terraform_destroy_scope mongodb` shape.

**Tech Stack:** bash (`scripts/legacy/dev/destroy.sh`), Python `unittest` (structural tests only, mocked `kubectl`/`terraform`/`aws` binaries — no live execution, matching the existing `LegacyDestroyFixture` pattern in `tests/environment_orchestration/test_entrypoints.py`).

## Global Constraints

- No `kubectl`, `terraform`, or `aws` command may be executed against a real cluster/account — every test uses the existing mocked-binary `LegacyDestroyFixture`.
- Delete the `Cluster` resource before the operator `HelmRelease` (D2) — never the reverse.
- Leave the `postgresql` and `postgresql-operator` namespaces in place (D3) — do not delete them.
- No changes to `confirm_destruction`, `export_scope_if_requested`, the `all` scope's dispatch, or the unified orchestrator's pre-destroy guard system — all already correctly handle `pg` (D5).

---

### Task 1: Add `destroy_postgresql_k8s()` and wire it into `destroy_pg()`

**Files:**
- Modify: `scripts/legacy/dev/destroy.sh`
- Modify: `tests/environment_orchestration/test_entrypoints.py`

**Interfaces:**
- Produces: `destroy_postgresql_k8s()`, called by `destroy_pg()` before `terraform_destroy_scope pg`.

- [ ] **Step 1: Write the failing test**

Modify `tests/environment_orchestration/test_entrypoints.py`'s
`test_pg_reaches_terraform_destroy_and_stops_there` (in
`LegacyDestroyRegressionTests`) to also assert the new k8s teardown calls
happen first:

```python
    def test_pg_reaches_terraform_destroy_and_stops_there(self):
        result = self.run_destroy(["pg", "--auto-approve"])
        self.assertEqual(result.returncode, 97, result.stderr)
        log = self.command_log_lines()
        self.assertTrue(
            any(
                line.startswith("kubectl ") and "delete" in line and "cluster" in line
                for line in log
            ),
            log,
        )
        self.assertTrue(
            any(
                line.startswith("kubectl ") and "delete" in line and "helmrelease" in line
                for line in log
            ),
            log,
        )
        cluster_index = next(
            i for i, line in enumerate(log)
            if line.startswith("kubectl ") and "delete" in line and "cluster" in line
        )
        helmrelease_index = next(
            i for i, line in enumerate(log)
            if line.startswith("kubectl ") and "delete" in line and "helmrelease" in line
        )
        self.assertLess(cluster_index, helmrelease_index, log)
        self.assertTrue(
            any(
                "bootstrap-terraform-s3-backend.sh" in line and "pg.tfstate" in line
                for line in log
            ),
            log,
        )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/environment_orchestration/test_entrypoints.py::LegacyDestroyRegressionTests::test_pg_reaches_terraform_destroy_and_stops_there -v`
Expected: FAIL — no `kubectl delete cluster`/`kubectl delete helmrelease` calls exist yet, `destroy_pg()` only calls `terraform_destroy_scope pg`.

- [ ] **Step 3: Implement `destroy_postgresql_k8s()`**

Add alongside `destroy_mongodb_k8s()` in `scripts/legacy/dev/destroy.sh`:

```bash
destroy_postgresql_k8s() {
  echo "Removing PostgreSQL CNPG Cluster resource..."
  kubectl -n postgresql delete cluster oms-postgresql --ignore-not-found=true || true

  echo "Removing CNPG operator..."
  kubectl -n postgresql-operator delete helmrelease cloudnative-pg --ignore-not-found=true || true
}
```

- [ ] **Step 4: Wire it into `destroy_pg()`**

Modify:
```bash
destroy_pg() {
  destroy_postgresql_k8s
  terraform_destroy_scope pg
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/environment_orchestration/test_entrypoints.py -v`
Expected: PASS — full file, not just the one modified test, to confirm no other pre-existing test regressed (in particular `test_all_completes_signoz_steps_then_stops_at_first_terraform_failure`, which should still pass unchanged: the `all` scope's mongodb Terraform destroy fails first under `set -e`, so `destroy_pg` — and this task's new k8s calls — are never reached in that test).

- [ ] **Step 6: Run `bash -n` syntax check**

Run: `bash -n scripts/legacy/dev/destroy.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/legacy/dev/destroy.sh tests/environment_orchestration/test_entrypoints.py
git commit -m "fix(postgresql): add destroy_postgresql_k8s to destroy.sh pg scope (closes #7)"
```

---

### Task 2: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full repo test suite**

Run: `env -u TF_DATA_DIR python -m pytest tests/ -q`
Expected: all tests pass, no regressions anywhere else in the repo.

- [ ] **Step 2: Commit any stragglers**

```bash
git status --short
git add -A
git commit -m "chore(issue-7): finalize" --allow-empty
```
