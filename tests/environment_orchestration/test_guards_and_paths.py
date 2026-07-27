import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Exact override cases from
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md,
# Task 2 Step 1.
FORBIDDEN_OVERRIDES = {
    "AWS_ENDPOINT_URL": "",
    "AWS_ENDPOINT_URL_S3": "https://invalid.example",
    "AWS_S3_ENDPOINT": "https://invalid.example",
    "AWS_STS_ENDPOINT": "https://invalid.example",
    "AWS_CA_BUNDLE": "/tmp/invalid-ca.pem",
    "AWS_CONFIG_FILE": "/tmp/invalid-aws-config",
    "AWS_SHARED_CREDENTIALS_FILE": "/tmp/invalid-credentials",
    "AWS_PROFILE": "other",
    "AWS_DEFAULT_PROFILE": "other",
    "AWS_REGION": "us-east-1",
    "AWS_DEFAULT_REGION": "us-east-1",
    "KUBECONFIG": "/tmp/invalid-kubeconfig",
    "TF_CLI_CONFIG_FILE": "/tmp/invalid.tfrc",
    "TF_PLUGIN_CACHE_DIR": "/tmp/plugins",
    "TF_REATTACH_PROVIDERS": "{}",
    "TF_CLI_ARGS": "-destroy",
    "TF_CLI_ARGS_plan": "-destroy",
    "TF_VAR_expected_account_id": "000000000000",
    "TF_WORKSPACE": "other",
    "TF_DATA_DIR": "/tmp/terraform-data",
}

_MOCK_AWS_SCRIPT = """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
  printf '%s\\n' "${MOCK_AWS_ACCOUNT_ID:-000000000000}"
  exit 0
fi
if [[ "$1" == "configure" && "$2" == "get" ]]; then
  printf '%s\\n' "${MOCK_AWS_CONFIGURED_REGION:-}"
  exit 0
fi
if [[ "$1" == "eks" && "$2" == "describe-cluster" ]]; then
  printf '%s\\n' "${MOCK_EKS_AUTH_MODE-API}"
  exit 0
fi
printf 'unhandled mock aws invocation: %s\\n' "$*" >&2
exit 1
"""

_MOCK_KUBECTL_SCRIPT = """#!/usr/bin/env bash
printf 'kubectl %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$1" == "config" && "$2" == "current-context" ]]; then
  printf '%s\\n' "${MOCK_KUBE_CONTEXT:-mock-context}"
  exit 0
fi
if [[ "$1" == "config" && "$2" == "view" ]]; then
  printf '%s\\n' "${MOCK_KUBE_CLUSTER_REF:-}"
  exit 0
fi
printf 'unhandled mock kubectl invocation: %s\\n' "$*" >&2
exit 1
"""

_STUB_BACKEND_BOOTSTRAP_SCRIPT = """#!/usr/bin/env bash
printf 'bootstrap-backend %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
exit 0
"""


class GuardsAndPathsFixture(unittest.TestCase):
    """Private fixture with command-specific aws and kubectl mocks.

    Deliberately does not reuse tests/environment_orchestration/helpers.py's
    RepositoryFixture: that fixture's generic mocks only log invocations and
    always exit 97, which is enough to prove a command was never called but
    is not enough to drive the specific STS/kubectl/EKS-describe outputs the
    guard functions below branch on.
    """

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # Resolve symlinks (e.g. macOS /var -> /private/var) so self.root
        # matches the real, canonical path any `cd ... && pwd` computation
        # inside a bash script under test will naturally produce.
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = Path(self.temporary.name) / "bin"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)

        self._write_executable(self.mock_bin / "aws", _MOCK_AWS_SCRIPT)
        self._write_executable(self.mock_bin / "kubectl", _MOCK_KUBECTL_SCRIPT)

        self._copy(
            "scripts/lib/platform-env.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )
        self._write_executable(
            self.root / "scripts" / "bootstrap-terraform-s3-backend.sh",
            _STUB_BACKEND_BOOTSTRAP_SCRIPT,
        )

    def _write_executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _copy(self, *relative_paths):
        for relative in relative_paths:
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def run_bash(self, script, extra_env=None):
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        if extra_env:
            environment.update({key: str(value) for key, value in extra_env.items()})
        return subprocess.run(
            ["bash", "-c", script], cwd=self.root, env=environment,
            text=True, capture_output=True,
        )

    def load_env_prefix(self, environment):
        return (
            "source scripts/lib/platform-env.sh && "
            "source scripts/lib/platform-guards.sh && "
            f"load_platform_env {environment} && "
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return self.command_log.read_text(encoding="utf-8").splitlines()

    def tearDown(self):
        self.temporary.cleanup()


class ExecutionOverrideGuardTests(GuardsAndPathsFixture):
    """Step 1, proof 1: every prohibited override is rejected before any
    command or file mutation. Step 1, proof 2: the endpoint-ignore flag is
    forced for allowed child commands."""

    def test_every_forbidden_override_is_rejected_before_any_mutation(self):
        for variable_name, value in FORBIDDEN_OVERRIDES.items():
            with self.subTest(variable=variable_name):
                result = self.run_bash(
                    "source scripts/lib/platform-guards.sh && "
                    "reject_execution_environment_overrides",
                    extra_env={variable_name: value},
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(variable_name, result.stderr)
                self.assertEqual(self.command_log_lines(), [])
                self.assertFalse((self.root / ".local").exists())

    def test_ordinary_credential_and_session_variables_are_not_rejected(self):
        result = self.run_bash(
            "source scripts/lib/platform-guards.sh && "
            "reject_execution_environment_overrides && echo ok",
            extra_env={
                "AWS_ACCESS_KEY_ID": "AKIAEXAMPLE",
                "AWS_SECRET_ACCESS_KEY": "secret",
                "AWS_SESSION_TOKEN": "token",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ok", result.stdout)

    def test_forces_ignore_configured_endpoint_urls_after_guard_passes(self):
        result = self.run_bash(
            "source scripts/lib/platform-guards.sh && "
            "reject_execution_environment_overrides && "
            'printf \'%s\\n\' "$AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "true\n")


class IdentityAndRegionGuardTests(GuardsAndPathsFixture):
    """Step 1, proof 3: STS account and configured Region must exactly
    match the selected contract."""

    def test_matching_account_and_region_pass_with_a_single_sts_call(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_aws_identity_and_region",
            extra_env={
                "MOCK_AWS_ACCOUNT_ID": "672172129937",
                "MOCK_AWS_CONFIGURED_REGION": "ap-east-1",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        sts_calls = [line for line in self.command_log_lines() if "sts get-caller-identity" in line]
        self.assertEqual(len(sts_calls), 1)

    def test_rejects_wrong_active_account(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_aws_identity_and_region",
            extra_env={
                "MOCK_AWS_ACCOUNT_ID": "000000000000",
                "MOCK_AWS_CONFIGURED_REGION": "ap-east-1",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("672172129937", result.stderr)

    def test_rejects_mismatched_configured_region(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_aws_identity_and_region",
            extra_env={
                "MOCK_AWS_ACCOUNT_ID": "672172129937",
                "MOCK_AWS_CONFIGURED_REGION": "us-east-1",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ap-east-1", result.stderr)

    def test_accepts_empty_configured_region_as_no_consistency_check(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_aws_identity_and_region",
            extra_env={
                "MOCK_AWS_ACCOUNT_ID": "672172129937",
                "MOCK_AWS_CONFIGURED_REGION": "",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)


class KubernetesContextGuardTests(GuardsAndPathsFixture):
    """Step 1, proof 4: the canonical cluster reference, not the context
    label, controls Kubernetes acceptance."""

    def test_accepts_relabeled_context_pointing_at_the_right_cluster(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_kubernetes_context",
            extra_env={
                "MOCK_KUBE_CONTEXT": "totally-different-label",
                "MOCK_KUBE_CLUSTER_REF": "arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_correctly_labeled_context_pointing_at_the_wrong_cluster(self):
        result = self.run_bash(
            self.load_env_prefix("uat") + "verify_kubernetes_context",
            extra_env={
                "MOCK_KUBE_CONTEXT": "uat",
                "MOCK_KUBE_CLUSTER_REF": "arn:aws:eks:ap-east-1:672172129937:cluster/some-other-cluster",
            },
        )
        self.assertNotEqual(result.returncode, 0)


class EksAuthenticationModeGuardTests(GuardsAndPathsFixture):
    """Step 1, proof 5: EKS authentication accepts only API and
    API_AND_CONFIG_MAP."""

    def test_accepts_only_api_and_api_and_config_map(self):
        cases = (
            ("API", True),
            ("API_AND_CONFIG_MAP", True),
            ("CONFIG_MAP", False),
            ("", False),
        )
        for mode, expected_ok in cases:
            with self.subTest(mode=mode):
                result = self.run_bash(
                    self.load_env_prefix("uat") + "verify_eks_authentication_mode",
                    extra_env={"MOCK_EKS_AUTH_MODE": mode},
                )
                if expected_ok:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)


class BackendContractGuardTests(GuardsAndPathsFixture):
    """Step 1, proof 6: backend bucket, Region, expected owner, and
    selected state key come only from the loaded contract."""

    def test_uses_only_loaded_contract_values_and_invokes_backend_bootstrap_once(self):
        result = self.run_bash(
            self.load_env_prefix("uat")
            + 'validate_backend_contract_for_scope access-governance "$PWD/tf-dir"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [line for line in self.command_log_lines() if line.startswith("bootstrap-backend")]
        self.assertEqual(len(calls), 1)
        self.assertIn("--bucket sml-oms-uat-tfstate-672172129937", calls[0])
        self.assertIn("--region ap-east-1", calls[0])
        self.assertIn("--key oms/uat/access-governance.tfstate", calls[0])
        self.assertIn("--expected-bucket-owner 672172129937", calls[0])

    def test_rejects_unknown_scope_before_invoking_backend_bootstrap(self):
        result = self.run_bash(
            self.load_env_prefix("uat")
            + 'validate_backend_contract_for_scope not-a-real-scope "$PWD/tf-dir"'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_rejects_state_key_outside_the_state_prefix(self):
        result = self.run_bash(
            self.load_env_prefix("uat")
            + "TF_STATE_PREFIX=oms/other && "
            + 'validate_backend_contract_for_scope access-governance "$PWD/tf-dir"'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_rejects_state_key_containing_dot_dot(self):
        result = self.run_bash(
            self.load_env_prefix("uat")
            + 'ACCESS_GOVERNANCE_STATE_KEY="oms/uat/../escape.tfstate" && '
            + 'validate_backend_contract_for_scope access-governance "$PWD/tf-dir"'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])


class OrchestrationPathIsolationTests(GuardsAndPathsFixture):
    """Step 1, proof 7: .local/dev and .local/uat plans, generated inputs,
    locks, logs, and evidence never overlap."""

    def get_paths(self, environment):
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            f"initialize_orchestration_paths {environment} && "
            "printf 'LOCAL_ROOT=%s\\nLOCK_DIR=%s\\nPLAN_DIR=%s\\n"
            "GENERATED_DIR=%s\\nLOG_DIR=%s\\nEVIDENCE_DIR=%s\\n' "
            '"$LOCAL_ROOT" "$LOCK_DIR" "$PLAN_DIR" "$GENERATED_DIR" '
            '"$LOG_DIR" "$EVIDENCE_DIR"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        paths = {}
        for line in result.stdout.splitlines():
            key, _, value = line.partition("=")
            paths[key] = Path(value)
        return paths

    def test_dev_and_uat_local_paths_never_overlap(self):
        uat_paths = self.get_paths("uat")
        self.assertEqual(uat_paths["LOCAL_ROOT"], self.root / ".local" / "uat")
        self.assertEqual(
            uat_paths["LOCK_DIR"],
            self.root / ".local" / "uat" / "locks" / "orchestration.lock",
        )
        self.assertEqual(uat_paths["PLAN_DIR"], self.root / ".local" / "uat" / "plans")
        self.assertEqual(uat_paths["GENERATED_DIR"], self.root / ".local" / "uat" / "generated")
        self.assertEqual(uat_paths["EVIDENCE_DIR"], self.root / ".local" / "uat" / "evidence")
        self.assertNotIn(
            str(self.root / ".local" / "dev"), "\n".join(map(str, uat_paths.values()))
        )

        dev_paths = self.get_paths("dev")
        self.assertEqual(dev_paths["LOCAL_ROOT"], self.root / ".local" / "dev")
        self.assertNotIn(
            str(self.root / ".local" / "uat"), "\n".join(map(str, dev_paths.values()))
        )

    def test_rejects_a_symlinked_local_directory(self):
        (self.root / ".local").symlink_to(self.temporary.name)
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && initialize_orchestration_paths uat"
        )
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_a_symlinked_environment_directory(self):
        (self.root / ".local").mkdir()
        (self.root / ".local" / "uat").symlink_to(self.temporary.name)
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && initialize_orchestration_paths uat"
        )
        self.assertNotEqual(result.returncode, 0)


class OrchestrationLockTests(GuardsAndPathsFixture):
    """Step 1, proof 8: a lock for one environment does not block the
    other; a second lock for the same environment fails."""

    def test_lock_for_one_environment_does_not_block_the_other(self):
        dev_result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths dev && acquire_orchestration_lock && echo dev-locked"
        )
        self.assertEqual(dev_result.returncode, 0, dev_result.stderr)
        self.assertIn("dev-locked", dev_result.stdout)
        self.assertTrue((self.root / ".local" / "dev" / "locks" / "orchestration.lock").is_dir())

        uat_result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && acquire_orchestration_lock && echo uat-locked"
        )
        self.assertEqual(uat_result.returncode, 0, uat_result.stderr)
        self.assertIn("uat-locked", uat_result.stdout)

    def test_second_lock_for_the_same_environment_fails(self):
        first = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && acquire_orchestration_lock && echo first-locked"
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("first-locked", first.stdout)

        second = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && acquire_orchestration_lock"
        )
        self.assertNotEqual(second.returncode, 0)


class OrchestrationCleanupTests(GuardsAndPathsFixture):
    """Step 1, proof 9: cleanup removes only registered artifacts beneath
    the selected environment and preserves the original failure status."""

    def test_cleanup_removes_only_registered_artifacts(self):
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && "
            "acquire_orchestration_lock && "
            'touch "$PLAN_DIR/tracked.tfplan" && '
            'touch "$PLAN_DIR/untracked.tfplan" && '
            'register_orchestration_artifact "$PLAN_DIR/tracked.tfplan" && '
            "cleanup_orchestration_artifacts 0"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / ".local" / "uat" / "plans" / "tracked.tfplan").exists())
        self.assertTrue((self.root / ".local" / "uat" / "plans" / "untracked.tfplan").exists())
        self.assertFalse((self.root / ".local" / "uat" / "locks" / "orchestration.lock").is_dir())

    def test_cleanup_preserves_the_original_nonzero_status(self):
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && "
            "acquire_orchestration_lock && "
            'touch "$PLAN_DIR/tracked.tfplan" && '
            'register_orchestration_artifact "$PLAN_DIR/tracked.tfplan" ; '
            "(exit 42) ; original=$? ; "
            "cleanup_orchestration_artifacts \"$original\" ; exit $?"
        )
        self.assertEqual(result.returncode, 42)
        self.assertFalse((self.root / ".local" / "uat" / "plans" / "tracked.tfplan").exists())

    def test_cleanup_failure_makes_an_otherwise_successful_run_fail(self):
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && "
            "acquire_orchestration_lock && "
            'rmdir "$LOCK_DIR" && '
            "cleanup_orchestration_artifacts 0"
        )
        self.assertEqual(result.returncode, 1)

    def test_registration_outside_the_environment_root_is_rejected(self):
        result = self.run_bash(
            "source scripts/lib/orchestration-paths.sh && "
            "initialize_orchestration_paths uat && "
            'register_orchestration_artifact "/tmp/outside-artifact"'
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
