import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PLATFORM_ENV = REPO_ROOT / "scripts" / "lib" / "platform-env.sh"
PROVISION_UAT_ACCESS = REPO_ROOT / "scripts" / "provision-uat-access.sh"
PRINCIPAL_INPUT = (
    REPO_ROOT / "config" / "environments" / "uat-workforce-principals.json"
)
GENERATED_TFVARS = (
    REPO_ROOT
    / "platform-prerequisites"
    / "terraform"
    / "eks-access"
    / "generated.auto.tfvars.json"
)


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

    def test_dev_kubernetes_cluster_reference_fails_closed(self):
        dev_reference = (
            "arn:aws:eks:ap-east-1:815402439714:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        result = self.run_shell(
            f'source "{PLATFORM_ENV}" && load_platform_env uat && verify_kubernetes_context',
            context=dev_reference,
            cluster_reference=dev_reference,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not target UAT", result.stderr)

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


class UATAccessProvisioningTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mock_bin = Path(self.temp_dir.name) / "bin"
        self.mock_bin.mkdir()
        self.command_log = Path(self.temp_dir.name) / "commands.log"
        self.real_jq = shutil.which("jq")
        if self.real_jq is None:
            self.skipTest("jq is required by the offline principal validator")
        self.saved_files = {
            path: path.read_bytes() if path.exists() else None
            for path in (PRINCIPAL_INPUT, GENERATED_TFVARS)
        }
        self._write_mock(
            "aws",
            """#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$1 $2" == "sts get-caller-identity" ]]; then
  printf '%s\n' "$MOCK_AWS_ACCOUNT_ID"
  exit 0
fi
if [[ "$1 $2" == "s3api head-bucket" || "$1 $2" == "s3api head-object" ]]; then
  exit 0
fi
printf 'unsupported mock aws invocation: %s\n' "$*" >&2
exit 64
""",
        )
        self._write_mock(
            "kubectl",
            """#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$1 $2" == "config current-context" ]]; then
  printf '%s\n' "$MOCK_KUBE_CONTEXT"
  exit 0
fi
if [[ "$1 $2 $3 $4 $5" == "config view --minify -o jsonpath={.contexts[0].context.cluster}" ]]; then
  printf '%s\n' "$MOCK_KUBE_CLUSTER_REFERENCE"
  exit 0
fi
exit 64
""",
        )
        self._write_mock(
            "terraform",
            """#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ " $* " == *" plan "* && "${MOCK_TERRAFORM_FAIL_PLAN:-false}" == "true" ]]; then
    exit 42
fi
exit 0
""",
        )
        self._write_mock(
            "rg",
            """#!/usr/bin/env bash
printf 'rg %s\n' "$*" >> "$MOCK_COMMAND_LOG"
exit 0
""",
        )
        self._write_mock(
            "jq",
            """#!/usr/bin/env bash
printf 'jq %s\n' "$*" >> "$MOCK_COMMAND_LOG"
exec "$REAL_JQ" "$@"
""",
        )
        self.write_valid_principals()

    def tearDown(self):
        for path, content in self.saved_files.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
        self.temp_dir.cleanup()

    def _write_mock(self, name, content):
        mock_path = self.mock_bin / name
        mock_path.write_text(content)
        mock_path.chmod(mock_path.stat().st_mode | stat.S_IXUSR)

    @staticmethod
    def role_arn(permission_set, suffix):
        return (
            "arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/"
            f"ap-east-1/AWSReservedSSO_{permission_set}_{suffix}"
        )

    def write_valid_principals(self):
        PRINCIPAL_INPUT.write_text(json.dumps({
            "infra_admin_role_arn": self.role_arn("UATInfraAdminEA", "111111"),
            "application_developer_role_arn": self.role_arn(
                "UATApplicationDeveloper", "222222"
            ),
            "boomi_admin_role_arn": self.role_arn("UATBoomiAdmin", "333333"),
            "process_owner_role_arn": self.role_arn(
                "UATBoomiProcessOwner", "444444"
            ),
        }))

    def run_provision(
        self,
        *arguments,
        account="672172129937",
        terraform_fail_plan=False,
    ):
        canonical_context = (
            "arn:aws:eks:ap-east-1:672172129937:cluster/"
            "EKS-boomi-runtime-cluster"
        )
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_AWS_ACCOUNT_ID": account,
            "MOCK_KUBE_CONTEXT": canonical_context,
            "MOCK_KUBE_CLUSTER_REFERENCE": canonical_context,
            "MOCK_COMMAND_LOG": str(self.command_log),
            "MOCK_TERRAFORM_FAIL_PLAN": str(terraform_fail_plan).lower(),
            "REAL_JQ": self.real_jq,
        })
        return subprocess.run(
            ["bash", str(PROVISION_UAT_ACCESS), *arguments],
            cwd=REPO_ROOT,
            env=env,
            text=True,
            capture_output=True,
        )

    def command_lines(self):
        if not self.command_log.exists():
            return []
        return self.command_log.read_text().splitlines()

    def assert_ordered_fragments(self, fragments):
        lines = self.command_lines()
        positions = []
        for fragment in fragments:
            matches = [index for index, line in enumerate(lines) if fragment in line]
            self.assertTrue(matches, f"missing {fragment!r} in {lines!r}")
            positions.append(matches[0])
        self.assertEqual(positions, sorted(positions), lines)

    def assert_no_forbidden_invocations(self):
        invocations = "\n".join(self.command_lines()).lower()
        for forbidden in (
            "sso-admin",
            "identitystore",
            "organizations",
            "sts assume-role",
            "--profile",
            "815402439714",
            "provision-platform-prereq",
            "provision.sh",
        ):
            self.assertNotIn(forbidden, invocations)

    def test_governance_orders_identity_backend_format_validate_plan_apply(self):
        result = self.run_provision("governance")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_ordered_fragments([
            "aws sts get-caller-identity --query Account --output text",
            "aws s3api head-bucket --bucket sml-oms-uat-tfstate-672172129937",
            "terraform -chdir=",
            " fmt -check -recursive",
            " validate",
            " plan -input=false -out=uat-access.tfplan",
            " apply -input=false uat-access.tfplan",
        ])
        self.assert_no_forbidden_invocations()

    def test_eks_access_orders_all_preflight_before_backend_and_terraform(self):
        result = self.run_provision("eks-access")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(GENERATED_TFVARS.exists())
        self.assert_ordered_fragments([
            "aws sts get-caller-identity --query Account --output text",
            "kubectl config current-context",
            "kubectl config view --minify",
            "jq -e",
            "aws s3api head-bucket --bucket sml-oms-uat-tfstate-672172129937",
            " fmt -check -recursive",
            " validate",
            " plan -input=false -out=uat-access.tfplan",
            " apply -input=false uat-access.tfplan",
        ])
        self.assert_no_forbidden_invocations()

    def test_all_completes_governance_before_eks_access(self):
        result = self.run_provision("all")

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_lines()
        governance_apply = next(
            index for index, line in enumerate(lines)
            if "access-governance apply -input=false uat-access.tfplan" in line
        )
        eks_identity = next(
            index for index, line in enumerate(lines[governance_apply + 1 :], governance_apply + 1)
            if "aws sts get-caller-identity" in line
        )
        eks_apply = next(
            index for index, line in enumerate(lines)
            if "eks-access apply -input=false uat-access.tfplan" in line
        )
        self.assertLess(governance_apply, eks_identity)
        self.assertLess(eks_identity, eks_apply)

    def test_auto_approve_applies_saved_plans_without_invalid_flag(self):
        result = self.run_provision("all", "--auto-approve")

        self.assertEqual(result.returncode, 0, result.stderr)
        apply_lines = [line for line in self.command_lines() if " apply " in line]
        self.assertEqual(len(apply_lines), 2, apply_lines)
        self.assertTrue(all(line.endswith("apply -input=false uat-access.tfplan") for line in apply_lines))
        self.assertTrue(all("auto-approve" not in line for line in apply_lines))

    def test_failed_plan_is_never_applied(self):
        result = self.run_provision("governance", terraform_fail_plan=True)

        self.assertEqual(result.returncode, 42)
        self.assertTrue(any(" plan " in line for line in self.command_lines()))
        self.assertFalse(any(" apply " in line for line in self.command_lines()))

    def test_wrong_account_causes_no_backend_terraform_or_generated_output(self):
        GENERATED_TFVARS.write_text("stale output")

        result = self.run_provision("eks-access", account="815402439714")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 672172129937", result.stderr)
        self.assertEqual(
            self.command_lines(),
            ["aws sts get-caller-identity --query Account --output text"],
        )
        self.assertEqual(GENERATED_TFVARS.read_text(), "stale output")

    def test_missing_principals_removes_stale_output_and_stops_before_backend(self):
        PRINCIPAL_INPUT.unlink()
        GENERATED_TFVARS.write_text("stale output")

        result = self.run_provision("eks-access")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(GENERATED_TFVARS.exists())
        self.assertFalse(any("s3api" in line for line in self.command_lines()))
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_invalid_principals_remove_stale_output_and_stop_before_backend(self):
        PRINCIPAL_INPUT.write_text("{}")
        GENERATED_TFVARS.write_text("stale output")

        result = self.run_provision("eks-access")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(GENERATED_TFVARS.exists())
        self.assertFalse(any("s3api" in line for line in self.command_lines()))
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_cli_rejects_all_uncontracted_forms_without_invocation(self):
        for arguments in (
            (),
            ("unknown",),
            ("governance", "extra"),
            ("--auto-approve", "governance"),
            ("governance", "--auto-approve", "--auto-approve"),
        ):
            with self.subTest(arguments=arguments):
                self.command_log.unlink(missing_ok=True)
                result = self.run_provision(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.command_lines(), [])


if __name__ == "__main__":
    unittest.main()