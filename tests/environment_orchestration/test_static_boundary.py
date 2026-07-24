import unittest

from .helpers import REPO_ROOT


UNIFIED_ENTRYPOINTS = (
    "scripts/provision.sh",
    "scripts/destroy.sh",
    "scripts/verify-platform-health.sh",
    "scripts/lib/orchestrator.sh",
)

UNIFIED_FOUNDATION_LIBS = (
    "scripts/lib/environment-contracts.sh",
    "scripts/lib/platform-env.sh",
    "scripts/lib/platform-guards.sh",
    "scripts/lib/orchestration-paths.sh",
    "scripts/lib/scope-registry.sh",
)

FORBIDDEN_LEGACY_REFERENCES = (
    "scripts/legacy/dev/provision.sh",
    "scripts/legacy/dev/destroy.sh",
    "scripts/legacy/dev/verify-platform-health.sh",
)


class StaticBoundaryTests(unittest.TestCase):
    def _read(self, relative_path):
        path = REPO_ROOT / relative_path
        return path.read_text(encoding="utf-8")

    def test_unified_orchestrator_and_libraries_do_not_source_legacy_dev_scripts(self):
        for relative_path in UNIFIED_FOUNDATION_LIBS:
            with self.subTest(path=relative_path):
                content = self._read(relative_path)
                for forbidden in FORBIDDEN_LEGACY_REFERENCES:
                    self.assertNotIn(forbidden, content)

    def test_public_wrappers_only_reference_legacy_in_non_env_branch(self):
        for relative_path in UNIFIED_ENTRYPOINTS[:3]:
            with self.subTest(path=relative_path):
                content = self._read(relative_path)
                # Public wrappers are allowed to delegate to legacy only for
                # the no-`--env` branch.
                self.assertIn("--env", content)
                self.assertIn("scripts/legacy/dev", content)

    def test_scope_registry_existing_platform_status_is_present(self):
        content = self._read("scripts/lib/scope-registry.sh")
        self.assertIn('eks-platform)', content)
        self.assertIn('"external-existing-platform"', content)

    def test_orchestrator_only_blocks_external_work_package_in_provision_gate(self):
        content = self._read("scripts/lib/orchestrator.sh")
        self.assertIn("external-work-package-*", content)
        self.assertNotIn("external-existing-platform-", content)


if __name__ == "__main__":
    unittest.main()
