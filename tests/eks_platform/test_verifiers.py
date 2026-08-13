"""Task 7 ("Define Canonical Component-Verifier Wrappers") tests for:
  scripts/lib/scope-verifiers.d/20-eks-platform.sh
  scripts/lib/packages/20-eks-platform/internal/verifiers.sh
  scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh

Covers:
  1. Static contract: fragment defines exactly the six canonical symbols
  2. Static contract: verifiers.sh defines only eks_internal_* verifier functions
  3. Static contract: pre-destroy-guards.sh defines only eks_internal_*_pre_destroy_guard
  4. Static contract: mutual non-sourcing between internal files
  5. Static contract: fragment sources exactly verifiers.sh then pre-destroy-guards.sh
  6. Runtime: success path for each of the three guards (callback spy, exit 0,
     contract-derived identity, sha256 format, no artifact file)
  7. Runtime: failure path for each guard (FAIL, non-zero exit, no artifact file)
  8. Runtime: GUARD_MISSING_RESULT abort when guard returns without calling callback
  9. Runtime: GUARD_WRAPPER_STATUS_DISAGREEMENT abort (PASS + non-zero, FAIL + zero)
"""

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT, RepositoryFixture

VERIFIER_FRAGMENT = "scripts/lib/scope-verifiers.d/20-eks-platform.sh"
INTERNAL_VERIFIERS = "scripts/lib/packages/20-eks-platform/internal/verifiers.sh"
INTERNAL_GUARDS = "scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh"

# Exactly the six canonical symbols that the verifier fragment must define.
SIX_CANONICAL_SYMBOLS = (
    "scope_registry_verify_eks_platform",
    "scope_registry_verify_workload_identity",
    "scope_registry_verify_platform_controllers",
    "verify_eks_platform_pre_destroy",
    "verify_workload_identity_pre_destroy",
    "verify_platform_controllers_pre_destroy",
)

# Exact delegation map: fragment wrapper -> internal helper
CANONICAL_WRAPPER_DELEGATES = {
    "scope_registry_verify_eks_platform": "eks_internal_eks_platform_verifier",
    "scope_registry_verify_workload_identity": "eks_internal_workload_identity_verifier",
    "scope_registry_verify_platform_controllers": "eks_internal_platform_controllers_verifier",
    "verify_eks_platform_pre_destroy": "eks_internal_eks_platform_pre_destroy_guard",
    "verify_workload_identity_pre_destroy": "eks_internal_workload_identity_pre_destroy_guard",
    "verify_platform_controllers_pre_destroy": "eks_internal_platform_controllers_pre_destroy_guard",
}

# Canonical guard symbols in the registry
REGISTRY_GUARD_SYMBOLS = (
    "scope_registry_pre_destroy_guard_eks_platform",
    "scope_registry_pre_destroy_guard_workload_identity",
    "scope_registry_pre_destroy_guard_platform_controllers",
)

# Canonical verifier symbols in the registry (placeholder names)
DISALLOWED_IN_INTERNALS = SIX_CANONICAL_SYMBOLS + REGISTRY_GUARD_SYMBOLS

# EKS platform identity used in runtime tests
_TEST_CLUSTER_ARN = "arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster"
_TEST_ENV = {
    "EKS_PLATFORM_IDENTITY": _TEST_CLUSTER_ARN,
    "EKS_CLUSTER_NAME": "oms-uat-eks-cluster",
    "AWS_REGION": "ap-east-1",
    "EXPECTED_AWS_ACCOUNT_ID": "672172129937",
    "ENVIRONMENT": "uat",
}

# A valid 64-hex-zero string for use in hand-crafted callback invocations
_ZEROS_HEX = "0" * 64
_ZEROS_DIGEST = f"sha256:{_ZEROS_HEX}"

# Bash snippet that produces passing observations for a given scope
_PASS_OBSERVATIONS_EKS_PLATFORM = """
eks_internal_live_guard_observations() {
  case "$1" in
    eks-platform)
      printf 'workload_identity_absent=true\\n'
      printf 'platform_controllers_absent=true\\n'
      printf 'eks_deletion_protection=enabled\\n'
      printf 'efs_protection=enabled\\n'
      printf 'backup_retention_days=35\\n'
      printf 'vault_lock_state=locked\\n'
      ;;
    workload-identity|platform-controllers)
      printf 'eks_deletion_protection=enabled\\n'
      printf 'efs_protection=enabled\\n'
      printf 'backup_retention_days=35\\n'
      printf 'vault_lock_state=locked\\n'
      ;;
  esac
}
"""

# eks-platform's remaining failure mode from observation DATA is a
# dependent that is not absent (a destroy-ORDER violation). Protection
# state -- deletion protection, EFS prevent_destroy, retention, vault lock
# -- is deliberately no longer a precondition on any of these three guards:
# requiring protections to still be ON blocked an operator from finishing a
# partially-completed teardown (#159) while adding no safety once a human
# has typed yes against a real enumerated resource list. The values are
# still observed, still hashed into the guard digest, and still recorded in
# the durable evidence record.
_FAIL_OBSERVATIONS_EKS_PLATFORM = """
eks_internal_live_guard_observations() {
  case "$1" in
    eks-platform)
      printf 'workload_identity_absent=false\\n'
      printf 'platform_controllers_absent=true\\n'
      printf 'eks_deletion_protection=enabled\\n'
      printf 'efs_protection=enabled\\n'
      printf 'backup_retention_days=35\\n'
      printf 'vault_lock_state=locked\\n'
      ;;
    workload-identity|platform-controllers)
      printf 'eks_deletion_protection=disabled\\n'
      printf 'efs_protection=enabled\\n'
      printf 'backup_retention_days=35\\n'
      printf 'vault_lock_state=locked\\n'
      ;;
  esac
}
"""

# workload-identity and platform-controllers have no dependent-absence
# check of their own (they are themselves dependents of eks-platform), so
# with protection state no longer a precondition their only remaining
# failure mode is being unable to read live observations at all. That is
# still a genuine fail-closed path and is what their failure tests below
# exercise.
_UNAVAILABLE_OBSERVATIONS = """
eks_internal_live_guard_observations() {
  printf 'ERROR: simulated observation failure\\n' >&2
  return 1
}
"""


# ---------------------------------------------------------------------------
# 1-5: Static contract tests (no subprocess needed)
# ---------------------------------------------------------------------------

class VerifierFragmentStaticContractTests(unittest.TestCase):
    """Fragment defines exactly the six canonical symbols, no more, no less,
    with exact delegation format, and sources exactly the two internal files
    in the correct order."""

    def _content(self):
        return (REPO_ROOT / VERIFIER_FRAGMENT).read_text(encoding="utf-8")

    def test_fragment_defines_exactly_six_canonical_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertEqual(
            set(function_names),
            set(SIX_CANONICAL_SYMBOLS),
            f"expected exactly {sorted(SIX_CANONICAL_SYMBOLS)}, got {sorted(function_names)}",
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
                'source_package_internal_library "20-eks-platform/internal/verifiers.sh" || return 1',
                'source_package_internal_library "20-eks-platform/internal/pre-destroy-guards.sh" || return 1',
            ],
            "fragment must source exactly verifiers.sh then pre-destroy-guards.sh via validated helper",
        )

    def test_fragment_sources_no_direct_source_or_dot_statements(self):
        content = self._content()
        # No bare `source` or `.` that bypasses the validated helper
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


class InternalVerifiersStaticContractTests(unittest.TestCase):
    """verifiers.sh defines only eks_internal_* verifier helpers.
    No canonical wrappers, no guard symbols, no lifecycle/handler symbols.
    Does not source pre-destroy-guards.sh."""

    def _content(self):
        return (REPO_ROOT / INTERNAL_VERIFIERS).read_text(encoding="utf-8")

    def test_verifiers_defines_only_eks_internal_prefixed_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertTrue(function_names, "verifiers.sh must define at least one function")
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("eks_internal_"),
                    f"{name} must start with eks_internal_",
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
                self.assertNotRegex(name, r"_(provision|destroy)_handler$")

    def test_verifiers_defines_no_canonical_wrapper_symbols(self):
        content = self._content()
        for sym in DISALLOWED_IN_INTERNALS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)

    def test_verifiers_does_not_source_pre_destroy_guards(self):
        content = self._content()
        self.assertNotIn("pre-destroy-guards.sh", content)
        # Check only non-comment lines for active sourcing calls (comments may
        # document the expected source path without actually executing it).
        non_comment = "\n".join(
            ln for ln in content.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn("source_package_internal_library", non_comment)


class InternalPreDestroyGuardsStaticContractTests(unittest.TestCase):
    """pre-destroy-guards.sh defines only eks_internal_*_pre_destroy_guard functions.
    No canonical wrappers, no verifier symbols, no lifecycle/handler symbols.
    Does not source verifiers.sh."""

    def _content(self):
        return (REPO_ROOT / INTERNAL_GUARDS).read_text(encoding="utf-8")

    def test_guards_defines_only_pre_destroy_guard_functions(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        self.assertTrue(function_names, "pre-destroy-guards.sh must define at least one function")
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(
                    name.startswith("eks_internal_"),
                    f"{name} must start with eks_internal_",
                )
                self.assertTrue(
                    name.endswith("_pre_destroy_guard"),
                    f"{name} must end with _pre_destroy_guard",
                )

    def test_guards_defines_no_canonical_wrapper_symbols(self):
        content = self._content()
        for sym in DISALLOWED_IN_INTERNALS:
            with self.subTest(symbol=sym):
                self.assertNotIn(sym, content)

    def test_guards_defines_no_verifier_symbols(self):
        content = self._content()
        # No eks_internal_*verifier* function definitions
        self.assertNotRegex(
            content,
            r"^eks_internal_[A-Za-z0-9_]*verifier[A-Za-z0-9_]*\(\)",
            "pre-destroy-guards.sh must not define any verifier function",
        )

    def test_guards_defines_no_handler_or_lifecycle_symbols(self):
        content = self._content()
        function_names = re.findall(
            r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE
        )
        for name in function_names:
            with self.subTest(name=name):
                self.assertNotRegex(name, r"_(provision|destroy)_handler$")

    def test_guards_does_not_source_verifiers(self):
        content = self._content()
        # Check only non-comment lines: header comments may mention verifiers.sh
        # as documentation without actually sourcing it.
        non_comment = "\n".join(
            ln for ln in content.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn("verifiers.sh", non_comment)
        self.assertNotIn("source_package_internal_library", non_comment)


# ---------------------------------------------------------------------------
# Runtime fixture
# ---------------------------------------------------------------------------

class EksGuardRuntimeFixture(RepositoryFixture):
    """Loads the orchestrator, registry, handler fragment, and verifier
    fragment into a real bash subprocess and drives guards through
    _orchestrator_dispatch_guard (the foundation's guard-wrapper caller)."""

    def setUp(self):
        super().setUp()
        self.copy(
            "scripts/lib/orchestrator.sh",
            "scripts/lib/terraform-destroy-scope.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "scripts/lib/scope-handlers.d/10-foundation-access.sh",
            "scripts/lib/scope-handlers.d/20-eks-platform.sh",
            "scripts/lib/scope-verifiers.d/10-foundation-access.sh",
            "scripts/lib/scope-verifiers.d/20-eks-platform.sh",
            "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh",
            "scripts/lib/packages/20-eks-platform/internal/live-observations.sh",
            "scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh",
            "scripts/lib/packages/20-eks-platform/internal/verifiers.sh",
            "scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )
        for rel in (
            "scripts/lib/orchestrator.sh",
            "scripts/lib/terraform-destroy-scope.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
        ):
            path = self.root / rel
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_guard_script(self, body, extra_env=None):
        """Sources orchestrator.sh + loads fragments, runs body, then dumps
        guard state as KEY=value lines on stdout."""
        script = (
            "source scripts/lib/orchestrator.sh || exit 1\n"
            "_orchestrator_load_package_fragments verify eks-platform || exit 1\n"
            + body
            + "\n"
            "printf 'RETURN_CODE=%s\\n' \"${LAST_RC:-0}\"\n"
            "printf 'ABORTED=%s\\n' \"${_ORCHESTRATOR_GUARD_ABORTED:-false}\"\n"
            "printf 'FAILURE_CODE=%s\\n' \"${_ORCHESTRATOR_GUARD_FAILURE_CODE:-}\"\n"
            "printf 'FAILURE_WRAPPER_STATUS=%s\\n' \"${_ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS:-}\"\n"
            "printf 'RESULT_COUNT=%s\\n' \"${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}\"\n"
            "printf 'RESULT_SCOPES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_SCOPES[*]:-}\"\n"
            "printf 'RESULT_STATUSES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_STATUSES[*]:-}\"\n"
            "printf 'RESULT_IDENTITIES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_IDENTITIES[*]:-}\"\n"
            "printf 'RESULT_DIGESTS=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_DIGESTS[*]:-}\"\n"
            "printf 'RESULT_SUMMARIES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_SUMMARIES[*]:-}\"\n"
        )
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_COMMAND_LOG": str(self.command_log),
        })
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

    def _no_artifact_files_created(self):
        """Return True if no .local/ evidence directory was created in the
        sandbox, confirming the guard did not touch the durable evidence
        artifact layer."""
        local_dir = self.root / ".local"
        return not local_dir.exists()


# ---------------------------------------------------------------------------
# 6: Success path tests
# ---------------------------------------------------------------------------

class EksPlatformGuardSuccessTests(EksGuardRuntimeFixture):
    """eks-platform guard: success path with passing observations."""

    def _run_success(self):
        body = (
            _PASS_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_eks_platform() { verify_eks_platform_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard eks-platform 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_success_path_callback_called_exactly_once(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_success_path_status_is_pass(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_STATUSES"), "PASS", state["_result"].stderr)

    def test_success_path_identity_is_contract_derived_cluster_arn(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_IDENTITIES"), _TEST_CLUSTER_ARN)

    def test_success_path_digest_is_valid_sha256_format(self):
        state = self._run_success()
        self.assertRegex(
            state.get("RESULT_DIGESTS", ""),
            r"^sha256:[0-9a-f]{64}$",
        )

    def test_success_path_exit_code_is_zero(self):
        state = self._run_success()
        self.assertEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_success_path_guard_not_aborted(self):
        state = self._run_success()
        self.assertEqual(state.get("ABORTED"), "false", state["_result"].stderr)

    def test_success_path_no_evidence_artifact_created(self):
        self._run_success()
        self.assertTrue(
            self._no_artifact_files_created(),
            "guard must not create any evidence artifact files",
        )


class WorkloadIdentityGuardSuccessTests(EksGuardRuntimeFixture):
    """workload-identity guard: success path."""

    def _run_success(self):
        body = (
            _PASS_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_workload_identity() { verify_workload_identity_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard workload-identity 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_success_path_callback_called_exactly_once(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_success_path_status_is_pass(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_STATUSES"), "PASS", state["_result"].stderr)

    def test_success_path_identity_is_cluster_arn_plus_workload_identity_suffix(self):
        state = self._run_success()
        expected = f"{_TEST_CLUSTER_ARN}/workload-identity"
        self.assertEqual(state.get("RESULT_IDENTITIES"), expected)

    def test_success_path_digest_is_valid_sha256_format(self):
        state = self._run_success()
        self.assertRegex(
            state.get("RESULT_DIGESTS", ""),
            r"^sha256:[0-9a-f]{64}$",
        )

    def test_success_path_exit_code_is_zero(self):
        state = self._run_success()
        self.assertEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_success_path_no_evidence_artifact_created(self):
        self._run_success()
        self.assertTrue(self._no_artifact_files_created())


class PlatformControllersGuardSuccessTests(EksGuardRuntimeFixture):
    """platform-controllers guard: success path."""

    def _run_success(self):
        body = (
            _PASS_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_platform_controllers() { verify_platform_controllers_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard platform-controllers 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_success_path_callback_called_exactly_once(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_success_path_status_is_pass(self):
        state = self._run_success()
        self.assertEqual(state.get("RESULT_STATUSES"), "PASS", state["_result"].stderr)

    def test_success_path_identity_is_cluster_arn_plus_platform_controllers_suffix(self):
        state = self._run_success()
        expected = f"{_TEST_CLUSTER_ARN}/platform-controllers"
        self.assertEqual(state.get("RESULT_IDENTITIES"), expected)

    def test_success_path_digest_is_valid_sha256_format(self):
        state = self._run_success()
        self.assertRegex(
            state.get("RESULT_DIGESTS", ""),
            r"^sha256:[0-9a-f]{64}$",
        )

    def test_success_path_exit_code_is_zero(self):
        state = self._run_success()
        self.assertEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_success_path_no_evidence_artifact_created(self):
        self._run_success()
        self.assertTrue(self._no_artifact_files_created())


# ---------------------------------------------------------------------------
# 7: Failure path tests
# ---------------------------------------------------------------------------

class EksPlatformGuardFailureTests(EksGuardRuntimeFixture):
    """eks-platform guard: failure path (dependent not absent)."""

    def _run_failure(self):
        body = (
            _FAIL_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_eks_platform() { verify_eks_platform_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard eks-platform 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_failure_path_callback_called_exactly_once(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_failure_path_status_is_fail(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_STATUSES"), "FAIL", state["_result"].stderr)

    def test_failure_path_identity_is_contract_derived_cluster_arn(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_IDENTITIES"), _TEST_CLUSTER_ARN)

    def test_failure_path_digest_is_valid_sha256_format(self):
        state = self._run_failure()
        self.assertRegex(
            state.get("RESULT_DIGESTS", ""),
            r"^sha256:[0-9a-f]{64}$",
        )

    def test_failure_path_exit_code_is_nonzero(self):
        state = self._run_failure()
        self.assertNotEqual(state.get("RETURN_CODE"), "0", state["_result"].stderr)

    def test_failure_path_no_evidence_artifact_created(self):
        self._run_failure()
        self.assertTrue(self._no_artifact_files_created())

    def test_failure_digest_differs_from_success_digest(self):
        fail_state = self._run_failure()
        body = (
            _PASS_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_eks_platform() { verify_eks_platform_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard eks-platform 0 || LAST_RC=$?\n"
        )
        pass_state = self.run_guard_script(body, extra_env=_TEST_ENV)
        self.assertNotEqual(
            fail_state.get("RESULT_DIGESTS"),
            pass_state.get("RESULT_DIGESTS"),
            "digest over failed observations must differ from digest over passing observations",
        )


class WorkloadIdentityGuardFailureTests(EksGuardRuntimeFixture):
    """workload-identity guard: failure path (live observations
    unavailable). Protection state is no longer a precondition -- see the
    note on _UNAVAILABLE_OBSERVATIONS above and #159."""

    def _run_failure(self):
        body = (
            _UNAVAILABLE_OBSERVATIONS
            + "\n"
            "scope_registry_pre_destroy_guard_workload_identity() { verify_workload_identity_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard workload-identity 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_failure_path_callback_called_exactly_once(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_failure_path_status_is_fail(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_STATUSES"), "FAIL", state["_result"].stderr)

    def test_failure_path_exit_code_is_nonzero(self):
        state = self._run_failure()
        self.assertNotEqual(state.get("RETURN_CODE"), "0")

    def test_failure_path_no_evidence_artifact_created(self):
        self._run_failure()
        self.assertTrue(self._no_artifact_files_created())


class PlatformControllersGuardFailureTests(EksGuardRuntimeFixture):
    """platform-controllers guard: failure path (live observations
    unavailable). Protection state is no longer a precondition -- see the
    note on _UNAVAILABLE_OBSERVATIONS above and #159."""

    def _run_failure(self):
        body = (
            _UNAVAILABLE_OBSERVATIONS
            + "\n"
            "scope_registry_pre_destroy_guard_platform_controllers() { verify_platform_controllers_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard platform-controllers 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_failure_path_callback_called_exactly_once(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_COUNT"), "1", state["_result"].stderr)

    def test_failure_path_status_is_fail(self):
        state = self._run_failure()
        self.assertEqual(state.get("RESULT_STATUSES"), "FAIL", state["_result"].stderr)

    def test_failure_path_exit_code_is_nonzero(self):
        state = self._run_failure()
        self.assertNotEqual(state.get("RETURN_CODE"), "0")

    def test_failure_path_no_evidence_artifact_created(self):
        self._run_failure()
        self.assertTrue(self._no_artifact_files_created())


# ---------------------------------------------------------------------------
# 8: GUARD_MISSING_RESULT tests
# ---------------------------------------------------------------------------

class GuardMissingResultTests(EksGuardRuntimeFixture):
    """Foundation detects GUARD_MISSING_RESULT when a guard wrapper returns
    without ever calling record_pre_destroy_guard_result."""

    def _run_missing_for(self, scope, registry_symbol):
        body = (
            f"{registry_symbol}() {{ return 0; }}\n"
            "LAST_RC=0\n"
            f"_orchestrator_dispatch_guard {scope} 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_eks_platform_guard_missing_result_triggers_abort(self):
        state = self._run_missing_for(
            "eks-platform", "scope_registry_pre_destroy_guard_eks_platform"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_MISSING_RESULT")

    def test_workload_identity_guard_missing_result_triggers_abort(self):
        state = self._run_missing_for(
            "workload-identity", "scope_registry_pre_destroy_guard_workload_identity"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_MISSING_RESULT")

    def test_platform_controllers_guard_missing_result_triggers_abort(self):
        state = self._run_missing_for(
            "platform-controllers", "scope_registry_pre_destroy_guard_platform_controllers"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_MISSING_RESULT")


# ---------------------------------------------------------------------------
# 9: GUARD_WRAPPER_STATUS_DISAGREEMENT tests
# ---------------------------------------------------------------------------

class GuardWrapperStatusDisagreementTests(EksGuardRuntimeFixture):
    """Foundation detects GUARD_WRAPPER_STATUS_DISAGREEMENT when:
    - guard records PASS but the wrapper exits non-zero, or
    - guard records FAIL but the wrapper exits zero."""

    def _run_pass_but_nonzero(self, scope, registry_symbol):
        body = (
            f"{registry_symbol}() {{\n"
            f"  record_pre_destroy_guard_result {scope} PASS "
            f'"{_TEST_CLUSTER_ARN}" "{_ZEROS_DIGEST}" PASS_MARKER\n'
            "  return 1\n"
            "}\n"
            "LAST_RC=0\n"
            f"_orchestrator_dispatch_guard {scope} 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def _run_fail_but_zero(self, scope, registry_symbol, identity):
        body = (
            f"{registry_symbol}() {{\n"
            f"  record_pre_destroy_guard_result {scope} FAIL "
            f'"{identity}" "{_ZEROS_DIGEST}" FAIL_MARKER\n'
            "  return 0\n"
            "}\n"
            "LAST_RC=0\n"
            f"_orchestrator_dispatch_guard {scope} 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_eks_platform_pass_with_nonzero_exit_triggers_disagreement(self):
        state = self._run_pass_but_nonzero(
            "eks-platform", "scope_registry_pre_destroy_guard_eks_platform"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_WRAPPER_STATUS_DISAGREEMENT")

    def test_eks_platform_fail_with_zero_exit_triggers_abort(self):
        # When the guard records FAIL, the callback returns 1 and immediately
        # fires GUARD_FAIL abort; the exit-code disagreement check is not
        # separately reached. The important guarantee — destroy is blocked —
        # holds regardless of which abort code fires.
        state = self._run_fail_but_zero(
            "eks-platform", "scope_registry_pre_destroy_guard_eks_platform",
            _TEST_CLUSTER_ARN,
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_FAIL")

    def test_workload_identity_pass_with_nonzero_exit_triggers_disagreement(self):
        state = self._run_pass_but_nonzero(
            "workload-identity", "scope_registry_pre_destroy_guard_workload_identity"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_WRAPPER_STATUS_DISAGREEMENT")

    def test_workload_identity_fail_with_zero_exit_triggers_abort(self):
        state = self._run_fail_but_zero(
            "workload-identity", "scope_registry_pre_destroy_guard_workload_identity",
            f"{_TEST_CLUSTER_ARN}/workload-identity",
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_FAIL")

    def test_platform_controllers_pass_with_nonzero_exit_triggers_disagreement(self):
        state = self._run_pass_but_nonzero(
            "platform-controllers", "scope_registry_pre_destroy_guard_platform_controllers"
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_WRAPPER_STATUS_DISAGREEMENT")

    def test_platform_controllers_fail_with_zero_exit_triggers_abort(self):
        state = self._run_fail_but_zero(
            "platform-controllers", "scope_registry_pre_destroy_guard_platform_controllers",
            f"{_TEST_CLUSTER_ARN}/platform-controllers",
        )
        self.assertEqual(state.get("ABORTED"), "true", state["_result"].stderr)
        self.assertEqual(state.get("FAILURE_CODE"), "GUARD_FAIL")


# ---------------------------------------------------------------------------
# Guard: dependent-absence protection
# ---------------------------------------------------------------------------

class EksPlatformDependentAbsenceTests(EksGuardRuntimeFixture):
    """eks-platform guard refuses if registered dependents are not absent."""

    def _run_with_dependent_present(self, workload_absent="false", controllers_absent="true"):
        obs = f"""
eks_internal_live_guard_observations() {{
  printf 'workload_identity_absent={workload_absent}\\n'
  printf 'platform_controllers_absent={controllers_absent}\\n'
  printf 'eks_deletion_protection=enabled\\n'
  printf 'efs_protection=enabled\\n'
  printf 'backup_retention_days=35\\n'
  printf 'vault_lock_state=locked\\n'
}}
"""
        body = (
            obs
            + "scope_registry_pre_destroy_guard_eks_platform() { verify_eks_platform_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard eks-platform 0 || LAST_RC=$?\n"
        )
        return self.run_guard_script(body, extra_env=_TEST_ENV)

    def test_workload_identity_dependent_present_causes_fail(self):
        state = self._run_with_dependent_present(workload_absent="false")
        self.assertEqual(state.get("RESULT_STATUSES"), "FAIL", state["_result"].stderr)

    def test_platform_controllers_dependent_present_causes_fail(self):
        state = self._run_with_dependent_present(
            workload_absent="true", controllers_absent="false"
        )
        self.assertEqual(state.get("RESULT_STATUSES"), "FAIL", state["_result"].stderr)

    def test_both_dependents_absent_allows_pass(self):
        state = self._run_with_dependent_present(
            workload_absent="true", controllers_absent="true"
        )
        self.assertEqual(state.get("RESULT_STATUSES"), "PASS", state["_result"].stderr)


# ---------------------------------------------------------------------------
# Guard: SHA-256 digest determinism
# ---------------------------------------------------------------------------

class GuardDigestDeterminismTests(EksGuardRuntimeFixture):
    """Same observations → same digest on repeated calls."""

    def test_eks_platform_digest_is_deterministic(self):
        body = (
            _PASS_OBSERVATIONS_EKS_PLATFORM
            + "\n"
            "scope_registry_pre_destroy_guard_eks_platform() { verify_eks_platform_pre_destroy \"$@\"; }\n"
            "LAST_RC=0\n"
            "_orchestrator_dispatch_guard eks-platform 0 || LAST_RC=$?\n"
        )
        state1 = self.run_guard_script(body, extra_env=_TEST_ENV)
        state2 = self.run_guard_script(body, extra_env=_TEST_ENV)
        self.assertEqual(
            state1.get("RESULT_DIGESTS"),
            state2.get("RESULT_DIGESTS"),
            "same observations must produce the same digest",
        )
