import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class RepositoryFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # Resolve symlinks (e.g. macOS /var -> /private/var) so self.root
        # matches the real, canonical path any `cd ... && pwd` computation
        # inside a bash script under test will naturally produce.
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = Path(self.temporary.name) / "bin"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.mock_bin.mkdir(parents=True)
        for command in ("aws", "kubectl", "terraform", "kustomize"):
            path = self.mock_bin / command
            path.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '{command} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
                "exit 97\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def copy(self, *relative_paths):
        for relative in relative_paths:
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def run_bash(self, script, extra_env=None):
        environment = os.environ.copy()
        environment.update({
            "PATH": f"{self.mock_bin}:{environment['PATH']}",
            "MOCK_COMMAND_LOG": str(self.command_log),
        })
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            ["bash", "-c", script], cwd=self.root, env=environment,
            text=True, capture_output=True,
        )

    def tearDown(self):
        self.temporary.cleanup()
