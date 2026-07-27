import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PLATFORM_ENV = REPO_ROOT / "scripts" / "lib" / "platform-env.sh"
PLATFORM_GUARDS = REPO_ROOT / "scripts" / "lib" / "platform-guards.sh"
PROVISION_UAT_ACCESS = REPO_ROOT / "scripts" / "provision-uat-access.sh"


class PlatformEnvironmentTests(unittest.TestCase):
    SOURCE_PREFIX = f'source "{PLATFORM_ENV}" && source "{PLATFORM_GUARDS}" && '

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mock_bin = Path(self.temp_dir.name) / "bin"
        self.mock_bin.mkdir()
        self.command_log = Path(self.temp_dir.name) / "commands.log"
        self._write_mock(
            "aws",
            """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$#" -eq 8 && "$1" == "sts" && "$2" == "get-caller-identity" && "$3" == "--region" && "$5" == "--query" && "$6" == "Account" && "$7" == "--output" && "$8" == "text" ]]; then
  printf '%s\\n' "$MOCK_AWS_ACCOUNT_ID"
  exit 0
fi
if [[ "$#" -eq 3 && "$1" == "configure" && "$2" == "get" && "$3" == "region" ]]; then
  printf '%s\\n' "$MOCK_AWS_CONFIGURED_REGION"
  exit 0
fi
printf 'unsupported mock aws invocation: %s\\n' "$*" >&2
exit 64
""",
        )
        self._write_mock(
            "kubectl",
            """#!/usr/bin/env bash
printf 'kubectl %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$#" -eq 2 && "$1" == "config" && "$2" == "current-context" ]]; then
  printf '%s\\n' "$MOCK_KUBE_CONTEXT"
  exit 0
fi
if [[ "$#" -eq 5 && "$1" == "config" && "$2" == "view" && "$3" == "--minify" && "$4" == "-o" && "$5" == 'jsonpath={.contexts[0].context.cluster}' ]]; then
    printf '%s\\n' "$MOCK_KUBE_CLUSTER_REFERENCE"
    exit 0
fi
printf 'unsupported mock kubectl invocation: %s\\n' "$*" >&2
exit 64
""",
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_mock(self, name, content):
        mock_path = self.mock_bin / name
        mock_path.write_text(content)
        mock_path.chmod(mock_path.stat().st_mode | stat.S_IXUSR)

    def run_shell(
        self,
        command,
        account="672172129937",
        configured_region="ap-east-1",
        context="",
        cluster_reference="",
    ):
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_AWS_ACCOUNT_ID": account,
            "MOCK_AWS_CONFIGURED_REGION": configured_region,
            "MOCK_KUBE_CONTEXT": context,
            "MOCK_KUBE_CLUSTER_REFERENCE": cluster_reference,
            "MOCK_COMMAND_LOG": str(self.command_log),
        })
        return subprocess.run(
            ["bash", "-c", command], cwd=REPO_ROOT, env=env,
            text=True, capture_output=True,
        )

    def test_uat_account_succeeds(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_aws_identity_and_region"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log.read_text(),
            "aws sts get-caller-identity --region ap-east-1 --query Account --output text\n"
            "aws configure get region\n",
        )

    def test_dev_account_fails_closed(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_aws_identity_and_region",
            account="815402439714",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 672172129937", result.stderr)

    def test_unknown_environment_is_rejected(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env production"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepts only dev or uat", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_canonical_uat_kubernetes_context_succeeds(self):
        canonical_reference = (
            "arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context=canonical_reference,
            cluster_reference=canonical_reference,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log.read_text(),
            "kubectl config current-context\n"
            "kubectl config view --minify -o "
            "jsonpath={.contexts[0].context.cluster}\n",
        )

    def test_dev_kubernetes_cluster_reference_fails_closed(self):
        dev_reference = (
            "arn:aws:eks:ap-east-1:815402439714:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context=dev_reference,
            cluster_reference=dev_reference,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not target uat", result.stderr)

    def test_same_account_wrong_region_cluster_reference_fails_closed(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context=(
                "arn:aws:eks:us-east-1:672172129937:cluster/"
                "EKS-boomi-runtime-cluster"
            ),
            cluster_reference=(
                "arn:aws:eks:us-east-1:672172129937:cluster/"
                "EKS-boomi-runtime-cluster"
            ),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "expected 'arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster'",
            result.stderr,
        )
        self.assertEqual(
            self.command_log.read_text(),
            "kubectl config current-context\n"
            "kubectl config view --minify -o "
            "jsonpath={.contexts[0].context.cluster}\n",
        )

    def test_lookalike_cluster_reference_fails_closed(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context="uat-admin",
            cluster_reference=(
                "arn:aws:eks:ap-east-1:672172129937:cluster/"
                "EKS-boomi-runtime-cluster-lookalike"
            ),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "expected 'arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster'",
            result.stderr,
        )
        self.assertEqual(
            self.command_log.read_text(),
            "kubectl config current-context\n"
            "kubectl config view --minify -o "
            "jsonpath={.contexts[0].context.cluster}\n",
        )

    def test_alias_context_succeeds_when_cluster_reference_is_canonical(self):
        canonical_reference = (
            "arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context="uat-admin-alias",
            cluster_reference=canonical_reference,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log.read_text(),
            "kubectl config current-context\n"
            "kubectl config view --minify -o "
            "jsonpath={.contexts[0].context.cluster}\n",
        )

    def test_alias_context_fails_when_cluster_reference_is_not_canonical(self):
        result = self.run_shell(
            self.SOURCE_PREFIX + "load_platform_env uat && verify_kubernetes_context",
            context="uat-admin-alias",
            cluster_reference="local-uat-cluster",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "expected 'arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster'",
            result.stderr,
        )
        self.assertEqual(
            self.command_log.read_text(),
            "kubectl config current-context\n"
            "kubectl config view --minify -o "
            "jsonpath={.contexts[0].context.cluster}\n",
        )


class ProvisionUatAccessForwardingTests(unittest.TestCase):
    """Regression tests for the Task 5 compatibility wrapper.

    scripts/provision-uat-access.sh no longer owns any account, backend,
    Terraform, kubectl, lock, plan, generated-file, or cleanup logic of its
    own; it only validates its old scope grammar and forwards to
    `scripts/provision.sh --env uat <access-governance|eks-access>`. These
    tests stub out provision.sh itself (logging only its argv) so they
    exercise the wrapper's own argument-mapping/forwarding logic in
    isolation. Full end-to-end coverage of the real unified provisioning
    behavior (backend bootstrap, Terraform plan/apply, locking, cleanup,
    identity/context guards) lives in
    tests/environment_orchestration/test_access_dispatch.py, which tests the
    real access-scopes.sh package directly.
    """

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.test_root = self.temp_path / "repository"
        self.provision_uat_access = (
            self.test_root / "scripts" / "provision-uat-access.sh"
        )
        self.stub_provision = self.test_root / "scripts" / "provision.sh"
        self.invocation_log = self.temp_path / "invocations.log"
        (self.test_root / "scripts").mkdir(parents=True)
        shutil.copy2(PROVISION_UAT_ACCESS, self.provision_uat_access)
        self.provision_uat_access.chmod(
            self.provision_uat_access.stat().st_mode | stat.S_IXUSR
        )
        self._write_stub_provision(exit_code=0)

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_stub_provision(self, exit_code):
        self.stub_provision.write_text(
            "#!/usr/bin/env bash\n"
            'printf \'%s\\n\' "$*" >> "$MOCK_INVOCATION_LOG"\n'
            f"exit {exit_code}\n"
        )
        self.stub_provision.chmod(
            self.stub_provision.stat().st_mode | stat.S_IXUSR
        )

    def run_wrapper(self, *arguments):
        env = os.environ.copy()
        env["PATH"] = f"{self.test_root / 'scripts'}:{env['PATH']}"
        env["MOCK_INVOCATION_LOG"] = str(self.invocation_log)
        return subprocess.run(
            ["bash", str(self.provision_uat_access), *arguments],
            cwd=self.test_root,
            env=env,
            text=True,
            capture_output=True,
        )

    def invocations(self):
        if not self.invocation_log.exists():
            return []
        return self.invocation_log.read_text().splitlines()

    def test_governance_forwards_to_unified_access_governance(self):
        result = self.run_wrapper("governance")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "DEPRECATED: use scripts/provision.sh --env uat "
            "<access-governance|eks-access>",
            result.stderr,
        )
        self.assertEqual(self.invocations(), ["--env uat access-governance"])

    def test_eks_access_forwards_to_unified_eks_access(self):
        result = self.run_wrapper("eks-access")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.invocations(), ["--env uat eks-access"])

    def test_all_forwards_governance_then_eks_access_not_unified_all(self):
        result = self.run_wrapper("all")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.invocations(),
            ["--env uat access-governance", "--env uat eks-access"],
        )

    def test_auto_approve_is_appended_to_every_forwarded_command(self):
        result = self.run_wrapper("all", "--auto-approve")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.invocations(),
            [
                "--env uat access-governance --auto-approve",
                "--env uat eks-access --auto-approve",
            ],
        )

    def test_governance_scope_accepts_auto_approve(self):
        result = self.run_wrapper("governance", "--auto-approve")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.invocations(), ["--env uat access-governance --auto-approve"]
        )

    def test_unknown_scope_is_rejected_before_forwarding(self):
        result = self.run_wrapper("bogus-scope")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_unknown_argument_is_rejected_before_forwarding(self):
        result = self.run_wrapper("governance", "--not-a-real-flag")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_missing_scope_argument_is_rejected_before_forwarding(self):
        result = self.run_wrapper()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_extra_trailing_argument_is_rejected_before_forwarding(self):
        result = self.run_wrapper("governance", "extra")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])

    def test_all_stops_after_governance_failure_and_never_runs_eks_access(self):
        self._write_stub_provision(exit_code=42)

        result = self.run_wrapper("all")

        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.invocations(), ["--env uat access-governance"])

    def test_exit_code_from_forwarded_command_propagates(self):
        self._write_stub_provision(exit_code=17)

        result = self.run_wrapper("governance")

        self.assertEqual(result.returncode, 17)


if __name__ == "__main__":
    unittest.main()