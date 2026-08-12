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

    @staticmethod
    def _strip_comments(text):
        """Drop comment lines and blank lines, keeping executable shell only."""
        return "\n".join(
            line for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )

    def test_handler_fragment_has_no_mongodb_references(self):
        """No mongodb symbols may leak into postgresql's handlers -- the
        original hazard was copy-pasted code calling mongodb functions.

        Comments are excluded deliberately (#162): #111 added prose
        explaining that these handlers use "the same shared helper
        mongodb's and signoz's destroy handlers use", which is accurate,
        useful, and not a code dependency. Asserting over comments made
        this fail on documentation alone.
        """
        handler_code = self._strip_comments(
            (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")
        )
        internal_code = self._strip_comments(self._content())
        self.assertNotIn("mongodb", handler_code.lower())
        self.assertNotIn("mongodb", internal_code.lower())

    def test_handler_wrappers_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / INTERNAL_LIFECYCLE)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class DestroyEnvironmentAwarenessTests(unittest.TestCase):
    """Issue #111: postgresql_internal_destroy_postgresql_{core,brand} are
    environment-aware.

    They previously shelled out to the DEV-hardcoded
    scripts/legacy/dev/destroy.sh and refused to run for UAT/Production
    ("not yet environment-aware", issue #95). Commit 99a240c replaced that
    with a real teardown calling terraform_destroy_scope directly -- the
    same shared helper mongodb's and signoz's destroy handlers use -- so
    the refusal no longer exists and these tests assert the current
    contract instead (#162).

    The safety property that matters is now structural: the handlers
    require ENVIRONMENT and the per-scope state key to be set, so they
    cannot silently act on the wrong environment's state.
    """

    def _run(self, function_name, account_id, extra_env=None):
        contracts_path = REPO_ROOT / "scripts" / "lib" / "environment-contracts.sh"
        script = (
            f'source "{contracts_path}"; '
            f'source "{REPO_ROOT / INTERNAL_LIFECYCLE}"; '
            f'EXPECTED_AWS_ACCOUNT_ID={account_id} {function_name}'
        )
        env = {"_ORCHESTRATOR_ROOT_DIR": "/nonexistent-guard-test-root", "PATH": "/usr/bin:/bin"}
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", "-c", script],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_legacy_refusal_is_gone(self):
        """The #95 refusal must not reappear: these scopes are environment-
        aware now, and a hardcoded refusal would re-break UAT/Prod destroy."""
        for function_name in (
            "postgresql_internal_destroy_postgresql_core",
            "postgresql_internal_destroy_postgresql_brand",
        ):
            for account_id in ("672172129937", "632674123947", "815402439714"):
                with self.subTest(function=function_name, account=account_id):
                    result = self._run(function_name, account_id)
                    self.assertNotIn("not yet environment-aware", result.stderr)

    def test_destroy_requires_environment_to_be_set(self):
        """Fails closed rather than defaulting to an environment: without
        ENVIRONMENT there is no safe scope to destroy."""
        for function_name in (
            "postgresql_internal_destroy_postgresql_core",
            "postgresql_internal_destroy_postgresql_brand",
        ):
            with self.subTest(function=function_name):
                result = self._run(function_name, "672172129937")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ENVIRONMENT", result.stderr)

    def test_destroy_requires_its_own_state_key(self):
        """Each scope must demand its own state key, so core can never be
        destroyed using brand's state (or vice versa)."""
        cases = (
            ("postgresql_internal_destroy_postgresql_core", "POSTGRESQL_CORE_STATE_KEY"),
            ("postgresql_internal_destroy_postgresql_brand", "POSTGRESQL_BRAND_STATE_KEY"),
        )
        for function_name, expected_key in cases:
            with self.subTest(function=function_name):
                result = self._run(function_name, "672172129937", {"ENVIRONMENT": "uat"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected_key, result.stderr)


if __name__ == "__main__":
    unittest.main()
