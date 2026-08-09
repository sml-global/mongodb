import re
import stat
import unittest
from pathlib import Path

from tests.environment_orchestration.helpers import REPO_ROOT, RepositoryFixture

HANDLER_FRAGMENT = "scripts/lib/scope-handlers.d/20-eks-platform.sh"
INTERNAL_LIFECYCLE = "scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh"

CANONICAL_WRAPPERS = {
    "scope_registry_deferred_eks_platform_provision": "eks_internal_eks_platform_provision_handler",
    "scope_registry_deferred_workload_identity_provision": "eks_internal_workload_identity_provision_handler",
    "scope_registry_deferred_platform_controllers_provision": "eks_internal_platform_controllers_provision_handler",
    "scope_registry_deferred_eks_platform_destroy": "eks_internal_eks_platform_destroy_handler",
    "scope_registry_deferred_workload_identity_destroy": "eks_internal_workload_identity_destroy_handler",
    "scope_registry_deferred_platform_controllers_destroy": "eks_internal_platform_controllers_destroy_handler",
}

DISALLOWED_CANONICAL_SYMBOLS = (
    "scope_registry_verify_eks_platform",
    "scope_registry_verify_workload_identity",
    "scope_registry_verify_platform_controllers",
)

PRE_DESTROY_GUARD_WRAPPERS = {
    "scope_registry_pre_destroy_guard_eks_platform": "eks_internal_eks_platform_pre_destroy_guard",
    "scope_registry_pre_destroy_guard_workload_identity": "eks_internal_workload_identity_pre_destroy_guard",
    "scope_registry_pre_destroy_guard_platform_controllers": "eks_internal_platform_controllers_pre_destroy_guard",
}


class HandlerFragmentStaticContractTests(unittest.TestCase):
    def test_fragment_defines_only_canonical_wrappers_and_single_validated_source(self):
        content = (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")

        function_names = re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE)
        expected_names = set(CANONICAL_WRAPPERS) | set(PRE_DESTROY_GUARD_WRAPPERS)
        self.assertEqual(set(function_names), expected_names)

        source_lines = [
            line.strip() for line in content.splitlines()
            if line.strip().startswith("source_package_internal_library")
        ]
        self.assertEqual(
            source_lines,
            [
                'source_package_internal_library "20-eks-platform/internal/live-observations.sh" || return 1',
                'source_package_internal_library "20-eks-platform/internal/lifecycle-handlers.sh" || return 1',
                'source_package_internal_library "20-eks-platform/internal/pre-destroy-guards.sh" || return 1',
            ],
        )

        self.assertNotIn("verifiers.sh", content)
        self.assertNotIn("../", content)
        self.assertNotIn("$(`", content)
        for line in source_lines:
            self.assertNotIn("$(", line)

    def test_pre_destroy_guard_wrappers_delegate_exactly_to_mapped_internal_guards(self):
        content = (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")
        for wrapper, internal in PRE_DESTROY_GUARD_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                pattern = re.compile(
                    r"^" + re.escape(wrapper) + r"\(\)\s*\{\s*" + re.escape(internal) + r'\s+"\$@";\s*\}',
                    flags=re.MULTILINE,
                )
                self.assertRegex(content, pattern)

    def test_wrapper_definitions_delegate_exactly_to_mapped_internal_helpers(self):
        content = (REPO_ROOT / HANDLER_FRAGMENT).read_text(encoding="utf-8")
        for wrapper, internal in CANONICAL_WRAPPERS.items():
            with self.subTest(wrapper=wrapper):
                expected_line = f'{wrapper}() {{ {internal} "$@"; }}'
                self.assertIn(expected_line, content)


class InternalLifecycleStaticContractTests(unittest.TestCase):
    def test_internal_file_defines_only_eks_internal_functions(self):
        content = (REPO_ROOT / INTERNAL_LIFECYCLE).read_text(encoding="utf-8")
        function_names = re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE)

        self.assertTrue(function_names)
        for name in function_names:
            with self.subTest(name=name):
                self.assertTrue(name.startswith("eks_internal_"))

        for symbol in DISALLOWED_CANONICAL_SYMBOLS:
            with self.subTest(symbol=symbol):
                self.assertNotIn(symbol, content)

        self.assertNotIn("source_package_internal_library", content)
        self.assertNotIn("verify_eks_platform_pre_destroy", content)
        self.assertNotIn("verify_workload_identity_pre_destroy", content)
        self.assertNotIn("verify_platform_controllers_pre_destroy", content)
        self.assertNotRegex(content, r"^scope_registry_", msg="canonical wrappers must not be defined in internal file")

    def test_internal_helper_names_avoid_verifier_and_pre_destroy_guard_surfaces(self):
        content = (REPO_ROOT / INTERNAL_LIFECYCLE).read_text(encoding="utf-8")
        function_names = re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", content, flags=re.MULTILINE)

        for name in function_names:
            with self.subTest(name=name):
                self.assertNotIn("pre_destroy_guard", name)
                self.assertNotRegex(name, r"^eks_internal_.*verifier")


class EksHandlerRuntimeFixture(RepositoryFixture):
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
            "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh",
            "scripts/lib/packages/20-eks-platform/internal/live-observations.sh",
            "scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh",
            "scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )

        # Make copied shell files executable for stricter parity with runtime.
        for rel in (
            "scripts/lib/orchestrator.sh",
            "scripts/lib/terraform-destroy-scope.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
        ):
            path = self.root / rel
            path.chmod(path.stat().st_mode | stat.S_IXUSR)


class RegistryLoadingAndBoundaryTests(EksHandlerRuntimeFixture):
    def test_registry_loading_flow_resolves_wrappers_without_registry_drift(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1

before_scopes="$(list_provision_scopes | tr '\n' '|')"
before_provision_all="$(resolve_provision_order all | tr '\n' '|')"
before_destroy_all="$(resolve_destroy_order all | tr '\n' '|')"
before_eks_platform_handler="$(provision_handler_for_scope eks-platform)"
before_workload_handler="$(provision_handler_for_scope workload-identity)"
before_platform_controllers_handler="$(provision_handler_for_scope platform-controllers)"
before_eks_platform_destroy="$(destroy_handler_for_scope eks-platform)"
before_workload_destroy="$(destroy_handler_for_scope workload-identity)"
before_platform_controllers_destroy="$(destroy_handler_for_scope platform-controllers)"
before_eks_platform_guard="$(pre_destroy_guard_for_scope eks-platform)"
before_workload_guard="$(pre_destroy_guard_for_scope workload-identity)"
before_platform_controllers_guard="$(pre_destroy_guard_for_scope platform-controllers)"

_orchestrator_load_package_fragments provision eks-platform || exit 1

after_scopes="$(list_provision_scopes | tr '\n' '|')"
after_provision_all="$(resolve_provision_order all | tr '\n' '|')"
after_destroy_all="$(resolve_destroy_order all | tr '\n' '|')"
after_eks_platform_handler="$(provision_handler_for_scope eks-platform)"
after_workload_handler="$(provision_handler_for_scope workload-identity)"
after_platform_controllers_handler="$(provision_handler_for_scope platform-controllers)"
after_eks_platform_destroy="$(destroy_handler_for_scope eks-platform)"
after_workload_destroy="$(destroy_handler_for_scope workload-identity)"
after_platform_controllers_destroy="$(destroy_handler_for_scope platform-controllers)"
after_eks_platform_guard="$(pre_destroy_guard_for_scope eks-platform)"
after_workload_guard="$(pre_destroy_guard_for_scope workload-identity)"
after_platform_controllers_guard="$(pre_destroy_guard_for_scope platform-controllers)"

[[ "$before_scopes" == "$after_scopes" ]] || exit 1
[[ "$before_provision_all" == "$after_provision_all" ]] || exit 1
[[ "$before_destroy_all" == "$after_destroy_all" ]] || exit 1
[[ "$before_eks_platform_handler" == "$after_eks_platform_handler" ]] || exit 1
[[ "$before_workload_handler" == "$after_workload_handler" ]] || exit 1
[[ "$before_platform_controllers_handler" == "$after_platform_controllers_handler" ]] || exit 1
[[ "$before_eks_platform_destroy" == "$after_eks_platform_destroy" ]] || exit 1
[[ "$before_workload_destroy" == "$after_workload_destroy" ]] || exit 1
[[ "$before_platform_controllers_destroy" == "$after_platform_controllers_destroy" ]] || exit 1
[[ "$before_eks_platform_guard" == "$after_eks_platform_guard" ]] || exit 1
[[ "$before_workload_guard" == "$after_workload_guard" ]] || exit 1
[[ "$before_platform_controllers_guard" == "$after_platform_controllers_guard" ]] || exit 1

for scope in eks-platform workload-identity platform-controllers; do
  symbol="$(provision_handler_for_scope "$scope")"
  [[ "$(type -t "$symbol")" == "function" ]] || exit 1
done
for scope in eks-platform workload-identity platform-controllers; do
  symbol="$(destroy_handler_for_scope "$scope")"
  [[ "$(type -t "$symbol")" == "function" ]] || exit 1
done
'''
        result = self.run_bash(
            script,
            extra_env={
                "EXPECTED_AWS_ACCOUNT_ID": "672172129937",
                "AWS_REGION": "ap-east-1",
                "ENVIRONMENT": "uat",
                "EKS_PLATFORM_IDENTITY": "arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_source_boundary_rejects_escape_substitution_and_alternate_paths(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1

_ORCHESTRATOR_ACTIVE_FRAGMENT_PACKAGE="20-eks-platform"

source_package_internal_library "20-eks-platform/internal/lifecycle-handlers.sh" || exit 1

if source_package_internal_library "../10-foundation-access/internal/access-scopes.sh"; then
  exit 1
fi
if source_package_internal_library "20-eks-platform/internal/../../10-foundation-access/internal/access-scopes.sh"; then
  exit 1
fi
if source_package_internal_library "20-eks-platform/internal/verifiers.sh"; then
  exit 1
fi
if source_package_internal_library "10-foundation-access/internal/access-scopes.sh"; then
  exit 1
fi
'''
        result = self.run_bash(
          script,
          extra_env={
            "EXPECTED_AWS_ACCOUNT_ID": "672172129937",
            "AWS_REGION": "ap-east-1",
            "ENVIRONMENT": "uat",
            "EKS_PLATFORM_IDENTITY": "arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster",
          },
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_wrapper_delegation_is_non_recursive_and_symbol_safe(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments provision eks-platform || exit 1

eks_internal_eks_platform_provision_handler() { printf 'delegated:eks-platform:provision\n'; }
eks_internal_workload_identity_provision_handler() { printf 'delegated:workload-identity:provision\n'; }
eks_internal_platform_controllers_provision_handler() { printf 'delegated:platform-controllers:provision\n'; }

out1="$(scope_registry_deferred_eks_platform_provision)" || exit 1
out2="$(scope_registry_deferred_workload_identity_provision)" || exit 1
out3="$(scope_registry_deferred_platform_controllers_provision)" || exit 1

[[ "$out1" == 'delegated:eks-platform:provision' ]] || exit 1
[[ "$out2" == 'delegated:workload-identity:provision' ]] || exit 1
[[ "$out3" == 'delegated:platform-controllers:provision' ]] || exit 1

eks_internal_require_foundation_destroy_guards() { return 0; }
eks_internal_recheck_destroy_drift_or_refuse() { return 0; }
eks_internal_execute_destroy_mutation() { printf 'delegated:%s:destroy\n' "$1"; }

d1="$(scope_registry_deferred_eks_platform_destroy)" || exit 1
d2="$(scope_registry_deferred_workload_identity_destroy)" || exit 1
d3="$(scope_registry_deferred_platform_controllers_destroy)" || exit 1

[[ "$d1" == 'delegated:eks-platform:destroy' ]] || exit 1
[[ "$d2" == 'delegated:workload-identity:destroy' ]] || exit 1
[[ "$d3" == 'delegated:platform-controllers:destroy' ]] || exit 1
'''
        result = self.run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)


class ModeAndDestroySafetyTests(EksHandlerRuntimeFixture):
    def test_modeled_mode_is_blocked_before_mutation_and_before_handler_load(self):
        result = self.run_bash(
            'source scripts/lib/orchestrator.sh && run_unified_command provision --env dev eks-platform'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unified dev mutation is blocked while PROMOTION_MODE=modeled", result.stderr)
        self.assertFalse(self.command_log.exists())
        self.assertFalse((self.root / ".local").exists())

    def test_uat_build_still_requires_foundation_identity_guard_before_dispatch(self):
        result = self.run_bash(
            'source scripts/lib/orchestrator.sh && run_unified_command provision --env uat eks-platform'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unable to read the active AWS account", result.stderr)

        self.assertTrue(self.command_log.exists())
        lines = self.command_log.read_text(encoding="utf-8").splitlines()
        self.assertTrue(any("aws sts get-caller-identity" in line for line in lines))
        self.assertFalse((self.root / ".local").exists())

    def test_destroy_handler_runs_identity_context_authentication_guards_in_order(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments destroy eks-platform || exit 1

trace=""

verify_aws_identity_and_region() {
  trace+="identity;"
  return 0
}

verify_kubernetes_context() {
  trace+="context;"
  return 0
}

verify_eks_authentication_mode() {
  trace+="auth;"
  return 0
}

eks_internal_live_destroy_drift_vector() {
  printf 'account=672172129937\nregion=ap-east-1\nenvironment=uat\nplatform_identity=arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster\neks_deletion_protection=enabled\nefs_protection=enabled\nbackup_retention_days=35\nvault_lock_state=locked\n'
}

eks_internal_execute_destroy_mutation() {
  trace+="mutate;"
  return 0
}

scope_registry_deferred_eks_platform_destroy || exit 1
[[ "$trace" == "identity;context;auth;mutate;" ]] || exit 1
'''
        result = self.run_bash(
            script,
            extra_env={
                "EXPECTED_AWS_ACCOUNT_ID": "672172129937",
                "AWS_REGION": "ap-east-1",
                "ENVIRONMENT": "uat",
                "EKS_PLATFORM_IDENTITY": "arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_destroy_refuses_on_drift_before_first_mutation(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments destroy eks-platform || exit 1

trace=""
mutation_calls=0

eks_internal_require_foundation_destroy_guards() {
  trace+="guard-check;"
  return 0
}

eks_internal_live_destroy_drift_vector() {
  if [[ "$2" == "baseline" ]]; then
    printf 'account=672172129937\nregion=ap-east-1\nenvironment=uat\nplatform_identity=arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster\neks_deletion_protection=enabled\nefs_protection=enabled\nbackup_retention_days=35\nvault_lock_state=locked\n'
    return 0
  fi
  printf 'account=672172129937\nregion=ap-east-1\nenvironment=uat\nplatform_identity=arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster\neks_deletion_protection=enabled\nefs_protection=enabled\nbackup_retention_days=14\nvault_lock_state=locked\n'
}

eks_internal_execute_destroy_mutation() {
  mutation_calls=$((mutation_calls + 1))
  trace+="mutate;"
  return 0
}

if scope_registry_deferred_eks_platform_destroy; then
  exit 1
fi

[[ "$mutation_calls" -eq 0 ]] || exit 1
[[ "$trace" == "guard-check;" ]] || exit 1
'''
        result = self.run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_destroy_refuses_when_live_observation_is_unavailable(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments destroy eks-platform || exit 1

mutation_calls=0

eks_internal_require_foundation_destroy_guards() { return 0; }
eks_internal_execute_destroy_mutation() {
  mutation_calls=$((mutation_calls + 1))
  return 0
}

if scope_registry_deferred_eks_platform_destroy; then
  exit 1
fi

[[ "$mutation_calls" -eq 0 ]] || exit 1
'''
        result = self.run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_destroy_refuses_when_protection_state_is_unsafe_even_if_stable(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments destroy eks-platform || exit 1

mutation_calls=0

eks_internal_require_foundation_destroy_guards() { return 0; }
eks_internal_live_destroy_drift_vector() {
  printf 'account=672172129937\nregion=ap-east-1\nenvironment=uat\nplatform_identity=arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster\neks_deletion_protection=enabled\nefs_protection=enabled\nbackup_retention_days=14\nvault_lock_state=locked\n'
}
eks_internal_execute_destroy_mutation() {
  mutation_calls=$((mutation_calls + 1))
  return 0
}

if scope_registry_deferred_eks_platform_destroy; then
  exit 1
fi

[[ "$mutation_calls" -eq 0 ]] || exit 1
'''
        result = self.run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_destroy_runs_immediate_recheck_then_mutates_only_when_stable(self):
        script = r'''
source scripts/lib/orchestrator.sh || exit 1
_orchestrator_load_package_fragments destroy eks-platform || exit 1

trace=""
mutation_calls=0

eks_internal_require_foundation_destroy_guards() {
  trace+="guard-check;"
  return 0
}

eks_internal_live_destroy_drift_vector() {
  printf 'phase:%s\n' "$2" >> "$RECHECK_TRACE_FILE"
  printf 'account=672172129937\nregion=ap-east-1\nenvironment=uat\nplatform_identity=arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster\neks_deletion_protection=enabled\nefs_protection=enabled\nbackup_retention_days=35\nvault_lock_state=locked\n'
}

eks_internal_execute_destroy_mutation() {
  mutation_calls=$((mutation_calls + 1))
  trace+="mutate;"
  return 0
}

scope_registry_deferred_eks_platform_destroy || exit 1

[[ "$mutation_calls" -eq 1 ]] || exit 1
[[ "$trace" == "guard-check;mutate;" ]] || exit 1
[[ "$(cat "$RECHECK_TRACE_FILE")" == $'phase:baseline\nphase:pre-mutation' ]] || exit 1
'''
        trace_file = self.root / "recheck-trace.log"
        result = self.run_bash(
          script,
          extra_env={
            "RECHECK_TRACE_FILE": str(trace_file),
            "EXPECTED_AWS_ACCOUNT_ID": "672172129937",
            "AWS_REGION": "ap-east-1",
            "ENVIRONMENT": "uat",
            "EKS_PLATFORM_IDENTITY": "arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster",
          },
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
