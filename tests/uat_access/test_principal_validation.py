import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "scripts" / "validate-uat-workforce-principals.sh"


class PrincipalValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.mock_bin = self.temp_path / "bin"
        self.mock_bin.mkdir()
        self.input_path = self.temp_path / "principals.json"
        self.output_path = self.temp_path / "generated.auto.tfvars.json"
        self.valid_principals = {
            "infra_admin_role_arn": self._role_arn("UATInfraAdminEA", "111111"),
            "application_developer_role_arn": self._role_arn(
                "UATApplicationDeveloper", "222222"
            ),
            "boomi_admin_role_arn": self._role_arn("UATBoomiAdmin", "333333"),
            "process_owner_role_arn": self._role_arn(
                "UATBoomiProcessOwner", "444444"
            ),
        }
        self._write_mock_aws()

    def tearDown(self):
        self.temp_dir.cleanup()

    @staticmethod
    def _role_arn(permission_set, suffix, account="672172129937"):
        return (
            f"arn:aws:iam::{account}:role/aws-reserved/sso.amazonaws.com/"
            f"ap-east-1/AWSReservedSSO_{permission_set}_{suffix}"
        )

    def _write_mock_aws(self):
        mock_aws = self.mock_bin / "aws"
        mock_aws.write_text(
            "#!/usr/bin/env bash\n"
            "printf 'ERROR: validator invoked AWS: %s\\n' \"$*\" >&2\n"
            "exit 99\n"
        )
        mock_aws.chmod(mock_aws.stat().st_mode | stat.S_IXUSR)

    def run_validator(self, principals):
        self.input_path.write_text(json.dumps(principals))
        env = os.environ.copy()
        env["PATH"] = f"{self.mock_bin}:{env['PATH']}"
        return subprocess.run(
            [
                "bash",
                str(VALIDATOR),
                "--input",
                str(self.input_path),
                "--output",
                str(self.output_path),
            ],
            cwd=REPO_ROOT,
            env=env,
            text=True,
            capture_output=True,
        )

    def assert_rejected(self, principals, error_text):
        result = self.run_validator(principals)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(error_text, result.stderr)
        self.assertNotIn("validator invoked AWS", result.stderr)
        self.assertFalse(self.output_path.exists())

    def test_valid_principals_generate_exact_eks_keys_without_aws(self):
        result = self.run_validator(self.valid_principals)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("validator invoked AWS", result.stderr)
        self.assertEqual(
            json.loads(self.output_path.read_text()),
            {
                key: self.valid_principals[key]
                for key in (
                    "infra_admin_role_arn",
                    "application_developer_role_arn",
                    "boomi_admin_role_arn",
                )
            },
        )
        self.assertEqual(stat.S_IMODE(self.output_path.stat().st_mode), 0o600)

    def test_missing_key_is_rejected(self):
        principals = dict(self.valid_principals)
        del principals["process_owner_role_arn"]

        self.assert_rejected(principals, "exactly four required keys")

    def test_extra_key_is_rejected(self):
        principals = dict(self.valid_principals, unexpected_role_arn="unused")

        self.assert_rejected(principals, "exactly four required keys")

    def test_wrong_account_is_rejected(self):
        principals = dict(self.valid_principals)
        principals["infra_admin_role_arn"] = self._role_arn(
            "UATInfraAdminEA", "111111", account="815402439714"
        )

        self.assert_rejected(principals, "account 672172129937")

    def test_wrong_permission_set_prefix_is_rejected(self):
        principals = dict(self.valid_principals)
        principals["boomi_admin_role_arn"] = self._role_arn(
            "UATBoomiReadOnly", "333333"
        )

        self.assert_rejected(principals, "UATBoomiAdmin")

    def test_duplicate_arn_is_rejected(self):
        principals = dict(self.valid_principals)
        principals["process_owner_role_arn"] = principals["boomi_admin_role_arn"]

        self.assert_rejected(principals, "unique")

    def test_non_aws_reserved_sso_role_is_rejected(self):
        principals = dict(self.valid_principals)
        principals["application_developer_role_arn"] = (
            "arn:aws:iam::672172129937:role/UATApplicationDeveloper"
        )

        self.assert_rejected(principals, "AWSReservedSSO_UATApplicationDeveloper")


if __name__ == "__main__":
    unittest.main()
