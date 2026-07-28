"""Task 4 verifier tests for:
  scripts/lib/scope-verifiers.d/30-mongodb.sh
  scripts/lib/packages/30-mongodb/internal/verifiers.sh
  scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh

Covers:
  1. Static contract: fragment defines exactly the four canonical symbols
  2. Static contract: verifiers.sh defines only mongodb_internal_* verifier functions
  3. Static contract: pre-destroy-guards.sh defines only mongodb_internal_*_pre_destroy_guard
  4. Static contract: mutual non-sourcing between internal files
  5. Static contract: fragment sources exactly verifiers.sh then pre-destroy-guards.sh
  6. Runtime: success path for each guard (callback invoked, exit 0, identity from env,
     sha256 format, correct scope name)
  7. Runtime: failure path for each guard (FAIL + non-zero exit)
  8. Runtime: seam missing causes FAIL + non-zero
"""

import os
import re
import shutil
import stat
import subprocess
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT, RepositoryFixture

VERIFIER_FRAGMENT = "scripts/lib/scope-verifiers.d/30-mongodb.sh"
INTERNAL_VERIFIERS = "scripts/lib/packages/30-mongodb/internal/verifiers.sh"
INTERNAL_GUARDS = "scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh"

# Exactly the four canonical symbols the verifier fragment must define.
FOUR_CANONICAL_SYMBOLS = (
    "scope_registry_verify_mongodb",
    "scope_registry_verify_mongodb_access",
    "verify_mongodb_pre_destroy",
    "verify_mongodb_access_pre_destroy",
)

# Exact delegation map: fragment wrapper -> internal helper
CANONICAL_WRAPPER_DELEGATES = {
    "scope_registry_verify_mongodb":        "mongodb_internal_mongodb_verifier",
    "scope_registry_verify_mongodb_access": "mongodb_internal_mongodb_access_verifier",
    "verify_mongodb_pre_destroy":           "mongodb_internal_mongodb_pre_destroy_guard",
    "verify_mongodb_access_pre_destroy":    "mongodb_internal_mongodb_access_pre_destroy_guard",
}

# Registry guard dispatch symbols (stubs in scope-registry.sh)
REGISTRY_GUARD_SYMBOLS = (
    "scope_registry_pre_destroy_guard_mongodb",
    "scope_registry_pre_destroy_guard_mongodb_access",
)

DISALLOWED_IN_INTERNALS = FOUR_CANONICAL_SYMBOLS + REGISTRY_GUARD_SYMBOLS

_TEST_ENV = {
    "MONGODB_NAMESPACE": "mongodb",
    "MONGODB_REPLICA_SET_NAME": "rs0",
}

# Bash observations that produce a PASS for each scope
_PASS_OBSERVATIONS = """
mongodb_internal_live_guard_observations() {
  case "$1" in
    mongodb)
      printf 'mongodb_access_absent=true\\n'
      printf 'pvc_protection_enabled=enabled\\n'
      printf 'pbm_backup_enabled=enabled\\n'
      ;;
    mongodb-access)
      printf 'pvc_protection_enabled=enabled\\n'
      printf 'pbm_backup_enabled=enabled\\n'
      ;;
  esac
}
"""

# Bash observations that produce a FAIL for each scope
_FAIL_OBSERVATIONS = """
mongodb_internal_live_guard_observations() {
  case "$1" in
    mongodb)
      printf 'mongodb_access_absent=false\\n'
      printf 'pvc_protection_enabled=enabled\\n'
      printf 'pbm_backup_enabled=enabled\\n'
      ;;
    mongodb-access)
      printf 'pvc_protection_enabled=disabled\\n'
      printf 'pbm_backup_enabled=enabled\\n'
      ;;
  esac
}
"""


# ---------------------------------------------------------------------------
# 1–5: Static contract tests
# ---------------------------------------------------------------------------

class VerifierFragmentStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / VERIFIER_FRAGMENT).read_text(encoding="utf-8")

    def test_fragment_defines_exactly_four_canonical_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertEqual(
            set(function_names),
            set(FOUR_CANONICAL_SYMBOLS),
            f"expected exactly {sorted(FOUR_CANONICAL_SYMBOLS)}, got {sorted(function_names)}",
        )

    def test_fragment_sources_exactly_verifiers_then_pre_destroy_guards_in_order(self):
        content = self._content()
        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertEqual(
            source_lines,
            [
                'source_package_internal_library "30-mongodb/internal/verifiers.sh" || return 1',
                'source_package_internal_library "30-mongodb/internal/pre-destroy-guards.sh" || return 1',
            ],
            "fragment must source exactly verifiers.sh then pre-destroy-guards.sh via validated helper",
        )

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

    def test_fragment_does_not_reference_lifecycle_handlers(self):
        content = self._content()
        self.assertNotIn("lifecycle-handlers.sh", content)

    def test_fragment_contains_no_path_escape_or_substitution_in_source_calls(self):
        content = self._content()
        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        for line in source_lines:
            self.assertNotIn("../", line)
            self.assertNotIn("$(", line)
            self.assertNotIn("`", line)

    def test_wrapper_definitions_delegate_exactly_to_mapped_internal_helpers(self):
        content = self._content()
        for wrapper, internal in CANONICAL_WRAPPER_DELEGATES.items():
            with self.subTest(wrapper=wrapper):
                expected_line = f'{wrapper}() {{ {internal} "$@"; }}'
                self.assertIn(
                    expected_line,
                    content,
                    f"missing or malformed delegation: expected {expected_line!r}",
                )

    def test_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / VERIFIER_FRAGMENT)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class InternalVerifiersStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_VERIFIERS).read_text(encoding="utf-8")

    def test_verifiers_defines_only_mongodb_internal_prefixed_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertTrue(function_names, "verifiers.sh must define at least one function")
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("mongodb_internal_"),
                    f"{name} must start with mongodb_internal_",
                )

    def test_verifiers_defines_no_pre_destroy_guard_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        for name in function_names:
            with self.subTest(name=name):
                self.assertNotIn(
                    "pre_destroy_guard", name,
                    f"{name} must not contain pre_destroy_guard",
                )

    def test_verifiers_defines_no_handler_or_lifecycle_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        for name in function_names:
            with self.subTest(name=name):
                self.assertNotRegex(name, r"_(provision|destroy)(_handler)?$")

    def test_verifiers_defines_no_canonical_wrapper_symbols(self):
        content = self._content()
        for sym in DISALLOWED_IN_INTERNALS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)

    def test_verifiers_does_not_source_pre_destroy_guards(self):
        content = self._content()
        self.assertNotIn("pre-destroy-guards.sh", content)
        non_comment = "\n".join(
            ln for ln in content.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn("source_package_internal_library", non_comment)

    def test_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / INTERNAL_VERIFIERS)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


class InternalPreDestroyGuardsStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / INTERNAL_GUARDS).read_text(encoding="utf-8")

    def test_guards_defines_only_pre_destroy_guard_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        # Filter out helpers (allowed, but they must still start with mongodb_internal_)
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("mongodb_internal_"),
                    f"{name} must start with mongodb_internal_",
                )

    def test_guards_defines_expected_guard_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        guard_names = [n for n in function_names if n.endswith("_pre_destroy_guard")]
        self.assertIn("mongodb_internal_mongodb_pre_destroy_guard", guard_names)
        self.assertIn("mongodb_internal_mongodb_access_pre_destroy_guard", guard_names)

    def test_guards_defines_no_canonical_wrapper_symbols(self):
        content = self._content()
        for sym in DISALLOWED_IN_INTERNALS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)

    def test_guards_defines_no_verifier_symbols(self):
        content = self._content()
        self.assertNotRegex(
            content,
            r"^mongodb_internal_[A-Za-z0-9_]*verifier[A-Za-z0-9_]*\(\)",
            "pre-destroy-guards.sh must not define any verifier function",
        )

    def test_guards_defines_no_handler_or_lifecycle_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        for name in function_names:
            with self.subTest(name=name):
                self.assertNotRegex(name, r"_(provision|destroy)(_handler)?$")

    def test_guards_does_not_source_verifiers(self):
        content = self._content()
        non_comment = "\n".join(
            ln for ln in content.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn("verifiers.sh", non_comment)
        self.assertNotIn("source_package_internal_library", non_comment)

    def test_bash_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(REPO_ROOT / INTERNAL_GUARDS)],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_guards_call_record_pre_destroy_guard_result(self):
        content = self._content()
        self.assertIn("record_pre_destroy_guard_result", content)

    def test_guards_include_sha256_digest(self):
        content = self._content()
        self.assertIn("sha256:", content)


# ---------------------------------------------------------------------------
# Runtime fixture
# ---------------------------------------------------------------------------

class MongodbGuardRuntimeFixture(RepositoryFixture):
    """Sources orchestrator + fragments and drives guards directly."""

    def setUp(self):
        super().setUp()
        self.copy(
            "scripts/lib/orchestrator.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "scripts/lib/scope-handlers.d/10-foundation-access.sh",
            "scripts/lib/scope-handlers.d/20-eks-platform.sh",
            "scripts/lib/scope-handlers.d/30-mongodb.sh",
            "scripts/lib/scope-verifiers.d/10-foundation-access.sh",
            "scripts/lib/scope-verifiers.d/20-eks-platform.sh",
            "scripts/lib/scope-verifiers.d/30-mongodb.sh",
            "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh",
            "scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh",
            "scripts/lib/packages/20-eks-platform/internal/verifiers.sh",
            "scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh",
            "scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh",
            "scripts/lib/packages/30-mongodb/internal/verifiers.sh",
            "scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )

    def run_guard(self, scope, observations_bash, extra_env=None):
        """Runs a single guard via the internal function directly, wired to
        record_pre_destroy_guard_result provided by the orchestrator."""
        # Determine internal guard function name from scope
        guard_fn = (
            "mongodb_internal_mongodb_pre_destroy_guard"
            if scope == "mongodb"
            else "mongodb_internal_mongodb_access_pre_destroy_guard"
        )
        # Wire scope_registry_pre_destroy_guard_<scope> → verify_<scope>_pre_destroy
        scope_underscore = scope.replace("-", "_")
        wiring = (
            f"scope_registry_pre_destroy_guard_{scope_underscore}() "
            f'{{ verify_{scope_underscore}_pre_destroy "$@"; }}\n'
        )

        script = (
            "source scripts/lib/orchestrator.sh || exit 1\n"
            "_orchestrator_load_package_fragments verify mongodb || exit 1\n"
            + wiring
            + observations_bash
            + "\n"
            f"LAST_RC=0\n"
            f'_orchestrator_dispatch_guard "{scope}" 0 || LAST_RC=$?\n'
            'printf \'RETURN_CODE=%s\\n\' "$LAST_RC"\n'
            'printf \'ABORTED=%s\\n\' "${_ORCHESTRATOR_GUARD_ABORTED:-false}"\n'
            'printf \'RESULT_COUNT=%s\\n\' "${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}"\n'
            'printf \'RESULT_SCOPE=%s\\n\' "${_ORCHESTRATOR_GUARD_RESULT_SCOPES[*]:-}"\n'
            'printf \'RESULT_STATUS=%s\\n\' "${_ORCHESTRATOR_GUARD_RESULT_STATUSES[*]:-}"\n'
            'printf \'RESULT_IDENTITY=%s\\n\' "${_ORCHESTRATOR_GUARD_RESULT_IDENTITIES[*]:-}"\n'
            'printf \'RESULT_DIGEST=%s\\n\' "${_ORCHESTRATOR_GUARD_RESULT_DIGESTS[*]:-}"\n'
            'printf \'RESULT_SUMMARY=%s\\n\' "${_ORCHESTRATOR_GUARD_RESULT_SUMMARIES[*]:-}"\n'
        )

        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_COMMAND_LOG": str(self.command_log),
        })
        env.update(_TEST_ENV)
        if extra_env:
            env.update(extra_env)

        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
        )
        state = {}
        for line in result.stdout.splitlines():
            if "=" in line:
                key, _, value = line.partition("=")
                state[key] = value
        state["_result"] = result
        return state


class MongodbGuardRuntimePassTests(MongodbGuardRuntimeFixture):
    """Guards succeed when observations are nominal."""

    def test_mongodb_guard_pass_exit_zero(self):
        state = self.run_guard("mongodb", _PASS_OBSERVATIONS)
        self.assertEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_mongodb_guard_pass_result_recorded(self):
        state = self.run_guard("mongodb", _PASS_OBSERVATIONS)
        self.assertEqual(state.get("RESULT_COUNT"), "1")
        self.assertEqual(state.get("RESULT_SCOPE"), "mongodb")
        self.assertEqual(state.get("RESULT_STATUS"), "PASS")

    def test_mongodb_guard_pass_identity_contains_namespace(self):
        state = self.run_guard("mongodb", _PASS_OBSERVATIONS)
        identity = state.get("RESULT_IDENTITY", "")
        self.assertIn("mongodb", identity)

    def test_mongodb_guard_pass_digest_sha256_format(self):
        state = self.run_guard("mongodb", _PASS_OBSERVATIONS)
        digest = state.get("RESULT_DIGEST", "")
        self.assertTrue(
            digest.startswith("sha256:"),
            f"digest must start with sha256:, got {digest!r}",
        )
        self.assertRegex(
            digest[7:], r"^[0-9a-f]{64}$",
            f"digest hex part must be 64 hex chars, got {digest[7:]!r}",
        )

    def test_mongodb_access_guard_pass_exit_zero(self):
        state = self.run_guard("mongodb-access", _PASS_OBSERVATIONS)
        self.assertEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_mongodb_access_guard_pass_result_recorded(self):
        state = self.run_guard("mongodb-access", _PASS_OBSERVATIONS)
        self.assertEqual(state.get("RESULT_COUNT"), "1")
        self.assertEqual(state.get("RESULT_SCOPE"), "mongodb-access")
        self.assertEqual(state.get("RESULT_STATUS"), "PASS")

    def test_mongodb_access_guard_pass_digest_sha256_format(self):
        state = self.run_guard("mongodb-access", _PASS_OBSERVATIONS)
        digest = state.get("RESULT_DIGEST", "")
        self.assertTrue(digest.startswith("sha256:"))
        self.assertRegex(digest[7:], r"^[0-9a-f]{64}$")


class MongodbGuardRuntimeFailTests(MongodbGuardRuntimeFixture):
    """Guards fail when observations indicate a problem."""

    def test_mongodb_guard_fail_exit_nonzero(self):
        state = self.run_guard("mongodb", _FAIL_OBSERVATIONS)
        self.assertNotEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_mongodb_guard_fail_result_status_is_fail(self):
        state = self.run_guard("mongodb", _FAIL_OBSERVATIONS)
        self.assertEqual(state.get("RESULT_STATUS"), "FAIL")

    def test_mongodb_access_guard_fail_exit_nonzero(self):
        state = self.run_guard("mongodb-access", _FAIL_OBSERVATIONS)
        self.assertNotEqual(state.get("RETURN_CODE"), "0")

    def test_mongodb_access_guard_fail_result_status_is_fail(self):
        state = self.run_guard("mongodb-access", _FAIL_OBSERVATIONS)
        self.assertEqual(state.get("RESULT_STATUS"), "FAIL")


class MongodbGuardRuntimeSeamMissingTests(MongodbGuardRuntimeFixture):
    """Guard fails when the observations seam is not defined."""

    def test_mongodb_guard_fail_without_seam(self):
        state = self.run_guard("mongodb", "")
        self.assertNotEqual(state.get("RETURN_CODE"), "0")
        self.assertEqual(state.get("RESULT_STATUS"), "FAIL")

    def test_mongodb_access_guard_fail_without_seam(self):
        state = self.run_guard("mongodb-access", "")
        self.assertNotEqual(state.get("RETURN_CODE"), "0")
        self.assertEqual(state.get("RESULT_STATUS"), "FAIL")


if __name__ == "__main__":
    unittest.main()
