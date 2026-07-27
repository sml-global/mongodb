"""Task 4 handler tests for:
  scripts/lib/scope-handlers.d/30-mongodb.sh
  scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh

Covers:
  1. Static contract: fragment defines exactly the four canonical wrapper symbols
  2. Static contract: fragment sources only lifecycle-handlers.sh via validated helper
  3. Static contract: wrapper definitions delegate exactly to mapped internal helpers
  4. Static contract: internal file defines only mongodb_internal_* functions
  5. Static contract: internal file defines no canonical registry or guard symbols
  6. Bash syntax: bash -n passes on both files
"""

import re
import subprocess
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT

HANDLER_FRAGMENT = "scripts/lib/scope-handlers.d/30-mongodb.sh"
INTERNAL_LIFECYCLE = "scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh"

# Exactly the four canonical wrappers the fragment must define, mapped to
# the internal helpers they must delegate to.
CANONICAL_WRAPPERS = {
    "scope_registry_deferred_mongodb_provision":        "mongodb_internal_provision_mongodb",
    "scope_registry_deferred_mongodb_access_provision": "mongodb_internal_provision_mongodb_access",
    "scope_registry_deferred_mongodb_destroy":          "mongodb_internal_destroy_mongodb",
    "scope_registry_deferred_mongodb_access_destroy":   "mongodb_internal_destroy_mongodb_access",
}

# Symbols that must NOT appear in the handler fragment or internal file.
DISALLOWED_CANONICAL_SYMBOLS = (
    "scope_registry_pre_destroy_guard_mongodb",
    "scope_registry_pre_destroy_guard_mongodb_access",
    "scope_registry_verify_mongodb",
    "scope_registry_verify_mongodb_access",
)


class HandlerFragmentStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")

    def test_fragment_defines_only_canonical_wrappers_and_single_validated_source(self):
        content = self._content()

        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertEqual(
            set(function_names),
            set(CANONICAL_WRAPPERS),
            f"expected exactly {sorted(CANONICAL_WRAPPERS)}, got {sorted(function_names)}",
        )

        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertEqual(
            source_lines,
            [
                'source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh" || return 1'
            ],
            "fragment must source exactly lifecycle-handlers.sh via validated helper",
        )

        self.assertNotIn("verifiers.sh", content)
        self.assertNotIn("pre-destroy-guards.sh", content)
        self.assertNotIn("../", content)
        self.assertNotIn("$(", source_lines[0])

    def test_fragment_sources_no_direct_source_or_dot_statements(self):
        content = self._content()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            self.assertNotRegex(
                stripped,
                r"^(source|\.)\s+[^\s]",
                f"line contains a direct source/dot statement: {stripped!r}",
            )

    def test_wrapper_definitions_delegate_exactly_to_mapped_internal_helpers(self):
        content = self._content()
        for wrapper, internal in CANONICAL_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                expected_line = f'{wrapper}() {{ {internal} "$@"; }}'
                self.assertIn(
                    expected_line,
                    content,
                    f"missing or malformed delegation: expected {expected_line!r}",
                )

    def test_fragment_defines_no_disallowed_canonical_symbols(self):
        content = self._content()
        for sym in DISALLOWED_CANONICAL_SYMBOLS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)

    def test_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / HANDLER_FRAGMENT)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class InternalLifecycleStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_LIFECYCLE).read_text(encoding="utf-8")

    def test_internal_file_defines_only_mongodb_internal_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertTrue(function_names, "lifecycle-handlers.sh must define at least one function")
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("mongodb_internal_"),
                    f"{name} must start with mongodb_internal_",
                )

    def test_internal_file_defines_no_canonical_registry_symbols(self):
        content = self._content()
        for sym in DISALLOWED_CANONICAL_SYMBOLS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)
        self.assertNotRegex(
            content,
            r"^scope_registry_",
            "canonical wrappers must not be defined in internal file",
        )

    def test_internal_file_does_not_source_verifiers_or_guards(self):
        content = self._content()
        self.assertNotIn("verifiers.sh", content)
        self.assertNotIn("pre-destroy-guards.sh", content)
        non_comment = "\n".join(
            ln for ln in content.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn("source_package_internal_library", non_comment)

    def test_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / INTERNAL_LIFECYCLE)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


if __name__ == "__main__":
    unittest.main()
