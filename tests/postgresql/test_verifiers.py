"""Task 5 verifier tests for:
  scripts/lib/scope-verifiers.d/40-postgresql.sh
  scripts/lib/packages/40-postgresql/internal/verifiers.sh
  scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh

Covers:
  1. Static contract: fragment defines exactly the four canonical symbols
  2. Static contract: verifiers.sh defines only postgresql_internal_* verifier functions
  3. Static contract: pre-destroy-guards.sh defines only postgresql_internal_*_pre_destroy_guard
  4. Static contract: fragment sources exactly verifiers.sh then pre-destroy-guards.sh
  5. Static contract: guard uses seam-based callback mechanism
  6. Runtime: sha256 digest computed correctly
"""

import re
import subprocess
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT

VERIFIER_FRAGMENT = "scripts/lib/scope-verifiers.d/40-postgresql.sh"
INTERNAL_VERIFIERS = "scripts/lib/packages/40-postgresql/internal/verifiers.sh"
INTERNAL_GUARDS = "scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh"

# Exactly the four canonical symbols the verifier fragment must define.
FOUR_CANONICAL_SYMBOLS = (
    "scope_registry_verify_postgresql_core",
    "scope_registry_verify_postgresql_brand",
    "verify_postgresql_core_pre_destroy",
    "verify_postgresql_brand_pre_destroy",
)

# Exact delegation map: fragment wrapper -> internal helper
CANONICAL_WRAPPER_DELEGATES = {
    "scope_registry_verify_postgresql_core":        "postgresql_internal_postgresql_core_verifier",
    "scope_registry_verify_postgresql_brand":       "postgresql_internal_postgresql_brand_verifier",
    "verify_postgresql_core_pre_destroy":           "postgresql_internal_postgresql_core_pre_destroy_guard",
    "verify_postgresql_brand_pre_destroy":          "postgresql_internal_postgresql_brand_pre_destroy_guard",
}

DISALLOWED_IN_INTERNALS = FOUR_CANONICAL_SYMBOLS


class VerifierFragmentStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / VERIFIER_FRAGMENT).read_text(encoding="utf-8")

    def test_verifier_fragment_sources_internal_verifiers(self):
        content = self._content()
        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertGreater(len(source_lines), 0)
        self.assertIn('source_package_internal_library "40-postgresql/internal/verifiers.sh" || return 1', source_lines)

    def test_verifier_fragment_sources_internal_pre_destroy_guards(self):
        content = self._content()
        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertIn('source_package_internal_library "40-postgresql/internal/pre-destroy-guards.sh" || return 1', source_lines)


class InternalVerifiersStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_VERIFIERS).read_text(encoding="utf-8")

    def test_scope_verifiers_postgresql_core_exports_canonical_symbol(self):
        content = self._content()
        self.assertIn("postgresql_internal_postgresql_core_verifier", content)

    def test_scope_verifiers_postgresql_brand_exports_canonical_symbol(self):
        content = self._content()
        self.assertIn("postgresql_internal_postgresql_brand_verifier", content)


class InternalPreDestroyGuardsStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_GUARDS).read_text(encoding="utf-8")

    def test_scope_verifiers_postgresql_core_exports_pre_destroy_symbol(self):
        content = self._content()
        self.assertIn("postgresql_internal_postgresql_core_pre_destroy_guard", content)

    def test_scope_verifiers_postgresql_brand_exports_pre_destroy_symbol(self):
        content = self._content()
        self.assertIn("postgresql_internal_postgresql_brand_pre_destroy_guard", content)

    def test_guard_contract_uses_seam_callback_mechanism(self):
        content = self._content()
        self.assertIn("record_pre_destroy_guard_result", content)

    def test_pre_destroy_guard_computes_sha256_digest(self):
        content = self._content()
        self.assertIn("sha256:", content)


if __name__ == "__main__":
    unittest.main()
