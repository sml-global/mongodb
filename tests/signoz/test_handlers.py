#!/usr/bin/env python3
"""
tests/signoz/test_handlers.py

Test bash handler fragment validation for SigNoz.
Tests: 10

- test_handler_fragment_sources_internal_lifecycle_handlers
- test_handler_wrappers_delegate_to_internal_signoz
- test_handler_wrappers_delegate_to_internal_signoz_observability
- test_scope_handlers_signoz_provides_provision_wrapper
- test_scope_handlers_signoz_provides_destroy_wrapper
- test_scope_handlers_signoz_observability_provides_provision_wrapper
- test_scope_handlers_signoz_observability_provides_destroy_wrapper
- test_handler_fragment_has_no_mongodb_references
- test_handler_fragment_has_no_postgresql_references
- test_handler_wrappers_bash_syntax_valid
"""

import unittest
import subprocess
from pathlib import Path


class TestSignozHandlers(unittest.TestCase):
    """Validate SigNoz bash handler fragments."""

    @classmethod
    def setUpClass(cls):
        """Load handler files."""
        cls.lifecycle_handlers_path = (
            Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages" 
            / "50-signoz" / "internal" / "lifecycle-handlers.sh"
        )
        cls.scope_handlers_path = (
            Path(__file__).parent.parent.parent / "scripts" / "lib" / "scope-handlers.d" 
            / "50-signoz.sh"
        )
        
        # Load file content
        cls.lifecycle_handlers_content = cls._load_file(cls.lifecycle_handlers_path)
        cls.scope_handlers_content = cls._load_file(cls.scope_handlers_path)

    @staticmethod
    def _load_file(path):
        """Load file content."""
        if not path.exists():
            return ""
        with open(path, 'r') as f:
            return f.read()

    def test_handler_fragment_sources_internal_lifecycle_handlers(self):
        """Scope handlers must source internal lifecycle-handlers.sh."""
        self.assertIn("50-signoz/internal/lifecycle-handlers.sh", self.scope_handlers_content,
            "scope-handlers.d/50-signoz.sh must source lifecycle-handlers.sh")

    def test_handler_wrappers_delegate_to_internal_signoz(self):
        """Handler wrappers must delegate to internal signoz functions."""
        self.assertIn("signoz_internal_provision_signoz", self.scope_handlers_content,
            "Must delegate signoz provision to signoz_internal_provision_signoz")
        self.assertIn("signoz_internal_destroy_signoz", self.scope_handlers_content,
            "Must delegate signoz destroy to signoz_internal_destroy_signoz")

    def test_handler_wrappers_delegate_to_internal_signoz_observability(self):
        """Handler wrappers must delegate to internal signoz-observability functions."""
        self.assertIn("signoz_internal_provision_signoz_observability", self.scope_handlers_content,
            "Must delegate signoz-observability provision")
        self.assertIn("signoz_internal_destroy_signoz_observability", self.scope_handlers_content,
            "Must delegate signoz-observability destroy")

    def test_scope_handlers_signoz_provides_provision_wrapper(self):
        """Must export scope_registry_deferred_signoz_provision."""
        self.assertIn("scope_registry_deferred_signoz_provision", self.scope_handlers_content,
            "Must export scope_registry_deferred_signoz_provision")

    def test_scope_handlers_signoz_provides_destroy_wrapper(self):
        """Must export scope_registry_deferred_signoz_destroy."""
        self.assertIn("scope_registry_deferred_signoz_destroy", self.scope_handlers_content,
            "Must export scope_registry_deferred_signoz_destroy")

    def test_scope_handlers_signoz_observability_provides_provision_wrapper(self):
        """Must export scope_registry_deferred_signoz_observability_provision."""
        self.assertIn("scope_registry_deferred_signoz_observability_provision", self.scope_handlers_content,
            "Must export scope_registry_deferred_signoz_observability_provision")

    def test_scope_handlers_signoz_observability_provides_destroy_wrapper(self):
        """Must export scope_registry_deferred_signoz_observability_destroy."""
        self.assertIn("scope_registry_deferred_signoz_observability_destroy", self.scope_handlers_content,
            "Must export scope_registry_deferred_signoz_observability_destroy")

    def test_handler_fragment_has_no_mongodb_references(self):
        """Handler fragment must NOT contain mongodb references."""
        # Check both scope handlers and lifecycle handlers
        all_content = self.scope_handlers_content + self.lifecycle_handlers_content
        # Look for mongodb patterns (case-insensitive)
        self.assertNotIn("mongodb", all_content.lower(),
            "Handler fragment must not reference mongodb (copy-paste violation)")
        self.assertNotIn("MONGODB", all_content,
            "Handler fragment must not reference MONGODB (copy-paste violation)")

    def test_handler_fragment_has_no_postgresql_references(self):
        """Handler fragment must NOT contain postgresql references."""
        # Check both scope handlers and lifecycle handlers
        all_content = self.scope_handlers_content + self.lifecycle_handlers_content
        # Look for postgresql patterns
        self.assertNotIn("postgresql", all_content.lower(),
            "Handler fragment must not reference postgresql (copy-paste violation)")
        self.assertNotIn("POSTGRESQL", all_content,
            "Handler fragment must not reference POSTGRESQL (copy-paste violation)")

    def test_handler_wrappers_bash_syntax_valid(self):
        """Bash syntax must be valid (bash -n)."""
        result = subprocess.run(
            ["bash", "-n", str(self.scope_handlers_path)],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0,
            f"scope-handlers.d/50-signoz.sh has invalid bash syntax: {result.stderr}")


class DestroyEnvironmentGuardTests(unittest.TestCase):
    """Issue #95: signoz_internal_destroy_{signoz,signoz_observability} shell
    out to the DEV-hardcoded scripts/legacy/dev/destroy.sh and are not yet
    environment-aware. Until rewritten, they must refuse to run for any
    $ENVIRONMENT other than dev, rather than silently destroying DEV
    resources while believing they target UAT/Prod.
    """

    LIFECYCLE_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages"
        / "50-signoz" / "internal" / "lifecycle-handlers.sh"
    )

    def _run(self, function_name, environment):
        script = (
            f'source "{self.LIFECYCLE_PATH}"; '
            f'ENVIRONMENT={environment} {function_name}'
        )
        return subprocess.run(
            ["bash", "-c", script],
            env={"_ORCHESTRATOR_ROOT_DIR": "/nonexistent-guard-test-root", "PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )

    def test_signoz_refuses_to_run_for_uat(self):
        result = self._run("signoz_internal_destroy_signoz", "uat")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)
        self.assertIn("issue #95", result.stderr)

    def test_signoz_observability_refuses_to_run_for_uat(self):
        result = self._run("signoz_internal_destroy_signoz_observability", "uat")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)

    def test_signoz_does_not_block_dev(self):
        result = self._run("signoz_internal_destroy_signoz", "dev")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertIn("No such file or directory", result.stderr)

    def test_signoz_observability_does_not_block_dev(self):
        result = self._run("signoz_internal_destroy_signoz_observability", "dev")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertIn("No such file or directory", result.stderr)


if __name__ == '__main__':
    unittest.main()
