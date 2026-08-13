"""Tests for `scripts/lib/enumerate-destroy-resources.sh`'s three-value
return-status contract, which the single-pass destroy gate depends on to
fail closed.

  0  enumeration succeeded and printed the real list
  1  enumeration FAILED for a scope that HAS an enumerator -> the caller
     must abort the destroy. There is deliberately no fallback list: a
     plausible-looking fiction shown while a human decides whether to
     destroy production is exactly the failure #163 removed.
  2  no enumerator is mapped for this scope -> an honest absence, the
     caller says so and continues to the typed-yes gate.

Conflating 1 and 2 is the specific bug this file guards against: before the
split, an unreadable Terraform state and an unmapped scope both returned 1,
so the only safe reading of "1" was "carry on regardless".
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .helpers import REPO_ROOT

LIBRARY = "scripts/lib/enumerate-destroy-resources.sh"


class EnumerationReturnStatusContractTests(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name).resolve()
        destination = self.root / LIBRARY
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO_ROOT / LIBRARY, destination)

    def tearDown(self):
        self._temporary.cleanup()

    def enumerate(self, scope, environment, extra_path=""):
        script = (
            f"source {LIBRARY}\n"
            f"enumerate_destroy_resources_for_scope {scope} {environment} >/dev/null 2>&1\n"
            "printf 'STATUS=%s\\n' \"$?\"\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": extra_path + "/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )
        for line in result.stdout.splitlines():
            if line.startswith("STATUS="):
                return int(line.split("=", 1)[1])
        self.fail(f"no status emitted: {result.stdout} {result.stderr}")

    def test_an_unmapped_scope_returns_2_not_1(self):
        self.assertEqual(self.enumerate("signoz", "uat"), 2)

    def test_a_scope_with_no_terraform_root_present_returns_2(self):
        # eks-platform HAS an enumerator, but its Terraform root does not
        # exist in this bare fixture, so there is nothing to read: that is
        # "no enumerator applicable here" (2), not "enumeration failed".
        self.assertEqual(self.enumerate("eks-platform", "uat"), 2)

    def test_a_kustomize_scope_with_no_overlay_directory_returns_2(self):
        self.assertEqual(self.enumerate("platform-controllers", "uat"), 2)

    def test_an_unmapped_environment_for_a_kustomize_scope_returns_2(self):
        self.assertEqual(self.enumerate("platform-controllers", "sit"), 2)

    def test_a_mapped_scope_whose_state_cannot_be_read_returns_1(self):
        """Terraform root present but `terraform` unusable -> hard failure
        (1), which the orchestrator turns into an aborted destroy."""
        tf_dir = self.root / "platform-prerequisites" / "terraform" / "eks-platform"
        tf_dir.mkdir(parents=True)
        (tf_dir / "main.tf").write_text("", encoding="utf-8")

        # No `terraform` on PATH at all, so `terraform show -json` fails.
        self.assertEqual(self.enumerate("eks-platform", "uat"), 1)

    def test_kubectl_failure_for_a_mapped_overlay_returns_3_not_1(self):
        """kubectl-unusable must be status 3 (state unavailable), never 1.

        kubectl fails precisely when the cluster is already gone -- the most
        common partially-destroyed state, and one a teardown produces itself
        by deleting the cluster before the Terraform scopes that referenced
        it. Returning 1 here aborts the whole destroy, making the remaining
        scopes undestroyable: the #159 deadlock rebuilt on a different
        observation.
        """
        overlay = self.root / "gitops" / "platform-controllers" / "overlays" / "uat"
        overlay.mkdir(parents=True)
        (overlay / "kustomization.yaml").write_text("resources: []\n", encoding="utf-8")

        failing_bin = self.root / "failing-bin"
        failing_bin.mkdir()
        kubectl = failing_bin / "kubectl"
        kubectl.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="ascii")
        kubectl.chmod(0o755)

        self.assertEqual(
            self.enumerate("platform-controllers", "uat", extra_path=f"{failing_bin}:"), 3
        )


if __name__ == "__main__":
    unittest.main()
