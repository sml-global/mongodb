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

    def test_uses_the_fixed_reusable_namespace_by_default(self):
        # EKS Pod Identity associations require an exact static
        # namespace+ServiceAccount match (no wildcards) -- a dynamically
        # timestamped namespace could never be granted AWS credentials via
        # Terraform ahead of time. Regression guard against reintroducing
        # dr-drill-postgresql-$(date +%s). The namespace itself is now
        # provisioned once by bootstrap-dr-drill-role-arns-configmap.sh, not
        # by this script (see D18/D19) -- so we assert on the namespace the
        # script applies the Cluster manifest into, not a `create namespace`
        # call (which no longer happens here).
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("apply -n dr-drill-postgresql-restore-target -f -", log)
        for line in log.splitlines():
            self.assertNotRegex(line, r"dr-drill-postgresql-\d{9,}",
                                 "must not use a timestamped namespace name")

    def test_deletes_the_cluster_at_start_before_recreating_it(self):
        # Namespace + RBAC are persistent (bootstrapped once); only the
        # throwaway CNPG Cluster itself is cycled per run.
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        delete_idx = log.index("delete cluster dr-drill-restore-target")
        apply_idx = log.index("apply -n dr-drill-postgresql-restore-target -f -")
        self.assertLess(delete_idx, apply_idx,
                         "cluster must be deleted (start-of-run safety net) "
                         "before it is recreated")
        self.assertIn("--wait=true", log)

    def test_waits_for_cnpg_pvcs_to_be_gone_before_recreating_the_cluster(self):
        # CNPG PVCs carry a real ownerReference back to their Cluster, so
        # deleting the Cluster triggers standard Kubernetes cascading GC --
        # but GC is asynchronous, so the script must poll for the PVCs to
        # actually be gone before recreating the Cluster, or the drill could
        # silently reuse stale local data instead of proving a real restore
        # from the S3 WAL archive.
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("get pvc -n dr-drill-postgresql-restore-target -l cnpg.io/cluster=dr-drill-restore-target", log)

    def test_falls_back_to_explicit_pvc_delete_when_gc_never_completes(self):
        # Exercises the untested branch: if `kubectl get pvc` never reports
        # empty (GC stuck/slow), the script must fall back to an explicit
        # `kubectl delete pvc` by the same label selector rather than
        # silently proceeding to recreate the Cluster onto a still-attached
        # stale volume. Mocks `sleep` as a no-op so the real 60x2s poll loop
        # doesn't make this test slow -- we're only proving the fallback
        # path fires with the right selector, not timing the real wait.
        self._mock("sleep", "exit 0")
        self._mock("kubectl", (
            'if [ "$1" = "apply" ]; then\n'
            f'  cat > "{self.manifest_path}"\n'
            'fi\n'
            'if [ "$1" = "wait" ]; then exit 0; fi\n'
            'if [ "$1" = "exec" ]; then echo "500"; exit 0; fi\n'
            'if [ "$1" = "get" ] && [[ "$*" == *"pvc"* ]]; then\n'
            '  echo "persistentvolumeclaim/dr-drill-restore-target-1"\n'
            '  exit 0\n'
            'fi\n'
            'exit 0\n'
        ))
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self._log()
        self.assertIn(
            "delete pvc -n dr-drill-postgresql-restore-target -l cnpg.io/cluster=dr-drill-restore-target",
            log,
            "must fall back to an explicit PVC delete when GC never reports the PVCs gone",
        )

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

    def test_tears_down_restore_target_cluster_even_on_failure(self):
        self._mock_kubectl(wait_exit=1)
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        self._run()
        self.assertIn("kubectl delete cluster", self._log())

    def test_records_a_nonnegative_rto(self):
        self._install_happy_path_mocks()
        result = self._run()
        self.assertRegex(result.stdout, r"RTO=\d+s")

    def test_exec_targets_the_correct_pod_ordinal_one(self):
        # Regression test: CNPG does NOT use StatefulSet resources -- it
        # manages PVCs directly and numbers instance pods starting at 1, not
        # 0 (verified against the official CNPG FAQ, "Why isn't CloudNativePG
        # using StatefulSets?", and its own worked example of a single-
        # instance cluster named "pg-italy" whose only pod is "pg-italy-1").
        # With `instances: 1` (this drill's throwaway target), the only pod
        # is "dr-drill-restore-target-1". The mock does not special-case the
        # pod name, so this only passes if the script actually execs into
        # the pod name the manifest implies.
        self._install_happy_path_mocks()
        self._run()
        exec_lines = [l for l in self._log().splitlines() if "kubectl exec" in l]
        self.assertTrue(exec_lines, "script must kubectl exec into the restore-target pod")
        for line in exec_lines:
            self.assertIn("dr-drill-restore-target-1", line,
                          "must exec into pod ordinal 1 (CNPG numbers from 1, "
                          "not 0 -- it does not use StatefulSets)")
            self.assertIn("psql", line)


if __name__ == "__main__":
    unittest.main()
