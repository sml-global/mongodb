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


if __name__ == "__main__":
    unittest.main()
