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

    def test_applied_manifest_attaches_the_dr_drill_service_account(self):
        # So s3Credentials.inheritFromIAMRole below has an identity to
        # inherit from -- Cluster.spec.serviceAccountName (verified against
        # cloudnative-pg.io/docs/devel/cloudnative-pg.v1), not fabricated.
        self._install_happy_path_mocks()
        self._run()
        manifest = self._applied_manifest()
        self.assertEqual(manifest["spec"]["serviceAccountName"],
                          "dr-drill-postgresql-runner")

    def test_creates_a_matching_service_account_in_the_drill_namespace(self):
        # ServiceAccounts are namespace-scoped; the CNPG-managed pod's own
        # fixed namespace needs its own SA of this name.
        self._install_happy_path_mocks()
        self._run()
        self.assertIn("create serviceaccount dr-drill-postgresql-runner", self._log())

    def test_uses_the_fixed_reusable_namespace_by_default(self):
        # EKS Pod Identity associations require an exact static
        # namespace+ServiceAccount match (no wildcards) -- a dynamically
        # timestamped namespace could never be granted AWS credentials via
        # Terraform ahead of time. Regression guard against reintroducing
        # dr-drill-postgresql-$(date +%s).
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("create namespace dr-drill-postgresql-restore-target", log)
        for line in log.splitlines():
            if "namespace" in line:
                self.assertNotRegex(line, r"dr-drill-postgresql-\d{9,}",
                                     "must not use a timestamped namespace name")

    def test_deletes_the_namespace_at_start_before_recreating_it(self):
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        delete_idx = log.index("delete namespace dr-drill-postgresql-restore-target")
        create_idx = log.index("create namespace dr-drill-postgresql-restore-target")
        self.assertLess(delete_idx, create_idx,
                         "namespace must be deleted (start-of-run safety net) "
                         "before it is recreated")
        self.assertIn("--wait=true", log)

    def test_self_applies_a_namespace_scoped_rolebinding_for_the_workload_operator_role(self):
        # The fixed namespace is deleted+recreated every run, wiping any
        # RBAC objects that lived inside the previous run's copy of it.
        applied_all_path = self.bin_dir / "applied-all.yaml"
        self._mock("kubectl", (
            'if [ "$1" = "apply" ] && [[ "$*" == *"-f -"* ]]; then\n'
            f'  cat >> "{applied_all_path}"\n'
            f'  echo "---" >> "{applied_all_path}"\n'
            '  exit 0\n'
            'fi\n'
            'if [ "$1" = "wait" ]; then exit 0; fi\n'
            'if [ "$1" = "exec" ]; then echo "500"; exit 0; fi\n'
            'exit 0\n'
        ))
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        docs = [d for d in yaml.safe_load_all(applied_all_path.read_text()) if d]
        role_bindings = [d for d in docs if d.get("kind") == "RoleBinding"]
        self.assertEqual(len(role_bindings), 1)
        manifest = role_bindings[0]
        self.assertEqual(manifest["metadata"]["namespace"], "dr-drill-postgresql-restore-target")
        self.assertEqual(manifest["roleRef"]["kind"], "ClusterRole")
        self.assertEqual(manifest["roleRef"]["name"], "dr-drill-workload-operator")
        self.assertEqual(manifest["subjects"][0]["name"], "dr-drill-postgresql-runner")
        self.assertEqual(manifest["subjects"][0]["namespace"], "dr-drill-uat")

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
