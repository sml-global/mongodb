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
        # Two distinct "kubectl get pod" targets: the LIVE signoz pod (backup
        # source only) and the THROWAWAY restore-target pod (in the drill
        # namespace) -- distinguished by args, since the script must never
        # reuse the live pod for restore. See test_restore_never_targets_the_live_signoz_namespace.
        self._mock("kubectl", (
            'if [ "$1" = "get" ]; then\n'
            '  if [[ "$*" == *"-n signoz "* ]] || [[ "$*" == *"-n signoz" ]]; then echo "signoz-clickhouse-0"; fi\n'
            '  if [[ "$*" == *"clickhouse-restore-target"* ]]; then echo "clickhouse-restore-target-abc"; fi\n'
            '  exit 0\n'
            'fi\n'
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

    def test_backup_create_and_upload_run_against_the_live_signoz_pod(self):
        # Safe: create/upload only freeze+copy data OUT, never mutate the
        # source -- this is the one part of the drill allowed to touch the
        # live namespace.
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("-n signoz", log)
        create_lines = [l for l in log.splitlines() if "clickhouse-backup create" in l]
        upload_lines = [l for l in log.splitlines() if "clickhouse-backup upload" in l]
        self.assertTrue(create_lines and upload_lines)
        for line in create_lines + upload_lines:
            self.assertIn("-n signoz", line)

    def test_restore_never_targets_the_live_signoz_namespace(self):
        # Regression test for a critical bug caught in whole-branch review:
        # an earlier version ran `clickhouse-backup restore --rm` directly
        # against the live signoz pod, which would have dropped and
        # overwritten production tables. Restore must run only against the
        # throwaway restore-target pod in an isolated dr-drill-* namespace.
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        restore_lines = [
            l for l in log.splitlines()
            if "clickhouse-backup restore" in l or "clickhouse-backup download" in l
        ]
        self.assertTrue(restore_lines, "script must actually run a restore")
        for line in restore_lines:
            self.assertNotIn("-n signoz", line,
                              "restore/download must never target the live "
                              "signoz namespace")
            self.assertIn("dr-drill-clickhouse", line,
                          "restore/download must target an isolated "
                          "dr-drill-clickhouse-* namespace")
        self.assertNotIn("--rm", log,
                          "must never use --rm against a pod that could be live")

    def test_deploys_and_tears_down_throwaway_restore_target(self):
        self._install_happy_path_mocks()
        self._run()
        log = self._log()
        self.assertIn("kubectl create namespace", log)
        self.assertIn("clickhouse-restore-target.yaml", log)
        self.assertIn("kubectl wait", log)
        self.assertIn("kubectl delete namespace", log)

    def test_tears_down_drill_namespace_even_on_failure(self):
        self._mock_kubectl(exec_row_count="")
        self._mock("aws", f'echo "{DRILL_ROLE_ARN}"')
        self._run()
        self.assertIn("kubectl delete namespace", self._log(),
                      "cleanup trap must run kubectl delete namespace even "
                      "when the drill fails partway through")


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

    def test_backup_sidecar_container_is_present(self):
        container_names = [c["name"] for c in self.clickhouse_values["extraContainers"]]
        self.assertIn("clickhouse-backup", container_names)

    def test_backup_targets_dedicated_bucket_not_mongodb_pbm_bucket(self):
        backup_container = next(
            c for c in self.clickhouse_values["extraContainers"]
            if c["name"] == "clickhouse-backup"
        )
        env_by_name = {e["name"]: e.get("value") for e in backup_container.get("env", [])}
        bucket = env_by_name.get("REMOTE_STORAGE_S3_BUCKET")
        self.assertEqual(bucket, "oms-signoz-clickhouse-backups")
        self.assertNotEqual(bucket, "oms-pbm-backups")


class ClickhouseRestoreTargetManifestTests(unittest.TestCase):
    """Structural (parsed-field) assertions on the throwaway restore-target
    Deployment, matching the convention in tests/signoz/test_gitops_manifests.py."""

    @classmethod
    def setUpClass(cls):
        manifest_path = REPO_ROOT / "k8s" / "dr-drill" / "clickhouse-restore-target.yaml"
        cls.deployment = yaml.safe_load(manifest_path.read_text())

    def test_pod_template_uses_the_dedicated_service_account(self):
        pod_spec = self.deployment["spec"]["template"]["spec"]
        self.assertEqual(pod_spec["serviceAccountName"], "dr-drill-clickhouse-runner")


if __name__ == "__main__":
    unittest.main()
