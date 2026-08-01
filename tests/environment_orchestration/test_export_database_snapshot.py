"""Structural tests for scripts/export-database-snapshot.sh: argument
parsing, per-database command sequencing, and exit-code behavior, using
mocked kubectl (no live cluster)."""
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

_KUBECTL_STUB_TEMPLATE = "#!/usr/bin/env bash\n{body}\n"


class ExportDatabaseSnapshotFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = pathlib.Path(self.temporary.name) / "bin"
        self.command_log = pathlib.Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)
        (self.root / "scripts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            REPO_ROOT / "scripts" / "export-database-snapshot.sh",
            self.root / "scripts" / "export-database-snapshot.sh",
        )
        (self.root / "scripts" / "export-database-snapshot.sh").chmod(0o755)

    def tearDown(self):
        self.temporary.cleanup()

    def _write_kubectl_stub(self, body):
        path = self.mock_bin / "kubectl"
        path.write_text(_KUBECTL_STUB_TEMPLATE.format(body=body), encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_export(self, args, kubectl_body):
        self._write_kubectl_stub(kubectl_body)
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        return subprocess.run(
            ["bash", "scripts/export-database-snapshot.sh", *args],
            cwd=self.root, env=environment, text=True, capture_output=True,
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text().splitlines() if line]


class UnknownScopeTests(ExportDatabaseSnapshotFixture):
    def test_unknown_scope_fails_with_usage(self):
        result = self.run_export(["unknown"], 'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"; exit 0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout + result.stderr)


class MongodbExportTests(ExportDatabaseSnapshotFixture):
    def test_mongodb_scope_execs_pbm_backup_with_wait(self):
        # Fake kubectl: log every invocation, return a fake pod name for `get pods`,
        # exit 0 for `exec ... pbm backup ...` to simulate successful backup.
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ "$1" == "get" && "$2" == "pods" ]] || [[ "$3" == "get" && "$4" == "pods" ]]; then\n'
            '  echo -n "psmdb-rs0-0"\n'
            '  exit 0\n'
            'fi\n'
            'if [[ "$1" == "exec" || "$3" == "exec" ]]; then exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["mongodb"], body)
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertIn("exec", logged)
        self.assertIn("pbm backup", logged)
        self.assertIn("--wait", logged)
        # Critical: verify container selection and explicit MongoDB URI
        # (C1 fix regression guard — wrong container/missing URI both silent-fail).
        self.assertIn("-c pbm-agent", logged, "Must exec into pbm-agent container, not default mongod")
        self.assertIn("--mongodb-uri=", logged, "Must pass explicit MongoDB URI (pbm-agent has no PBM_MONGODB_URI env)")


class PostgresqlExportTests(ExportDatabaseSnapshotFixture):
    def test_postgresql_scope_applies_backup_cr_and_polls_phase(self):
        # Fake kubectl: `apply -f -` (creating the Backup CR) logs and
        # succeeds; `get backup ... -o jsonpath={.status.phase}` reports
        # "completed" immediately so the poll loop exits right away.
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ ("$1" == "get" && "$2" == "backup") || ("$3" == "get" && "$4" == "backup") ]]; then echo -n completed; exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["postgresql"], body)
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertIn("apply", logged)
        self.assertIn("kind: Backup", (self.root / "scripts" / "export-database-snapshot.sh").read_text())
        self.assertIn("jsonpath", logged)

    def test_postgresql_scope_fails_when_backup_phase_is_failed(self):
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ ("$1" == "get" && "$2" == "backup") || ("$3" == "get" && "$4" == "backup") ]]; then echo -n failed; exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["postgresql"], body)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
