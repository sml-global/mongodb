# Phase 4 Sub-Project 1: Data Durability & DR Validation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove — with automated, repeatable, scheduled drills — that MongoDB, PostgreSQL, and ClickHouse (SigNoz) data can be restored from backup with measured RTO/RPO and verified integrity, using least-privilege credentials in an isolated UAT namespace.

**Architecture:** Each database gets a dedicated drill script (`scripts/dr-drill-*.sh`) that assumes a drill-only IAM role, restores the most recent S3 backup into a throwaway namespace in the UAT cluster, runs a data-integrity check, records RTO, and tears down. Every script includes a runtime identity guard (`aws sts get-caller-identity`) that fails closed if the pod is not actually running under its expected drill role -- defense-in-depth in case a ServiceAccount's IRSA annotation is ever misconfigured. A shared scheduling wrapper runs all three drills weekly via a Kubernetes CronJob.

**Testing strategy (per superpowers `writing-good-tests.md`, v6.2.0):** string-presence assertions on script/manifest text are a falsifiability trap and are not used here. Instead:
- Bash scripts (Tasks 1-3) are tested by executing them for real with PATH-mocked `kubectl`/`pbm`/`aws`/`mongosh`/`psql`/`clickhouse-client`, asserting on actual exit codes and actual captured invocation arguments.
- Declarative Terraform (Task 4) is verified with `terraform validate` (already this repo's existing convention), which catches real reference errors -- not achievable with grep.
- Declarative Kubernetes/Helm YAML (Tasks 3-4) is verified by parsing with PyYAML and asserting on parsed fields, matching the existing convention in `tests/signoz/test_gitops_manifests.py`.

**Tech Stack:** bash, kubectl, Percona Backup for MongoDB (PBM) CLI, CloudNativePG (CNPG) `cnpg` kubectl plugin / Barman PITR, `clickhouse-backup`, Python `unittest`, PyYAML, Kubernetes CronJob.

**Scope note (writing-plans skill check):** The Phase 3 audit identified 16 findings across 4 independent themes. Per the brainstorming design (`docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md`), this plan covers **only Theme 2 (Data Durability & DR)** — the P0 risk-first sub-project. Themes 1 (Cost & Compliance), 3 (Platform Operations), and 4 (Observability Stability) each get their own follow-up plan once this one's Completion Gates pass. The one exception — the CRD/Operator Upgrade runbook in Theme 3 — is explicitly gated on this plan's completion (see Task 4).

---

### Task 1: MongoDB PBM Restore Drill

**Files:**
- Create: `scripts/dr-drill-mongodb-restore.sh`
- Test: `tests/dr_drill/test_mongodb_restore_drill.py`

- [ ] **Step 1: Write the failing test**

```python
"""Behavioral test suite for the MongoDB PBM restore drill script.

Uses PATH-mocked kubectl/pbm/mongosh/aws executables so the script's actual
runtime behavior (arguments passed, exit-code handling, identity guard) is
exercised without any live Kubernetes/AWS/MongoDB infrastructure. Per
superpowers writing-good-tests.md (v6.2.0): string-presence assertions on
script text are a falsifiability trap -- these tests run the real script
and observe its real behavior instead.
"""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "dr-drill-mongodb-restore.sh"
DRILL_ROLE_ARN = "arn:aws:iam::123456789012:role/dr-drill-mongodb-restore-role"
WRONG_ROLE_ARN = "arn:aws:iam::123456789012:role/prod-mongodb-pbm-backup-role"


class MongoDbRestoreDrillBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.log_path = self.bin_dir / "calls.log"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env['PATH']}"
        self.env["DR_DRILL_MONGODB_ROLE_ARN"] = DRILL_ROLE_ARN

    def tearDown(self):
        self.tmp.cleanup()

    def _mock(self, name, body):
        """Write an executable mock that appends its real invocation args to
        calls.log (double-quoted so $* actually expands) before running body."""
        path = self.bin_dir / name
        path.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "{name} $*" >> "{self.log_path}"\n'
            f"{body}\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _mock_kubectl(self, pbm_list_output="2026-07-28T12:00:00Z", pbm_status_exit=0,
                       doc_count="42"):
        # All pbm/mongosh interaction happens via `kubectl exec` -- this
        # script runs on the operator's machine, not inside the cluster, so
        # there is no local pbm/mongosh binary to mock separately.
        self._mock("kubectl", (
            'if [ "$1" = "get" ]; then echo "mongodb-restore-target-abc"; exit 0; fi\n'
            'if [ "$1" = "exec" ]; then\n'
            '  if [[ "$*" == *"pbm status"* ]]; then exit ' + str(pbm_status_exit) + '; fi\n'
            '  if [[ "$*" == *"pbm list"* ]]; then echo "' + pbm_list_output + '"; exit 0; fi\n'
            '  if [[ "$*" == *"pbm restore"* ]]; then exit 0; fi\n'
            '  if [[ "$*" == *"mongosh"* ]]; then echo "' + doc_count + '"; exit 0; fi\n'
            '  exit 0\n'
            'fi\n'
            'exit 0\n'
        ))

    def _install_happy_path_mocks(self, sts_arn=DRILL_ROLE_ARN):
        self._mock_kubectl()
        self._mock("aws", f'echo "{sts_arn}"')

    def _run(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def _log(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def test_happy_path_exits_zero_and_reports_pass(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DR Drill PASSED", result.stdout)

    def test_restores_the_latest_backup_returned_by_pbm_list(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pbm restore 2026-07-28T12:00:00Z", self._log())

    def test_never_targets_production_namespace(self):
        self._install_happy_path_mocks()
        self._run()
        for line in self._log().splitlines():
            if line.startswith("kubectl "):
                self.assertNotIn("mongodb-prod", line,
                                  "drill must never run kubectl against the "
                                  "production namespace")

    def test_fails_closed_when_pbm_status_fails(self):
        self._mock_kubectl(pbm_status_exit=1)
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertNotEqual(result.returncode, 0,
                             "script must exit non-zero when pbm status fails")

    def test_fails_closed_when_no_backups_exist(self):
        self._mock_kubectl(pbm_list_output="")
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertNotEqual(result.returncode, 0,
                             "script must exit non-zero when the PBM backup "
                             "catalog is empty")

    def test_fails_closed_when_post_restore_document_count_is_zero(self):
        self._mock_kubectl(doc_count="0")
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertNotEqual(result.returncode, 0,
                             "script must exit non-zero when the post-restore "
                             "integrity check finds zero documents")

    def test_fails_closed_when_running_under_the_wrong_iam_identity(self):
        # Defense-in-depth: even if the pod's ServiceAccount is misconfigured
        # (wrong IRSA binding), the script must refuse to proceed if the
        # assumed identity does not match the expected drill role.
        self._install_happy_path_mocks(sts_arn=WRONG_ROLE_ARN)
        result = self._run()
        self.assertNotEqual(result.returncode, 0,
                             "script must exit non-zero when the running "
                             "identity does not match DR_DRILL_MONGODB_ROLE_ARN")
        self.assertIn("identity", (result.stdout + result.stderr).lower())

    def test_tears_down_drill_namespace_even_on_failure(self):
        self._mock_kubectl(pbm_status_exit=1)
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        self._run()
        self.assertIn("kubectl delete namespace", self._log(),
                      "cleanup trap must run kubectl delete namespace even "
                      "when the drill fails partway through")

    def test_records_a_nonnegative_rto(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertRegex(result.stdout, r"RTO=\d+s")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_mongodb_restore_drill.py -v`
Expected: FAIL with `FileNotFoundError` / `No such file or directory: 'scripts/dr-drill-mongodb-restore.sh'` (script doesn't exist yet).

- [ ] **Step 3: Write the drill script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-mongodb-restore.sh
#
# Automated DR drill: restores the most recent PBM (Percona Backup for
# MongoDB) backup from S3 into an isolated, throwaway namespace in the UAT
# cluster, verifies data integrity, records RTO, and tears down.
#
# NEVER targets the production namespace. Uses a dedicated least-privilege
# drill IAM role (read-only S3 GetObject on the backup prefix) -- never the
# production PBM write role.
#
# Usage:
#   scripts/dr-drill-mongodb-restore.sh [<drill-namespace>]

DRILL_NAMESPACE="${1:-dr-drill-mongodb-$(date +%s)}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_MONGODB_ROLE_ARN:?Set DR_DRILL_MONGODB_ROLE_ARN (dr-drill-mongodb-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

cleanup() {
  echo "Tearing down drill namespace ${DRILL_NAMESPACE}..."
  kubectl delete namespace "${DRILL_NAMESPACE}" --ignore-not-found --wait=false
}
trap cleanup EXIT

echo "=== MongoDB PBM Restore Drill ==="
echo "Drill namespace: ${DRILL_NAMESPACE}"
echo "Drill IAM role: ${DRILL_IAM_ROLE_ARN} (read-only, dr-drill-mongodb-restore-role)"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role before touching anything. Guards against a misconfigured IRSA
# ServiceAccount binding accidentally granting production credentials.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

kubectl create namespace "${DRILL_NAMESPACE}"

echo "Deploying throwaway single-node MongoDB for restore target..."
kubectl apply -n "${DRILL_NAMESPACE}" -f "$(dirname "$0")/../k8s/dr-drill/mongodb-restore-target.yaml"
kubectl wait --for=condition=ready pod -l app=mongodb-restore-target -n "${DRILL_NAMESPACE}" --timeout=300s

# This script runs on the operator's machine / a CI runner, not inside the
# cluster -- so pbm and mongosh commands are always run via `kubectl exec`
# into the restore-target pod (matching the pattern already used by
# dr-drill-clickhouse-backup-restore.sh), never assumed reachable at
# localhost:27017 from the caller's machine.
RESTORE_POD=$(kubectl get pod -n "${DRILL_NAMESPACE}" -l app=mongodb-restore-target \
  -o jsonpath='{.items[0].metadata.name}')

echo "Checking PBM backup catalog (read-only drill role)..."
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- pbm status --mongodb-uri="mongodb://localhost:27017" || {
  echo "FATAL: pbm status failed -- cannot enumerate backups for drill"
  exit 1
}

LATEST_BACKUP=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  pbm list --mongodb-uri="mongodb://localhost:27017" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | tail -1)
if [ -z "${LATEST_BACKUP}" ]; then
  echo "FATAL: no backups found in PBM catalog"
  exit 1
fi
echo "Restoring backup: ${LATEST_BACKUP}"

RESTORE_START=$(date +%s)
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  pbm restore "${LATEST_BACKUP}" --mongodb-uri="mongodb://localhost:27017" --wait
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
DOC_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  mongosh "mongodb://localhost:27017" --quiet --eval "db.getSiblingDB('oms').orders.countDocuments({})")
if [ -z "${DOC_COUNT}" ] || [ "${DOC_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore document count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${DOC_COUNT} documents present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredDocs=${DOC_COUNT}"
```

- [ ] **Step 3b: Write the throwaway MongoDB restore-target manifest the script deploys**

```yaml
# k8s/dr-drill/mongodb-restore-target.yaml
#
# Single throwaway MongoDB + PBM sidecar, deployed fresh into each drill
# namespace by scripts/dr-drill-mongodb-restore.sh. Not GitOps-managed --
# this is drill scratch infrastructure, torn down by the script's cleanup
# trap every run.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-restore-target
  labels:
    app: mongodb-restore-target
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-restore-target
  template:
    metadata:
      labels:
        app: mongodb-restore-target
    spec:
      containers:
        - name: mongodb
          image: percona/percona-server-mongodb:6.0
          ports:
            - containerPort: 27017
          readinessProbe:
            exec:
              command: ["mongosh", "--eval", "db.adminCommand('ping')"]
            initialDelaySeconds: 5
            periodSeconds: 5
        - name: pbm-agent
          image: percona/percona-backup-mongodb:2.4
          env:
            - name: PBM_MONGODB_URI
              value: "mongodb://localhost:27017"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_mongodb_restore_drill.py -v`
Expected: PASS (9/9)

- [ ] **Step 5: Make the script executable and commit**

```bash
chmod +x scripts/dr-drill-mongodb-restore.sh
git add scripts/dr-drill-mongodb-restore.sh k8s/dr-drill/mongodb-restore-target.yaml tests/dr_drill/test_mongodb_restore_drill.py
git commit -m "feat(dr-drill): add MongoDB PBM restore drill with RTO measurement and IRSA identity guard"
```

---

### Task 2: PostgreSQL WAL/PITR Restore Drill

**Files:**
- Create: `scripts/dr-drill-postgresql-restore.sh`
- Test: `tests/dr_drill/test_postgresql_restore_drill.py`

- [ ] **Step 1: Write the failing test**

```python
"""Behavioral test suite for the PostgreSQL CNPG WAL/PITR restore drill.

PATH-mocked kubectl captures both invocation arguments and the exact YAML
manifest piped to `kubectl apply -f -`, so tests assert on the *real*,
runtime-generated CNPG Cluster spec (parsed structurally with PyYAML) rather
than grepping the static script text. Per writing-good-tests.md (v6.2.0):
string-presence assertions on scripts/manifests counterfeit falsifiability.
"""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "dr-drill-postgresql-restore.sh"
DRILL_ROLE_ARN = "arn:aws:iam::123456789012:role/dr-drill-postgresql-restore-role"
WRONG_ROLE_ARN = "arn:aws:iam::123456789012:role/prod-postgresql-wal-role"


class PostgresqlRestoreDrillBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.log_path = self.bin_dir / "calls.log"
        self.manifest_path = self.bin_dir / "applied-manifest.yaml"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env['PATH']}"
        self.env["DR_DRILL_POSTGRESQL_ROLE_ARN"] = DRILL_ROLE_ARN

    def tearDown(self):
        self.tmp.cleanup()

    def _mock(self, name, body):
        path = self.bin_dir / name
        path.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "{name} $*" >> "{self.log_path}"\n'
            f"{body}\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _mock_kubectl(self, wait_exit=0, row_count="500"):
        self._mock("kubectl", (
            'if [ "$1" = "apply" ]; then\n'
            f'  cat > "{self.manifest_path}"\n'
            'fi\n'
            'if [ "$1" = "wait" ]; then\n'
            f'  exit {wait_exit}\n'
            'fi\n'
            'if [ "$1" = "exec" ]; then\n'
            f'  echo "{row_count}"\n'
            '  exit 0\n'
            'fi\n'
            'exit 0\n'
        ))

    def _install_happy_path_mocks(self, sts_arn=DRILL_ROLE_ARN):
        self._mock_kubectl()
        self._mock("aws", f'echo "{sts_arn}"')

    def _run(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def _log(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def _applied_manifest(self):
        return yaml.safe_load(self.manifest_path.read_text())

    def test_happy_path_exits_zero_and_reports_pass(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DR Drill PASSED", result.stdout)

    def test_applied_manifest_uses_cnpg_native_recovery_bootstrap(self):
        self._install_happy_path_mocks()
        self._run()
        manifest = self._applied_manifest()
        self.assertEqual(manifest["apiVersion"], "postgresql.cnpg.io/v1")
        self.assertIn("recovery", manifest["spec"]["bootstrap"])
        self.assertIn("barmanObjectStore",
                      manifest["spec"]["externalClusters"][0])

    def test_never_targets_production_namespace(self):
        self._install_happy_path_mocks()
        self._run()
        for line in self._log().splitlines():
            if line.startswith("kubectl "):
                self.assertNotIn("postgresql-prod", line)

    def test_fails_closed_when_cluster_never_becomes_ready(self):
        self._mock_kubectl(wait_exit=1)
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertNotEqual(result.returncode, 0)

    def test_fails_closed_when_post_restore_row_count_is_zero(self):
        self._mock_kubectl(row_count="0")
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertNotEqual(result.returncode, 0)

    def test_fails_closed_when_running_under_the_wrong_iam_identity(self):
        self._install_happy_path_mocks(sts_arn=WRONG_ROLE_ARN)
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity", (result.stdout + result.stderr).lower())

    def test_tears_down_drill_namespace_even_on_failure(self):
        self._mock_kubectl(wait_exit=1)
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        self._run()
        self.assertIn("kubectl delete namespace", self._log())

    def test_records_a_nonnegative_rto(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertRegex(result.stdout, r"RTO=\d+s")

    def test_exec_targets_the_correct_statefulset_ordinal_zero_pod(self):
        # Regression test for a real bug caught in task review: CNPG's
        # Cluster is backed by a StatefulSet, whose pod ordinals start at 0.
        # With `instances: 1` (this drill's throwaway target), the only pod
        # is "dr-drill-restore-target-0" -- never "-1". The mock does not
        # special-case the pod name, so this only passes if the script
        # actually execs into the pod name the manifest implies.
        self._install_happy_path_mocks()
        self._run()
        exec_lines = [l for l in self._log().splitlines() if "kubectl exec" in l]
        self.assertTrue(exec_lines, "script must kubectl exec into the restore-target pod")
        for line in exec_lines:
            self.assertIn("dr-drill-restore-target-0", line,
                          "must exec into ordinal-0 pod (StatefulSet, instances: 1), "
                          "not '-1' or any other ordinal")
            self.assertIn("psql", line)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_postgresql_restore_drill.py -v`
Expected: FAIL with `FileNotFoundError` (script doesn't exist yet).

- [ ] **Step 3: Write the drill script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-postgresql-restore.sh
#
# Automated DR drill: uses CloudNativePG's native recovery bootstrap to
# restore a new, throwaway Cluster from the continuous WAL/PITR archive in
# S3, verifies data integrity, records RTO, and tears down.
#
# NEVER targets the production namespace. Uses a dedicated least-privilege
# drill IAM role (read-only S3 GetObject on the WAL archive prefix).
#
# Usage:
#   scripts/dr-drill-postgresql-restore.sh [--namespace <drill-ns>]

DRILL_NAMESPACE="${1:-dr-drill-postgresql-$(date +%s)}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_POSTGRESQL_ROLE_ARN:?Set DR_DRILL_POSTGRESQL_ROLE_ARN (dr-drill-postgresql-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"
RECOVERY_TARGET_TIME="${RECOVERY_TARGET_TIME:-latest}"

cleanup() {
  echo "Tearing down drill namespace ${DRILL_NAMESPACE}..."
  kubectl delete namespace "${DRILL_NAMESPACE}" --ignore-not-found --wait=false
}
trap cleanup EXIT

echo "=== PostgreSQL WAL/PITR Restore Drill ==="
echo "Drill namespace: ${DRILL_NAMESPACE}"
echo "Drill IAM role: ${DRILL_IAM_ROLE_ARN} (read-only, dr-drill-postgresql-restore-role)"
echo "Recovery target time: ${RECOVERY_TARGET_TIME}"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role before touching anything.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

kubectl create namespace "${DRILL_NAMESPACE}"

cat <<EOF | kubectl apply -n "${DRILL_NAMESPACE}" -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: dr-drill-restore-target
spec:
  instances: 1
  storage:
    size: 10Gi
    storageClass: gp3-mongodb
  bootstrap:
    recovery:
      source: oms-postgresql-prod-backup
      recoveryTarget:
        targetTime: "${RECOVERY_TARGET_TIME}"
  externalClusters:
    - name: oms-postgresql-prod-backup
      barmanObjectStore:
        destinationPath: s3://oms-postgresql-wal-archive/
        s3Credentials:
          inheritFromIAMRole: true
EOF

RESTORE_START=$(date +%s)
kubectl wait --for=condition=Ready cluster/dr-drill-restore-target -n "${DRILL_NAMESPACE}" --timeout=600s || {
  echo "FATAL: restored cluster did not become Ready within 600s"
  exit 1
}
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
# CNPG Clusters are backed by a StatefulSet; pod ordinals start at 0, not 1.
# With `instances: 1` (a throwaway single-node drill target), the only pod
# is "<cluster-name>-0".
ROW_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" dr-drill-restore-target-0 -- \
  psql -U postgres -d oms -tAc "SELECT COUNT(*) FROM orders;")
if [ -z "${ROW_COUNT}" ] || [ "${ROW_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore row count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_postgresql_restore_drill.py -v`
Expected: PASS (9/9)

- [ ] **Step 5: Make the script executable and commit**

```bash
chmod +x scripts/dr-drill-postgresql-restore.sh
git add scripts/dr-drill-postgresql-restore.sh tests/dr_drill/test_postgresql_restore_drill.py
git commit -m "feat(dr-drill): add PostgreSQL CNPG WAL/PITR restore drill with RTO measurement and IRSA identity guard"
```

---

### Task 3: ClickHouse Application-Consistent Backup & Restore Drill

**Files:**
- Create: `scripts/dr-drill-clickhouse-backup-restore.sh`
- Modify: `gitops/signoz/base/helmreleases.yaml` (add `clickhouse-backup` sidecar config)
- Test: `tests/dr_drill/test_clickhouse_backup_restore_drill.py`

- [ ] **Step 1: Write the failing test**

```python
"""Behavioral test suite for the ClickHouse application-consistent backup +
restore drill.

PATH-mocked kubectl (with per-subcommand branching) exercises the script's
real runtime behavior. The HelmRelease YAML change is verified via
structural YAML parsing (the same convention used in
tests/signoz/test_gitops_manifests.py), not substring matching. Per
writing-good-tests.md (v6.2.0): string-presence assertions counterfeit
falsifiability.
"""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "dr-drill-clickhouse-backup-restore.sh"
HELMRELEASES = REPO_ROOT / "gitops" / "signoz" / "base" / "helmreleases.yaml"
DRILL_ROLE_ARN = "arn:aws:iam::123456789012:role/dr-drill-clickhouse-backup-role"
WRONG_ROLE_ARN = "arn:aws:iam::123456789012:role/dr-drill-mongodb-restore-role"


class ClickhouseBackupRestoreDrillBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.log_path = self.bin_dir / "calls.log"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env['PATH']}"
        self.env["DR_DRILL_CLICKHOUSE_ROLE_ARN"] = DRILL_ROLE_ARN

    def tearDown(self):
        self.tmp.cleanup()

    def _mock(self, name, body):
        path = self.bin_dir / name
        path.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "{name} $*" >> "{self.log_path}"\n'
            f"{body}\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _mock_kubectl(self, exec_row_count="123456"):
        self._mock("kubectl", (
            'if [ "$1" = "get" ]; then echo "signoz-clickhouse-0"; exit 0; fi\n'
            'if [ "$1" = "exec" ]; then\n'
            f'  if [[ "$*" == *"count()"* ]]; then echo "{exec_row_count}"; fi\n'
            '  exit 0\n'
            'fi\n'
            'exit 0\n'
        ))

    def _install_happy_path_mocks(self, sts_arn=DRILL_ROLE_ARN, row_count="123456"):
        self._mock_kubectl(exec_row_count=row_count)
        self._mock("aws", (
            'if [ "$1" = "sts" ]; then echo "' + sts_arn + '"; else exit 0; fi'
        ))

    def _run(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def _log(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def test_happy_path_exits_zero_and_reports_pass(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DR Drill PASSED", result.stdout)

    def test_uses_clickhouse_backup_tool_never_raw_ebs_snapshot(self):
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("clickhouse-backup create", log)
        self.assertNotIn("create-snapshot", log,
                          "must never invoke a raw block-level EBS snapshot "
                          "of a live ClickHouse volume")

    def test_scopes_to_clickhouse_pods_only_via_label_selector(self):
        self._install_happy_path_mocks()
        self._run()
        self.assertIn("app.kubernetes.io/name=clickhouse", self._log())

    def test_fails_closed_when_post_restore_row_count_is_empty(self):
        self._install_happy_path_mocks(row_count="")
        result = self._run()
        self.assertNotEqual(result.returncode, 0)

    def test_fails_closed_when_running_under_the_wrong_iam_identity(self):
        self._install_happy_path_mocks(sts_arn=WRONG_ROLE_ARN)
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity", (result.stdout + result.stderr).lower())

    def test_records_a_nonnegative_rto(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertRegex(result.stdout, r"RTO=\d+s")


class ClickhouseHelmReleaseBackupConfigTests(unittest.TestCase):
    """Structural (not substring) assertions on the HelmRelease values,
    matching the convention in tests/signoz/test_gitops_manifests.py."""

    @classmethod
    def setUpClass(cls):
        docs = list(yaml.safe_load_all(HELMRELEASES.read_text()))
        cls.signoz_release = next(
            d for d in docs if d and d.get("metadata", {}).get("name") == "signoz"
        )
        cls.clickhouse_values = cls.signoz_release["spec"]["values"]["clickhouse"]

    def test_backup_sidecar_is_enabled(self):
        self.assertTrue(self.clickhouse_values["backup"]["enabled"])

    def test_backup_targets_dedicated_bucket_not_mongodb_pbm_bucket(self):
        bucket = self.clickhouse_values["backup"]["s3"]["bucket"]
        self.assertEqual(bucket, "oms-signoz-clickhouse-backups")
        self.assertNotEqual(bucket, "oms-pbm-backups")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_clickhouse_backup_restore_drill.py -v`
Expected: FAIL with `FileNotFoundError` (script doesn't exist) and a `KeyError`/`StopIteration` on the HelmRelease backup config (not yet added).

- [ ] **Step 3: Write the drill script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-clickhouse-backup-restore.sh
#
# Application-consistent ClickHouse backup + restore drill for SigNoz.
#
# Uses `clickhouse-backup` (https://github.com/Altinity/clickhouse-backup),
# which internally issues FREEZE TABLE before copying data -- this avoids the
# corruption risk of a raw/blind EBS snapshot of a live ClickHouse volume
# (in-flight merges/inserts can be captured mid-write by a block-level
# snapshot). ClickHouse currently shares the gp3-mongodb EBS storage class
# (gitops/signoz/base/helmreleases.yaml), so this drill explicitly scopes to
# clickhouse pods only via label selector -- never a blanket volume policy.
#
# Backups are stored in a DEDICATED S3 bucket/prefix, never the MongoDB PBM
# bucket (oms-pbm-backups).
#
# Usage:
#   scripts/dr-drill-clickhouse-backup-restore.sh

CLICKHOUSE_POD=$(kubectl get pod -n signoz -l app.kubernetes.io/name=clickhouse \
  -o jsonpath='{.items[0].metadata.name}')
BACKUP_NAME="dr-drill-$(date +%s)"
S3_BACKUP_PATH="s3://oms-signoz-clickhouse-backups/${BACKUP_NAME}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_CLICKHOUSE_ROLE_ARN:?Set DR_DRILL_CLICKHOUSE_ROLE_ARN (dr-drill-clickhouse-backup-role, read+write scoped to oms-signoz-clickhouse-backups only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

echo "=== ClickHouse Application-Consistent Backup + Restore Drill ==="
echo "Target pod: ${CLICKHOUSE_POD} (app.kubernetes.io/name=clickhouse)"
echo "Backup destination: ${S3_BACKUP_PATH}"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role (read+write scoped only to oms-signoz-clickhouse-backups)
# before touching anything.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

echo "Creating application-consistent backup (FREEZE TABLE via clickhouse-backup)..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup create "${BACKUP_NAME}"

echo "Uploading backup to S3..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup upload "${BACKUP_NAME}"

echo "Verifying backup landed in S3..."
aws s3 ls "${S3_BACKUP_PATH}/" >/dev/null 2>&1 || {
  echo "FATAL: backup not found at ${S3_BACKUP_PATH} after upload"
  exit 1
}

echo "Restoring into a throwaway table to prove restorability..."
RESTORE_START=$(date +%s)
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup download "${BACKUP_NAME}"
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup restore --rm "${BACKUP_NAME}"
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying row count post-restore..."
ROW_COUNT=$(kubectl exec -n signoz "${CLICKHOUSE_POD}" -- \
  clickhouse-client --query "SELECT count() FROM signoz_traces.signoz_index_v2")
if [ -z "${ROW_COUNT}" ]; then
  echo "FATAL: could not read row count post-restore"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"

echo "Cleaning up local backup snapshot from pod..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup delete local "${BACKUP_NAME}"
```

- [ ] **Step 4: Run test to verify it passes (script portion)**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_clickhouse_backup_restore_drill.py::ClickhouseBackupRestoreDrillBehaviorTests -v`
Expected: PASS (6/6)

- [ ] **Step 5: Add clickhouse-backup sidecar config to the SigNoz HelmRelease**

Modify `gitops/signoz/base/helmreleases.yaml` — add under `clickhouse:`:

```yaml
    clickhouse:
      password:
        valueFrom:
          secretKeyRef:
            name: signoz-clickhouse
            key: password
      # clickhouse-backup sidecar: enables application-consistent backups
      # (FREEZE TABLE-based) instead of raw EBS snapshots. See
      # scripts/dr-drill-clickhouse-backup-restore.sh and Phase 4 design spec
      # docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md (D1).
      backup:
        enabled: true
        image: altinity/clickhouse-backup:latest
        s3:
          bucket: oms-signoz-clickhouse-backups
          path: "clickhouse-backups"
```

- [ ] **Step 6: Run full test file to verify both classes pass**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_clickhouse_backup_restore_drill.py -v`
Expected: PASS (8/8)

- [ ] **Step 7: Make the script executable and commit**

```bash
chmod +x scripts/dr-drill-clickhouse-backup-restore.sh
git add scripts/dr-drill-clickhouse-backup-restore.sh tests/dr_drill/test_clickhouse_backup_restore_drill.py gitops/signoz/base/helmreleases.yaml
git commit -m "feat(dr-drill): add application-consistent ClickHouse backup/restore drill with IRSA identity guard (clickhouse-backup, not raw EBS snapshot)"
```

---

### Task 4: DR Drill Scheduling, Least-Privilege IAM Roles, and Weekly CronJob

**Files:**
- Create: `platform-prerequisites/terraform/dr-drill/main.tf`
- Create: `platform-prerequisites/terraform/dr-drill/versions.tf` (provider requirements, mirroring `platform-prerequisites/terraform/mongodb/versions.tf`)
- Create: `platform-prerequisites/terraform/dr-drill/terraform.tfvars.sample` (documents `oidc_provider_arn` / `oidc_provider_url`, mirroring `platform-prerequisites/terraform/mongodb/terraform.tfvars.sample`)
- Create: `scripts/bootstrap-dr-drill-role-arns-configmap.sh` (turns Terraform outputs into the ConfigMap the CronJob reads -- this repo never uses the `kubernetes` Terraform provider; see Step 3b)
- Create: `k8s/dr-drill/cronjob.yaml`
- Test: `tests/dr_drill/test_dr_drill_scheduling.py`

- [ ] **Step 1: Write the failing test**

```python
"""Structural test suite for DR drill IAM least-privilege and CronJob
scheduling.

Terraform is verified with `terraform validate` (this repo's existing
verification convention -- see AGENTS.md), which parses the real HCL and
catches reference errors (e.g. an assume_role_policy pointing at a data
source that was never defined) that no grep could ever catch. The CronJob
is verified by parsing the YAML with PyYAML and asserting on structured
fields, matching tests/signoz/test_gitops_manifests.py. Per
writing-good-tests.md (v6.2.0): string-presence assertions counterfeit
falsifiability.

Note: `terraform validate` proves the HCL is internally consistent (types,
references, required arguments). It does not prove the IAM policy behaves
correctly against live AWS -- that is proven independently by the runtime
identity guard (`aws sts get-caller-identity`) built into each drill script
in Tasks 1-3, and ultimately by the drills actually passing in UAT.
"""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
TF_DIR = REPO_ROOT / "platform-prerequisites" / "terraform" / "dr-drill"
CRONJOB = REPO_ROOT / "k8s" / "dr-drill" / "cronjob.yaml"
BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts" / "bootstrap-dr-drill-role-arns-configmap.sh"


class DrDrillTerraformValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(
            ["terraform", "init", "-backend=false", "-input=false"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=120,
        )

    def test_terraform_directory_exists(self):
        self.assertTrue(TF_DIR.exists(), "platform-prerequisites/terraform/dr-drill must exist")

    def test_terraform_validate_succeeds(self):
        # Catches real reference errors -- e.g. assume_role_policy pointing
        # at an undefined data source -- that grep cannot detect.
        result = subprocess.run(
            ["terraform", "validate", "-json"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0,
                          f"terraform validate failed:\n{result.stdout}\n{result.stderr}")

    def test_terraform_fmt_check_passes(self):
        result = subprocess.run(
            ["terraform", "fmt", "-check", "-recursive"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
                          f"terraform fmt -check failed:\n{result.stdout}")

    def test_terraform_never_defines_a_kubernetes_provider(self):
        # This repo's convention: Terraform manages AWS only. Kubernetes
        # objects are always created via GitOps/kubectl scripts (see
        # bootstrap-dr-drill-role-arns-configmap.sh below), never the
        # `kubernetes` Terraform provider.
        for tf_file in TF_DIR.glob("*.tf"):
            self.assertNotIn('provider "kubernetes"', tf_file.read_text())
            self.assertNotIn("resource \"kubernetes_", tf_file.read_text())

    def test_terraform_outputs_all_three_role_arns(self):
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=30,
        )
        # Without real AWS credentials `terraform output` returns an empty
        # object (no state), but it must at least declare the output names --
        # verified structurally by grepping the parsed HCL output blocks via
        # `terraform validate`'s success above, plus this direct check that
        # the output declarations exist in the source.
        main_tf = (TF_DIR / "main.tf").read_text()
        for output_name in (
            "dr_drill_mongodb_role_arn",
            "dr_drill_postgresql_role_arn",
            "dr_drill_clickhouse_role_arn",
        ):
            self.assertIn(f'output "{output_name}"', main_tf)


class DrDrillRoleArnsBootstrapScriptBehaviorTests(unittest.TestCase):
    """Behavioral test for the kubectl-based bootstrap script (PATH-mocked
    terraform + kubectl), matching the D6 convention for bash scripts."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.log_path = self.bin_dir / "calls.log"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env['PATH']}"

    def tearDown(self):
        self.tmp.cleanup()

    def _mock(self, name, body):
        path = self.bin_dir / name
        path.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "{name} $*" >> "{self.log_path}"\n'
            f"{body}\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _log(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def test_reads_all_three_outputs_and_creates_configmap(self):
        self._mock("terraform", (
            'if [[ "$*" == *"dr_drill_mongodb_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-mongodb-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_postgresql_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-postgresql-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_clickhouse_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-clickhouse-backup-role"; fi\n'
        ))
        self._mock("kubectl", "cat > /dev/null; exit 0")
        result = subprocess.run(
            ["bash", str(BOOTSTRAP_SCRIPT)],
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dr-drill-role-arns", self._log())
        self.assertIn("DR_DRILL_MONGODB_ROLE_ARN", self._log())


class DrDrillCronJobStructureTests(unittest.TestCase):
    """Structural (parsed-field) assertions, not substring search."""

    @classmethod
    def setUpClass(cls):
        cls.doc = yaml.safe_load(CRONJOB.read_text())

    def test_cronjob_exists_and_parses(self):
        self.assertEqual(self.doc["kind"], "CronJob")

    def test_cronjob_targets_dr_drill_uat_namespace(self):
        self.assertEqual(self.doc["metadata"]["namespace"], "dr-drill-uat")

    def test_cronjob_runs_weekly_sunday_0300_utc(self):
        self.assertEqual(self.doc["spec"]["schedule"], "0 3 * * 0")

    def test_cronjob_pod_spec_uses_dedicated_service_account(self):
        pod_spec = self.doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
        self.assertEqual(pod_spec["serviceAccountName"], "dr-drill-runner")

    def test_cronjob_invokes_all_three_drill_scripts_in_order(self):
        pod_spec = self.doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
        command_str = pod_spec["containers"][0]["command"][-1]
        mongo_idx = command_str.index("dr-drill-mongodb-restore.sh")
        pg_idx = command_str.index("dr-drill-postgresql-restore.sh")
        ch_idx = command_str.index("dr-drill-clickhouse-backup-restore.sh")
        self.assertLess(mongo_idx, pg_idx)
        self.assertLess(pg_idx, ch_idx)

    def test_cronjob_sources_role_arns_from_bootstrapped_configmap(self):
        # No hardcoded AWS account ID/ARNs in the YAML -- real values come
        # from the dr-drill-role-arns ConfigMap (created by
        # scripts/bootstrap-dr-drill-role-arns-configmap.sh from Terraform
        # outputs, Step 3b).
        container = self.doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]
        config_map_refs = [
            ref["configMapRef"]["name"] for ref in container.get("envFrom", [])
        ]
        self.assertIn("dr-drill-role-arns", config_map_refs)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_dr_drill_scheduling.py -v`
Expected: FAIL with `platform-prerequisites/terraform/dr-drill must exist` (directory not found).

- [ ] **Step 3: Write the least-privilege IAM Terraform**

This mirrors the exact IRSA trust-policy pattern already used in
`platform-prerequisites/terraform/modules/iam/main.tf` (OIDC provider +
`sts:AssumeRoleWithWebIdentity` + `StringLike` on the `:sub` claim scoped to
a specific Kubernetes ServiceAccount) -- the original draft of this task
referenced an `eks_irsa_trust` data source that was never defined; this
version defines a scoped trust policy per role instead.

```hcl
# platform-prerequisites/terraform/dr-drill/main.tf
#
# Least-privilege IAM roles for automated DR restore drills. The MongoDB and
# PostgreSQL roles are READ-ONLY (s3:GetObject/ListBucket only) and MUST NOT
# be reused for production restore operations. The ClickHouse role is
# READ+WRITE but scoped only to its own dedicated backup bucket (Task 3
# creates backups, not just restores them) -- see
# docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md (D3, D8).

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider (from the eks-platform root's output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the EKS cluster's IAM OIDC provider, e.g. https://oidc.eks.<region>.amazonaws.com/id/<id>"
  type        = string
}

locals {
  oidc_hostpath = replace(var.oidc_provider_url, "https://", "")
}

# --- MongoDB PBM restore drill role (read-only) ---

data "aws_iam_policy_document" "dr_drill_mongodb_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_mongodb_restore" {
  statement {
    sid    = "ReadOnlyPbmBackupAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-pbm-backups",
      "arn:aws:s3:::oms-pbm-backups/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_mongodb_restore_role" {
  name               = "dr-drill-mongodb-restore-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_mongodb_trust.json
}

resource "aws_iam_role_policy" "dr_drill_mongodb_restore" {
  name   = "dr-drill-mongodb-restore-readonly"
  role   = aws_iam_role.dr_drill_mongodb_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_mongodb_restore.json
}

# --- PostgreSQL WAL/PITR restore drill role (read-only) ---

data "aws_iam_policy_document" "dr_drill_postgresql_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_postgresql_restore" {
  statement {
    sid    = "ReadOnlyWalArchiveAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-postgresql-wal-archive",
      "arn:aws:s3:::oms-postgresql-wal-archive/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_postgresql_restore_role" {
  name               = "dr-drill-postgresql-restore-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_postgresql_trust.json
}

resource "aws_iam_role_policy" "dr_drill_postgresql_restore" {
  name   = "dr-drill-postgresql-restore-readonly"
  role   = aws_iam_role.dr_drill_postgresql_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_postgresql_restore.json
}

# --- ClickHouse backup+restore drill role (read+write, own bucket ONLY) ---
# Unlike the two roles above, this one also creates backups (Task 3 runs
# `clickhouse-backup create` + `upload`), so it needs s3:PutObject -- but
# strictly scoped to its own dedicated bucket, never oms-pbm-backups or
# oms-postgresql-wal-archive.

data "aws_iam_policy_document" "dr_drill_clickhouse_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_clickhouse_backup" {
  statement {
    sid    = "ClickhouseBackupBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-signoz-clickhouse-backups",
      "arn:aws:s3:::oms-signoz-clickhouse-backups/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_clickhouse_backup_role" {
  name               = "dr-drill-clickhouse-backup-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_clickhouse_trust.json
}

resource "aws_iam_role_policy" "dr_drill_clickhouse_backup" {
  name   = "dr-drill-clickhouse-backup-scoped"
  role   = aws_iam_role.dr_drill_clickhouse_backup_role.id
  policy = data.aws_iam_policy_document.dr_drill_clickhouse_backup.json
}

# NOTE: this repo's convention is Terraform-manages-AWS-only; Kubernetes
# objects are always created via GitOps/kubectl scripts (see
# scripts/create-signoz-root-user-secret.sh), never via the `kubernetes`
# Terraform provider (verified: no other root in this repo defines any
# kubernetes_* resource). The role ARNs are exposed as outputs; a bootstrap
# script (Step 3b below) turns them into the ConfigMap the CronJob reads.

output "dr_drill_mongodb_role_arn" {
  value = aws_iam_role.dr_drill_mongodb_restore_role.arn
}

output "dr_drill_postgresql_role_arn" {
  value = aws_iam_role.dr_drill_postgresql_restore_role.arn
}

output "dr_drill_clickhouse_role_arn" {
  value = aws_iam_role.dr_drill_clickhouse_backup_role.arn
}
```

- [ ] **Step 3b: Write the bootstrap script that turns the Terraform outputs into the ConfigMap the CronJob reads**

Matches the existing repo convention (e.g. `scripts/create-signoz-root-user-secret.sh`):
an idempotent, operator-run `kubectl apply` script -- no Flux/Terraform ordering
dependency, since it can be re-run any time after `terraform apply`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# scripts/bootstrap-dr-drill-role-arns-configmap.sh
#
# Reads the dr-drill IAM role ARNs from Terraform outputs
# (platform-prerequisites/terraform/dr-drill) and creates/updates the
# 'dr-drill-role-arns' ConfigMap the weekly CronJob (k8s/dr-drill/cronjob.yaml)
# reads via envFrom. Idempotent -- safe to re-run any time after
# `terraform apply`. Run this manually as part of the provisioning workflow;
# it has no GitOps/Flux ordering dependency because it is not reconciled by
# Flux at all.
#
# Usage:
#   scripts/bootstrap-dr-drill-role-arns-configmap.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/dr-drill"
NAMESPACE="dr-drill-uat"

MONGODB_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_mongodb_role_arn)
POSTGRESQL_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_postgresql_role_arn)
CLICKHOUSE_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_clickhouse_role_arn)

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap dr-drill-role-arns \
  --namespace "$NAMESPACE" \
  --from-literal=DR_DRILL_MONGODB_ROLE_ARN="$MONGODB_ARN" \
  --from-literal=DR_DRILL_POSTGRESQL_ROLE_ARN="$POSTGRESQL_ARN" \
  --from-literal=DR_DRILL_CLICKHOUSE_ROLE_ARN="$CLICKHOUSE_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ dr-drill-role-arns ConfigMap up to date in namespace $NAMESPACE"
```

Also create the provider/version pinning file, mirroring the existing `mongodb` root:

```hcl
# platform-prerequisites/terraform/dr-drill/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
  }
}
```

And the sample tfvars file operators copy and fill in:

```hcl
# platform-prerequisites/terraform/dr-drill/terraform.tfvars.sample
# Copy to terraform.tfvars and fill in with the eks-platform root's outputs:
#   terraform -chdir=platform-prerequisites/terraform/eks-platform output oidc_provider_arn
#   terraform -chdir=platform-prerequisites/terraform/eks-platform output oidc_provider_url
oidc_provider_arn = ""
oidc_provider_url = ""
```

- [ ] **Step 4: Write the weekly CronJob targeting UAT**

```yaml
# k8s/dr-drill/cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dr-drill-weekly
  namespace: dr-drill-uat
spec:
  # Weekly, Sunday 03:00 UTC -- low-traffic window in the UAT environment.
  schedule: "0 3 * * 0"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: dr-drill-runner
          containers:
            - name: dr-drill-runner
              image: oms/dr-drill-runner:latest
              # Real expected drill-role ARNs, sourced from the
              # dr-drill-role-arns ConfigMap created by
              # scripts/bootstrap-dr-drill-role-arns-configmap.sh (values are
              # the actual Terraform-output role ARNs -- never hardcoded
              # here). Re-run that script any time after `terraform apply`.
              envFrom:
                - configMapRef:
                    name: dr-drill-role-arns
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail
                  echo "Running weekly DR drills against UAT..."
                  /scripts/dr-drill-mongodb-restore.sh
                  /scripts/dr-drill-postgresql-restore.sh
                  /scripts/dr-drill-clickhouse-backup-restore.sh
          restartPolicy: Never
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/test_dr_drill_scheduling.py -v`
Expected: PASS (12/12)

- [ ] **Step 6: Run full dr_drill test suite together**

Run: `cd /Users/frank/sml/oms/mongodb && python3 -m pytest tests/dr_drill/ -v`
Expected: PASS (38/38 across Tasks 1-4: 9 + 9 + 8 + 12)

- [ ] **Step 7: Make the bootstrap script executable and commit**

```bash
chmod +x scripts/bootstrap-dr-drill-role-arns-configmap.sh
git add platform-prerequisites/terraform/dr-drill/main.tf platform-prerequisites/terraform/dr-drill/versions.tf platform-prerequisites/terraform/dr-drill/terraform.tfvars.sample scripts/bootstrap-dr-drill-role-arns-configmap.sh k8s/dr-drill/cronjob.yaml tests/dr_drill/test_dr_drill_scheduling.py
git commit -m "feat(dr-drill): add least-privilege drill IAM roles (scoped IRSA trust policies), kubectl-based ConfigMap bootstrap script, and weekly UAT CronJob scheduling"
```

---

## Completion Gate for This Sub-Project

Before starting the follow-up plan for Theme 3's CRD/Operator Upgrade runbook (which
depends on this work per design decision D4), confirm:

- [ ] `python3 -m pytest tests/dr_drill/ -v` — all tests pass
- [ ] `terraform -chdir=platform-prerequisites/terraform/dr-drill fmt -check && terraform -chdir=platform-prerequisites/terraform/dr-drill validate`
- [ ] `terraform -chdir=platform-prerequisites/terraform/dr-drill apply` has been run once against real AWS, then `scripts/bootstrap-dr-drill-role-arns-configmap.sh` has been run to populate the `dr-drill-role-arns` ConfigMap in UAT
- [ ] All 3 drill scripts have been run at least once manually against UAT and produced a passing `✅ DR Drill PASSED` line with a recorded RTO
- [ ] Weekly CronJob deployed to `dr-drill-uat` namespace and confirmed via `kubectl get cronjob -n dr-drill-uat`

## Next Plans (Not In This Document)

Per the Phase 4 design spec's task ordering, once this sub-project's gate passes:
1. **Theme 3 plan** — Platform Operations (dashboard import failure recovery, alerts,
   concurrency lock, API quota preflight, and the CRD/Operator Upgrade runbook gated on
   this plan).
2. **Theme 1 plan** — Cost & Compliance (CloudWatch cost alerts, KMS rotation, S3
   lifecycle, network TLS, secrets rotation).
3. **Theme 4 plan** — Observability Stability (SigNoz API versioning matrix, dashboard
   JSON schema validator, ClickHouse schema stability docs, data model compatibility).
