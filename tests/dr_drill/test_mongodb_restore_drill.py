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
