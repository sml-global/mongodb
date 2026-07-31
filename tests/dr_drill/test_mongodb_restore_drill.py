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

import yaml

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
            '  if [[ "$*" == *"pbm config"* ]]; then exit 0; fi\n'
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

    def test_pbm_commands_target_the_pbm_agent_container(self):
        # Regression test: an earlier version omitted `-c pbm-agent`, so
        # kubectl exec silently defaulted to the first container (mongodb),
        # where the pbm binary does not exist. Caught in whole-branch review.
        self._install_happy_path_mocks()
        self._run()
        pbm_exec_lines = [
            l for l in self._log().splitlines()
            if l.startswith("kubectl ") and "exec" in l and " pbm " in f" {l} "
        ]
        self.assertTrue(pbm_exec_lines, "script must exec pbm commands")
        for line in pbm_exec_lines:
            self.assertIn("-c pbm-agent", line,
                          "pbm commands must target the pbm-agent container")

    def test_mongosh_targets_the_mongodb_container(self):
        self._install_happy_path_mocks()
        self._run()
        mongosh_exec_lines = [
            l for l in self._log().splitlines()
            if l.startswith("kubectl ") and "exec" in l and "mongosh" in l
        ]
        self.assertTrue(mongosh_exec_lines, "script must exec mongosh")
        for line in mongosh_exec_lines:
            self.assertIn("-c mongodb", line,
                          "mongosh must target the mongodb container")

    def test_configures_pbm_storage_backend_before_checking_status(self):
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        config_idx = log.index("pbm config")
        status_idx = log.index("pbm status")
        self.assertLess(config_idx, status_idx,
                        "pbm config must run before pbm status/list/restore")
        self.assertIn("oms-pbm-backups", log)

    def test_creates_a_matching_service_account_in_the_drill_namespace(self):
        # ServiceAccounts are namespace-scoped; the restore-target pod's own
        # fixed namespace needs its own SA of this name to match
        # k8s/dr-drill/mongodb-restore-target.yaml's serviceAccountName.
        self._install_happy_path_mocks()
        self._run()
        self.assertIn("create serviceaccount dr-drill-mongodb-runner", self._log())

    def test_uses_the_fixed_reusable_namespace_by_default(self):
        # EKS Pod Identity associations require an exact static
        # namespace+ServiceAccount match (no wildcards) -- a dynamically
        # timestamped namespace could never be granted AWS credentials via
        # Terraform ahead of time. Regression guard against reintroducing
        # dr-drill-mongodb-$(date +%s).
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("create namespace dr-drill-mongodb-restore-target", log)
        for line in log.splitlines():
            if "namespace" in line:
                self.assertNotRegex(line, r"dr-drill-mongodb-\d{9,}",
                                     "must not use a timestamped namespace name")

    def test_deletes_the_namespace_at_start_before_recreating_it(self):
        # Safety net: a previous run's cleanup may have failed/been
        # interrupted, potentially leaving the fixed namespace stuck
        # mid-teardown. The script must block on a clean delete before
        # recreating it, not just in the exit trap.
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        delete_idx = log.index("delete namespace dr-drill-mongodb-restore-target")
        create_idx = log.index("create namespace dr-drill-mongodb-restore-target")
        self.assertLess(delete_idx, create_idx,
                         "namespace must be deleted (start-of-run safety net) "
                         "before it is recreated")
        self.assertIn("--wait=true", log)

    def test_self_applies_a_namespace_scoped_rolebinding_for_the_workload_operator_role(self):
        # The fixed namespace is deleted+recreated every run, wiping any
        # RBAC objects that lived inside the previous run's copy of it. The
        # script must re-grant its own orchestrator ServiceAccount the
        # namespace-scoped workload permissions by binding the persistent
        # dr-drill-workload-operator ClusterRole (k8s/dr-drill/rbac.yaml) to
        # just this namespace every run.
        applied_manifest_path = self.bin_dir / "applied-rolebinding.yaml"
        self._mock("kubectl", (
            'if [ "$1" = "get" ]; then echo "mongodb-restore-target-abc"; exit 0; fi\n'
            'if [ "$1" = "apply" ] && [[ "$*" == *"-f -"* ]]; then cat > "' + str(applied_manifest_path) + '"; exit 0; fi\n'
            'if [ "$1" = "apply" ]; then exit 0; fi\n'
            'if [ "$1" = "exec" ]; then\n'
            '  if [[ "$*" == *"pbm config"* ]]; then exit 0; fi\n'
            '  if [[ "$*" == *"pbm status"* ]]; then exit 0; fi\n'
            '  if [[ "$*" == *"pbm list"* ]]; then echo "2026-07-28T12:00:00Z"; exit 0; fi\n'
            '  if [[ "$*" == *"pbm restore"* ]]; then exit 0; fi\n'
            '  if [[ "$*" == *"mongosh"* ]]; then echo "42"; exit 0; fi\n'
            '  exit 0\n'
            'fi\n'
            'exit 0\n'
        ))
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = yaml.safe_load(applied_manifest_path.read_text())
        self.assertEqual(manifest["kind"], "RoleBinding")
        self.assertEqual(manifest["metadata"]["namespace"], "dr-drill-mongodb-restore-target")
        self.assertEqual(manifest["roleRef"]["kind"], "ClusterRole")
        self.assertEqual(manifest["roleRef"]["name"], "dr-drill-workload-operator")
        subjects = manifest["subjects"]
        self.assertEqual(len(subjects), 1)
        self.assertEqual(subjects[0]["name"], "dr-drill-mongodb-runner")
        self.assertEqual(subjects[0]["namespace"], "dr-drill-uat")


class MongoDbRestoreTargetManifestTests(unittest.TestCase):
    """Structural (parsed-field) assertions on the throwaway restore-target
    Deployment, matching the convention in tests/signoz/test_gitops_manifests.py."""

    @classmethod
    def setUpClass(cls):
        manifest_path = REPO_ROOT / "k8s" / "dr-drill" / "mongodb-restore-target.yaml"
        cls.deployment = yaml.safe_load(manifest_path.read_text())

    def test_pod_template_uses_the_dedicated_service_account(self):
        pod_spec = self.deployment["spec"]["template"]["spec"]
        self.assertEqual(pod_spec["serviceAccountName"], "dr-drill-mongodb-runner")


if __name__ == "__main__":
    unittest.main()
