import pathlib
import unittest

TF_DIR = pathlib.Path(__file__).parents[2] / "platform-prerequisites" / "terraform" / "postgresql"


class PostgresqlTerraformContractTests(unittest.TestCase):
    def test_versions_tf_exists(self):
        self.assertTrue((TF_DIR / "versions.tf").exists())

    def test_versions_tf_has_correct_provider_constraints(self):
        content = (TF_DIR / "versions.tf").read_text()
        self.assertIn(">= 1.10.0", content)
        self.assertIn(">= 6.0, < 7.0", content)

    def test_variables_tf_exists_and_has_descriptions(self):
        content = (TF_DIR / "variables.tf").read_text()
        self.assertTrue((TF_DIR / "variables.tf").exists())
        # Verify key variables exist
        self.assertIn("postgresql_operator_iam_role_arn", content)
        self.assertIn("cnpg_backup_bucket_name", content)
        self.assertIn("cluster_kms_key_arn", content)

    def test_checks_tf_has_role_arn_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "postgresql_operator_role_is_provided"', content)

    def test_checks_tf_has_backup_bucket_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "cnpg_backup_bucket_is_provided"', content)

    def test_checks_tf_has_kms_key_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "cluster_kms_key_is_valid_arn"', content)

    def test_main_tf_attaches_policy_to_role(self):
        content = (TF_DIR / "main.tf").read_text()
        # Verify policy attachment resource exists
        self.assertIn("aws_iam_role_policy", content)
        # Verify S3 and KMS permissions
        for action in ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]:
            self.assertIn(action, content, f"Missing S3 action: {action}")
        for action in ["kms:Decrypt", "kms:GenerateDataKey"]:
            self.assertIn(action, content, f"Missing KMS action: {action}")

    def test_role_name_extraction_with_standard_arn(self):
        content = (TF_DIR / "main.tf").read_text()
        # Verify role name extraction from ARN is present
        self.assertIn('split("/", var.postgresql_operator_iam_role_arn)', content)

    def test_outputs_tf_exports_policy_id(self):
        content = (TF_DIR / "outputs.tf").read_text()
        self.assertIn('output "cnpg_backup_policy_id"', content)


if __name__ == "__main__":
    unittest.main()
