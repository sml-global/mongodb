import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PLATFORM_ENV = REPO_ROOT / "scripts" / "lib" / "platform-env.sh"


class PlatformEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mock_bin = Path(self.temp_dir.name) / "bin"
        self.mock_bin.mkdir()
        self.command_log = Path(self.temp_dir.name) / "commands.log"
        self._write_mock(
            "aws",
            """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$#" -eq 6 && "$1" == "sts" && "$2" == "get-caller-identity" && "$3" == "--query" && "$4" == "Account" && "$5" == "--output" && "$6" == "text" ]]; then
  printf '%s\\n' "$MOCK_AWS_ACCOUNT_ID"
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
        context="",
        cluster_reference="",
    ):
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_AWS_ACCOUNT_ID": account,
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
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_aws_identity'
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log.read_text(),
            "aws sts get-caller-identity --query Account --output text\n",
        )

    def test_dev_account_fails_closed(self):
        result = self.run_shell(
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_aws_identity',
            account="815402439714",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 672172129937", result.stderr)

    def test_unknown_environment_is_rejected(self):
        result = self.run_shell(
            f'source "{PLATFORM_ENV}" && load_platform_env production'
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepts only uat", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_canonical_uat_kubernetes_context_succeeds(self):
        canonical_reference = (
            "arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        result = self.run_shell(
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
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

    def test_same_account_wrong_region_cluster_reference_fails_closed(self):
        result = self.run_shell(
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
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
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
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
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
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
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
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


if __name__ == "__main__":
    unittest.main()