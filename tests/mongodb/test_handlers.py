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
import tempfile
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
    "scope_registry_verify_mongodb",
    "scope_registry_verify_mongodb_access",
)

# Pre-destroy guard wrappers the fragment must ALSO define, delegating to
# the real guard implementations in pre-destroy-guards.sh -- registered
# here (rather than left as scope-registry.sh's stub) once #50 unblocked
# mongodb/mongodb-access dispatch the same way #35 did for the EKS-family
# scopes.
PRE_DESTROY_GUARD_WRAPPERS = {
    "scope_registry_pre_destroy_guard_mongodb": "mongodb_internal_mongodb_pre_destroy_guard",
    "scope_registry_pre_destroy_guard_mongodb_access": "mongodb_internal_mongodb_access_pre_destroy_guard",
}


class HandlerFragmentStaticContractTests(unittest.TestCase):
    def _content(self):
        return (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")

    def test_fragment_defines_only_canonical_wrappers_and_single_validated_source(self):
        content = self._content()

        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        expected_names = set(CANONICAL_WRAPPERS) | set(PRE_DESTROY_GUARD_WRAPPERS)
        self.assertEqual(
            set(function_names),
            expected_names,
            f"expected exactly {sorted(expected_names)}, got {sorted(function_names)}",
        )

        source_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertEqual(
            source_lines,
            [
                'source_package_internal_library "30-mongodb/internal/live-observations.sh" || return 1',
                'source_package_internal_library "30-mongodb/internal/destroy-k8s.sh" || return 1',
                'source_package_internal_library "30-mongodb/internal/lifecycle-handlers.sh" || return 1',
                'source_package_internal_library "30-mongodb/internal/pre-destroy-guards.sh" || return 1',
            ],
            "fragment must source live-observations.sh, destroy-k8s.sh, lifecycle-handlers.sh, then pre-destroy-guards.sh via validated helper",
        )

    def test_pre_destroy_guard_wrappers_delegate_exactly_to_mapped_internal_guards(self):
        content = self._content()
        for wrapper, internal in PRE_DESTROY_GUARD_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                pattern = re.compile(
                    r"^" + re.escape(wrapper) + r"\(\)\s*\{\s*" + re.escape(internal) + r'\s+"\$@";\s*\}',
                    flags=re.MULTILINE,
                )
                self.assertRegex(content, pattern)

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


class DestroyEnvironmentAwareTests(unittest.TestCase):
    """Issue #111: mongodb_internal_destroy_mongodb is now environment-aware
    -- it calls destroy-k8s.sh/terraform-destroy-scope.sh directly with the
    caller's own environment values, instead of shelling out to the
    DEV-hardcoded scripts/legacy/dev/destroy.sh. The forbidden-account guard
    from #95/#96/#97 no longer applies to this scope; this replaces the
    removed DestroyEnvironmentGuardTests for mongodb specifically
    (postgresql/signoz keep their own guard tests until they get the same
    rewrite).
    """

    def test_uses_environment_values_not_forbidden_account_guard(self):
        contracts_path = REPO_ROOT / "scripts" / "lib" / "environment-contracts.sh"
        destroy_k8s_path = REPO_ROOT / "scripts" / "lib" / "packages" / "30-mongodb" / "internal" / "destroy-k8s.sh"
        tf_destroy_path = REPO_ROOT / "scripts" / "lib" / "terraform-destroy-scope.sh"
        script = (
            f'source "{contracts_path}"; '
            f'source "{tf_destroy_path}"; '
            f'source "{destroy_k8s_path}"; '
            f'source "{REPO_ROOT / INTERNAL_LIFECYCLE}"; '
            'export MONGODB_NAMESPACE=mongodb-uat EKS_CLUSTER_NAME=oms-uat-eks-cluster '
            'AWS_REGION=ap-east-1 ENVIRONMENT=uat MONGODB_STATE_KEY=oms/uat/mongo.tfstate '
            'TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937 TF_STATE_REGION=ap-east-1 '
            'EXPECTED_AWS_ACCOUNT_ID=672172129937; '
            'mongodb_internal_destroy_mongodb'
        )
        result = subprocess.run(
            ["bash", "-c", script],
            env={"_ORCHESTRATOR_ROOT_DIR": "/nonexistent-destroy-test-root", "PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )
        # Fails for an unrelated reason (fake root dir has no kubectl/terraform
        # binaries reachable, or no mongodb Terraform root there) -- not
        # because a forbidden-account guard rejected the UAT account.
        self.assertNotIn("not yet environment-aware", result.stderr)
        self.assertNotIn("Refusing to run against forbidden AWS account", result.stderr)

    def test_mongodb_access_destroy_targets_resolved_namespace(self):
        destroy_k8s_path = REPO_ROOT / "scripts" / "lib" / "packages" / "30-mongodb" / "internal" / "destroy-k8s.sh"
        script = (
            f'source "{destroy_k8s_path}"; '
            f'source "{REPO_ROOT / INTERNAL_LIFECYCLE}"; '
            'export MONGODB_NAMESPACE=mongodb-uat; '
            'mongodb_internal_destroy_mongodb_access'
        )
        fake_bin = tempfile.mkdtemp()
        kubectl_stub = Path(fake_bin) / "kubectl"
        kubectl_stub.write_text('#!/usr/bin/env bash\necho "KUBECTL_CALL: $*" >&2\nexit 0\n')
        kubectl_stub.chmod(0o755)
        result = subprocess.run(
            ["bash", "-c", script],
            env={"PATH": f"{fake_bin}:/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("KUBECTL_CALL: -n mongodb-uat delete secret oms-audit-writer", result.stderr)
        self.assertNotIn("INFO: mongodb-access destroy", result.stdout)


if __name__ == "__main__":
    unittest.main()
