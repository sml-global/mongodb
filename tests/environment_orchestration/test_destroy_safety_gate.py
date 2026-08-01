"""Structural tests for the new confirmation gate and --export-first flag
in scripts/legacy/dev/destroy.sh. Mocks kubectl/terraform/aws; no live
execution. Confirmation input is supplied via stdin."""
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

_LOGGING_STUB_TEMPLATE = (
    "#!/usr/bin/env bash\n"
    "printf '{name} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
    "exit 0\n"
)


class DestroySafetyGateFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = pathlib.Path(self.temporary.name) / "bin"
        self.command_log = pathlib.Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)
        for command in ("aws", "kubectl", "terraform"):
            self._write_executable(
                self.mock_bin / command, _LOGGING_STUB_TEMPLATE.format(name=command),
            )
        (self.root / "scripts").mkdir(parents=True, exist_ok=True)
        for name in ("legacy/dev/destroy.sh", "export-database-snapshot.sh",
                     "bootstrap-terraform-s3-backend.sh"):
            source = REPO_ROOT / "scripts" / name
            destination = self.root / "scripts" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.exists():
                shutil.copy2(source, destination)
                destination.chmod(0o755)
        # Stub the backend bootstrap script (Terraform-scope helper, not
        # under test here) with a logging no-op.
        (self.root / "scripts" / "bootstrap-terraform-s3-backend.sh").write_text(
            _LOGGING_STUB_TEMPLATE.format(name="bootstrap-terraform-s3-backend.sh"),
            encoding="utf-8",
        )
        (self.root / "scripts" / "bootstrap-terraform-s3-backend.sh").chmod(0o755)
        for tf_subdir in ("mongodb", "postgresql"):
            tfvars = self.root / "platform-prerequisites" / "terraform" / tf_subdir / "terraform.tfvars"
            tfvars.parent.mkdir(parents=True, exist_ok=True)
            tfvars.write_text("", encoding="utf-8")

    def tearDown(self):
        self.temporary.cleanup()

    def _write_executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_destroy(self, args, stdin_text=None):
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        return subprocess.run(
            ["bash", "scripts/legacy/dev/destroy.sh", *args],
            cwd=self.root, env=environment, text=True, capture_output=True,
            input=stdin_text,
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text().splitlines() if line]


class ConfirmationGateTests(DestroySafetyGateFixture):
    def test_wrong_confirmation_aborts_with_no_destructive_calls(self):
        result = self.run_destroy(["mongodb"], stdin_text="not-destroy\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_empty_confirmation_aborts_with_no_destructive_calls(self):
        result = self.run_destroy(["mongodb"], stdin_text="\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_correct_confirmation_proceeds(self):
        result = self.run_destroy(["mongodb"], stdin_text="DESTROY\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(len(self.command_log_lines()) > 0)

    def test_auto_approve_skips_prompt_entirely(self):
        result = self.run_destroy(["mongodb", "--auto-approve"], stdin_text="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(len(self.command_log_lines()) > 0)


class ExportFirstFlagTests(DestroySafetyGateFixture):
    def test_export_first_calls_export_script_before_any_destructive_command(self):
        result = self.run_destroy(
            ["mongodb", "--auto-approve", "--export-first"], stdin_text="",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = self.command_log_lines()
        # First logged kubectl/terraform call must come from the export
        # tool's own kubectl invocations (it runs before destroy_mongodb_k8s).
        self.assertTrue(any("get pods" in line or "exec" in line for line in logged[:2]))

    def test_without_export_first_flag_export_script_never_invoked(self):
        result = self.run_destroy(["mongodb", "--auto-approve"], stdin_text="")
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertNotIn("pbm backup", logged)


if __name__ == "__main__":
    unittest.main()
