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


class DestroyEnvironmentAwareTests(unittest.TestCase):
    """Issue #111: signoz_internal_destroy_{signoz,signoz_observability} are
    now environment-aware -- they call destroy-k8s.sh/destroy-observability.sh
    directly with the caller's own environment values, instead of shelling
    out to the DEV-hardcoded scripts/legacy/dev/destroy.sh. The
    forbidden-account guard from #95/#96/#97 no longer applies to this
    scope; this replaces the removed DestroyEnvironmentGuardTests for
    signoz specifically (postgresql keeps its own guard tests until it
    gets the same rewrite).
    """

    LIFECYCLE_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages"
        / "50-signoz" / "internal" / "lifecycle-handlers.sh"
    )
    DESTROY_K8S_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages"
        / "50-signoz" / "internal" / "destroy-k8s.sh"
    )
    DESTROY_OBSERVABILITY_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages"
        / "50-signoz" / "internal" / "destroy-observability.sh"
    )
    TF_DESTROY_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "terraform-destroy-scope.sh"
    )
    CONTRACTS_PATH = (
        Path(__file__).parent.parent.parent / "scripts" / "lib" / "environment-contracts.sh"
    )

    def _run(self, function_name, account_id):
        script = (
            f'source "{self.CONTRACTS_PATH}"; '
            f'source "{self.TF_DESTROY_PATH}"; '
            f'source "{self.DESTROY_K8S_PATH}"; '
            f'source "{self.DESTROY_OBSERVABILITY_PATH}"; '
            f'source "{self.LIFECYCLE_PATH}"; '
            'export SIGNOZ_NAMESPACE=signoz-uat ENVIRONMENT=uat '
            'SIGNOZ_OBSERVABILITY_STATE_KEY=oms/uat/signoz-observability.tfstate '
            'TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937 TF_STATE_REGION=ap-east-1 '
            f'EXPECTED_AWS_ACCOUNT_ID={account_id}; '
            f'{function_name}'
        )
        return subprocess.run(
            ["bash", "-c", script],
            env={"_ORCHESTRATOR_ROOT_DIR": "/nonexistent-destroy-test-root", "PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )

    def test_signoz_uses_environment_values_not_forbidden_account_guard(self):
        result = self._run("signoz_internal_destroy_signoz", "672172129937")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertNotIn("Refusing to run against forbidden AWS account", result.stderr)

    def test_signoz_observability_uses_environment_values_not_forbidden_account_guard(self):
        result = self._run("signoz_internal_destroy_signoz_observability", "672172129937")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertNotIn("Refusing to run against forbidden AWS account", result.stderr)


if __name__ == '__main__':
    unittest.main()
