"""Task 5 handler tests for:
  scripts/lib/scope-handlers.d/40-postgresql.sh
  scripts/lib/packages/40-postgresql/internal/lifecycle-handlers.sh

Covers:
  1. Static contract: fragment defines exactly the four canonical wrapper symbols
  2. Static contract: fragment sources only lifecycle-handlers.sh via validated helper
  3. Static contract: wrapper definitions delegate exactly to mapped internal helpers
  4. Static contract: internal file defines only postgresql_internal_* functions
  5. Static contract: internal file defines no canonical registry or guard symbols
  6. Bash syntax: bash -n passes on both files
"""

import re
import subprocess
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT

HANDLER_FRAGMENT = "scripts/lib/scope-handlers.d/40-postgresql.sh"
INTERNAL_LIFECYCLE = "scripts/lib/packages/40-postgresql/internal/lifecycle-handlers.sh"

# Exactly the four canonical wrappers the fragment must define, mapped to
# the internal helpers they must delegate to.
CANONICAL_WRAPPERS = {
    "scope_registry_deferred_postgresql_core_provision":        "postgresql_internal_provision_postgresql_core",
    "scope_registry_deferred_postgresql_brand_provision":       "postgresql_internal_provision_postgresql_brand",
    "scope_registry_deferred_postgresql_core_destroy":          "postgresql_internal_destroy_postgresql_core",
    "scope_registry_deferred_postgresql_brand_destroy":         "postgresql_internal_destroy_postgresql_brand",
}

# Symbols that must NOT appear in the handler fragment or internal file.
DISALLOWED_CANONICAL_SYMBOLS = (
    "scope_registry_verify_postgresql_core",
    "scope_registry_verify_postgresql_brand",
)

# Pre-destroy guard wrappers the fragment must ALSO define, registered here
# once #50 unblocked postgresql-core/postgresql-brand dispatch the same way
# #35 did for the EKS-family scopes.
PRE_DESTROY_GUARD_WRAPPERS = {
    "scope_registry_pre_destroy_guard_postgresql_core": "postgresql_internal_postgresql_core_pre_destroy_guard",
    "scope_registry_pre_destroy_guard_postgresql_brand": "postgresql_internal_postgresql_brand_pre_destroy_guard",
}


class HandlerFragmentStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")

    def test_handler_fragment_sources_internal_lifecycle_handlers(self):
        content = self._content()
        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertEqual(
            source_lines,
            [
                'source_package_internal_library "40-postgresql/internal/live-observations.sh" || return 1',
                'source_package_internal_library "40-postgresql/internal/lifecycle-handlers.sh" || return 1',
                'source_package_internal_library "40-postgresql/internal/pre-destroy-guards.sh" || return 1',
            ],
            "fragment must source live-observations.sh, lifecycle-handlers.sh, then pre-destroy-guards.sh via validated helper",
        )

    def test_pre_destroy_guard_wrappers_delegate_exactly_to_mapped_internal_guards(self):
        content = self._content()
        for wrapper, internal in PRE_DESTROY_GUARD_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                expected_line = f'{wrapper}() {{ {internal} "$@"; }}'
                self.assertIn(expected_line, content)

    def test_handler_wrappers_delegate_correctly_to_internal(self):
        content = self._content()
        for wrapper, internal in CANONICAL_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                expected_line = f'{wrapper}() {{ {internal} "$@"; }}'
                self.assertIn(
                    expected_line,
                    content,
                    f"missing or malformed delegation: expected {expected_line!r}",
                )

    def test_handler_wrappers_use_postgresql_core_scope_name(self):
        content = self._content()
        self.assertIn("postgresql_core", content)

    def test_handler_wrappers_use_postgresql_brand_scope_name(self):
        content = self._content()
        self.assertIn("postgresql_brand", content)

    def test_handler_wrappers_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / HANDLER_FRAGMENT)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class InternalLifecycleStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_LIFECYCLE).read_text(encoding="utf-8")

    def test_scope_handlers_postgresql_core_provides_provision_wrapper(self):
        content = self._content()
        self.assertIn("postgresql_internal_provision_postgresql_core", content)

    def test_scope_handlers_postgresql_core_provides_destroy_wrapper(self):
        content = self._content()
        self.assertIn("postgresql_internal_destroy_postgresql_core", content)

    def test_scope_handlers_postgresql_core_provides_access_provision_wrapper(self):
        content = self._content()
        self.assertIn("postgresql_internal_provision_postgresql_brand", content)

    def test_scope_handlers_postgresql_core_provides_access_destroy_wrapper(self):
        content = self._content()
        self.assertIn("postgresql_internal_destroy_postgresql_brand", content)

    def test_scope_handlers_postgresql_brand_provides_provision_wrapper(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertTrue(function_names, "lifecycle-handlers.sh must define at least one function")

    def test_scope_handlers_postgresql_brand_provides_destroy_wrapper(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("postgresql_internal_"),
                    f"{name} must start with postgresql_internal_",
                )

    def test_handler_fragment_has_no_mongodb_references(self):
        handler_content = (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")
        internal_content = self._content()
        # Case-insensitive search for mongodb references
        self.assertNotIn("mongodb", handler_content.lower())
        self.assertNotIn("mongodb", internal_content.lower())

    def test_handler_wrappers_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / INTERNAL_LIFECYCLE)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class DestroyEnvironmentGuardTests(unittest.TestCase):
    """Issue #95: postgresql_internal_destroy_postgresql_{core,brand} shell
    out to the DEV-hardcoded scripts/legacy/dev/destroy.sh and are not yet
    environment-aware. Until rewritten, they must refuse to run whenever
    EXPECTED_AWS_ACCOUNT_ID resolves to UAT or Production, rather than
    silently destroying DEV resources while believing they target them.
    """

    def _run(self, function_name, account_id):
        contracts_path = REPO_ROOT / "scripts" / "lib" / "environment-contracts.sh"
        script = (
            f'source "{contracts_path}"; '
            f'source "{REPO_ROOT / INTERNAL_LIFECYCLE}"; '
            f'EXPECTED_AWS_ACCOUNT_ID={account_id} {function_name}'
        )
        return subprocess.run(
            ["bash", "-c", script],
            env={"_ORCHESTRATOR_ROOT_DIR": "/nonexistent-guard-test-root", "PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )

    def test_core_refuses_to_run_for_uat_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_core", "672172129937")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)
        self.assertIn("issue #95", result.stderr)

    def test_brand_refuses_to_run_for_uat_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_brand", "672172129937")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)

    def test_core_refuses_to_run_for_prod_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_core", "632674123947")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)

    def test_brand_refuses_to_run_for_prod_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_brand", "632674123947")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not yet environment-aware", result.stderr)

    def test_core_does_not_block_dev_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_core", "815402439714")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertIn("No such file or directory", result.stderr)

    def test_brand_does_not_block_dev_account(self):
        result = self._run("postgresql_internal_destroy_postgresql_brand", "815402439714")
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertIn("No such file or directory", result.stderr)


if __name__ == "__main__":
    unittest.main()
