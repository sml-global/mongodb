"""Tests for the automatic-but-conditional protection lifting in
`scripts/lib/packages/10-foundation-access/internal/access-scopes.sh`.

Since the destroy gate became a single interactive pass, there are no
`--confirm-remove-protected` / `--confirm-disable-deletion-protection`
flags: once a human has typed `yes` against a real enumerated resource
list, lifting Terraform's `lifecycle.prevent_destroy` and the live EKS
`deletionProtection` is automatic.

Automatic must not become unconditional. Two failure modes each recreate a
#159-class deadlock -- a partially-destroyed stack that can no longer be
finished -- and each has tests here:

  * hardcoding a protected address (e.g. `module.efs[0]...`) as mandatory,
    which fails the moment that resource has already been destroyed. The
    address list is therefore derived from live `terraform state list`
    intersected with the resource blocks that actually still declare
    `prevent_destroy = true`.

  * unconditionally pushing `deletion_protection=false`, which fails when
    the cluster is already gone or the flag is already false. Both are
    treated as success (nothing to do), while a lookup that genuinely
    FAILED is treated as fatal -- never silently read as "still enabled".
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .helpers import REPO_ROOT

LIBRARY = "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh"

KMS_MODULE = """
resource "aws_kms_key" "cluster" {
  description = "cluster key"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "backup" {
  description = "backup key"
  lifecycle {
    prevent_destroy = true
  }
}
"""

EFS_MODULE = """
resource "aws_efs_file_system" "this" {
  encrypted = true
  lifecycle {
    prevent_destroy = true
  }
}
"""

UNPROTECTED_KMS_MODULE = """
resource "aws_kms_key" "cluster" {
  description = "cluster key"
  lifecycle {
    prevent_destroy = false
  }
}
"""


class _AccessScopesFixture(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name).resolve()
        destination = self.root / LIBRARY
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO_ROOT / LIBRARY, destination)

        self.mock_bin = self.root / "bin"
        self.mock_bin.mkdir()

        self.modules = self.root / "platform-prerequisites" / "terraform" / "modules"
        (self.modules / "kms").mkdir(parents=True)
        (self.modules / "efs").mkdir(parents=True)
        (self.modules / "kms" / "main.tf").write_text(KMS_MODULE, encoding="utf-8")
        (self.modules / "efs" / "main.tf").write_text(EFS_MODULE, encoding="utf-8")

    def tearDown(self):
        self._temporary.cleanup()

    def write_terraform_state_list(self, addresses):
        script = "#!/usr/bin/env bash\n"
        script += 'if [ "$2" = "state" ] || [ "$3" = "state" ]; then\n'
        for address in addresses:
            script += f"  printf '%s\\n' '{address}'\n"
        script += "  exit 0\nfi\nexit 1\n"
        terraform = self.mock_bin / "terraform"
        terraform.write_text(script, encoding="ascii")
        terraform.chmod(0o755)

    def present_protected_addresses(self):
        script = (
            f"_ACCESS_SCOPES_ROOT_DIR={self.root}\n"
            f"source {LIBRARY} 2>/dev/null\n"
            f"_ACCESS_SCOPES_ROOT_DIR={self.root}\n"
            "_eks_platform_present_protected_addresses /tf-dir\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": f"{self.mock_bin}:/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )
        return [line for line in result.stdout.splitlines() if line.strip()]


class PresentProtectedAddressDerivationTests(_AccessScopesFixture):
    def test_only_addresses_present_in_state_are_returned(self):
        self.write_terraform_state_list(
            ["module.kms.aws_kms_key.cluster", "module.eks.aws_eks_cluster.this"]
        )

        self.assertEqual(
            self.present_protected_addresses(), ["module.kms.aws_kms_key.cluster"]
        )

    def test_an_already_destroyed_efs_simply_does_not_appear(self):
        """The #159 shape: EFS is gone from state. A hardcoded
        `module.efs[0]...` entry would make the destroy mandatory-fail
        here; deriving from state must yield the KMS keys alone."""
        self.write_terraform_state_list(
            ["module.kms.aws_kms_key.cluster", "module.kms.aws_kms_key.backup"]
        )

        addresses = self.present_protected_addresses()

        self.assertEqual(
            addresses,
            ["module.kms.aws_kms_key.cluster", "module.kms.aws_kms_key.backup"],
        )
        self.assertNotIn("module.efs[0].aws_efs_file_system.this", addresses)

    def test_an_indexed_efs_module_address_is_parsed_and_returned_when_present(self):
        self.write_terraform_state_list(["module.efs[0].aws_efs_file_system.this"])

        self.assertEqual(
            self.present_protected_addresses(),
            ["module.efs[0].aws_efs_file_system.this"],
        )

    def test_a_resource_whose_block_no_longer_declares_prevent_destroy_is_excluded(self):
        (self.modules / "kms" / "main.tf").write_text(
            UNPROTECTED_KMS_MODULE, encoding="utf-8"
        )
        self.write_terraform_state_list(["module.kms.aws_kms_key.cluster"])

        self.assertEqual(self.present_protected_addresses(), [])

    def test_an_empty_state_yields_no_addresses_and_does_not_fail(self):
        self.write_terraform_state_list([])

        self.assertEqual(self.present_protected_addresses(), [])

    def test_an_unreadable_state_yields_no_addresses_rather_than_a_guessed_list(self):
        # No terraform on PATH at all: `terraform state list` fails. The
        # helper returns nothing, and Terraform itself will then refuse any
        # genuinely protected resource by name -- rather than this code
        # patching source files it has no evidence it needs to patch.
        self.assertEqual(self.present_protected_addresses(), [])

    def test_a_resource_in_an_unknown_module_is_skipped_not_guessed_at(self):
        self.write_terraform_state_list(["module.unknown.aws_thing.this"])

        self.assertEqual(self.present_protected_addresses(), [])

    def test_two_protected_resources_sharing_one_module_file_are_answered_per_resource(self):
        self.write_terraform_state_list(
            ["module.kms.aws_kms_key.cluster", "module.kms.aws_kms_key.backup"]
        )

        self.assertEqual(len(self.present_protected_addresses()), 2)


class BlockScopedPreventDestroyDetectionTests(_AccessScopesFixture):
    def declares(self, resource_type, resource_name, module="kms"):
        script = (
            f"source {LIBRARY} 2>/dev/null\n"
            "_eks_platform_resource_block_declares_prevent_destroy "
            f"{self.modules}/{module}/main.tf {resource_type} {resource_name}\n"
            "printf 'STATUS=%s\\n' \"$?\"\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )
        for line in result.stdout.splitlines():
            if line.startswith("STATUS="):
                return line.split("=", 1)[1] == "0"
        self.fail(result.stdout + result.stderr)

    def test_a_protected_resource_is_detected(self):
        self.assertTrue(self.declares("aws_kms_key", "cluster"))

    def test_detection_is_scoped_to_the_named_resource_block(self):
        """modules/kms/main.tf holds two resources. Flipping one must not
        make the other read as protected (or unprotected)."""
        mixed = KMS_MODULE.replace(
            'resource "aws_kms_key" "backup" {\n  description = "backup key"\n  lifecycle {\n    prevent_destroy = true',
            'resource "aws_kms_key" "backup" {\n  description = "backup key"\n  lifecycle {\n    prevent_destroy = false',
        )
        (self.modules / "kms" / "main.tf").write_text(mixed, encoding="utf-8")

        self.assertTrue(self.declares("aws_kms_key", "cluster"))
        self.assertFalse(self.declares("aws_kms_key", "backup"))

    def test_an_absent_resource_is_not_reported_as_protected(self):
        self.assertFalse(self.declares("aws_kms_key", "nonexistent"))


class DestroyRefusesWithoutTheTypedYesSignalTests(_AccessScopesFixture):
    def test_destroy_eks_platform_scope_refuses_when_the_gate_signal_is_absent(self):
        """`UNIFIED_DESTROY_CONFIRMED=yes` is exported only by the
        orchestrator, only after a human typed yes. Without it, this
        function must not destroy and must not lift any protection --
        so a direct call (a stray script, a half-remembered invocation)
        cannot reach the automatic lifts."""
        var_file = self.root / "platform-prerequisites" / "terraform" / "environments" / "uat" / "eks-platform.tfvars"
        var_file.parent.mkdir(parents=True, exist_ok=True)
        var_file.write_text("deletion_protection = true\n", encoding="utf-8")

        script = (
            f"_ACCESS_SCOPES_ROOT_DIR={self.root}\n"
            f"source {LIBRARY} 2>/dev/null\n"
            f"_ACCESS_SCOPES_ROOT_DIR={self.root}\n"
            "ENVIRONMENT=uat\n"
            "provision_backend_scope() { printf 'BACKEND_RAN\\n'; }\n"
            "_eks_platform_disable_live_deletion_protection() { printf 'DISABLE_RAN\\n'; }\n"
            "_run_terraform_destroy_or_report_prevent_destroy() { printf 'DESTROY_RAN\\n'; }\n"
            "destroy_eks_platform_scope\n"
            "printf 'STATUS=%s\\n' \"$?\"\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": f"{self.mock_bin}:/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )

        self.assertIn("STATUS=1", result.stdout)
        self.assertNotIn("DESTROY_RAN", result.stdout)
        self.assertNotIn("DISABLE_RAN", result.stdout)
        self.assertIn("not confirmed at the interactive typed-yes gate", result.stderr)


if __name__ == "__main__":
    unittest.main()
