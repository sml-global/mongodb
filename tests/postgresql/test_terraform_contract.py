import pathlib
import unittest

TF_DIR = pathlib.Path(__file__).parents[2] / "platform-prerequisites" / "terraform" / "postgresql-core"


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
        self.assertIn("cluster_kms_key_arn", content)
        self.assertIn("vpc_id", content)
        self.assertIn("database_subnet_ids", content)

    def test_checks_tf_has_kms_key_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "cluster_kms_key_is_valid_arn"', content)

    def test_main_tf_provisions_aurora_via_shared_module(self):
        content = (TF_DIR / "main.tf").read_text()
        self.assertIn('module "postgresql"', content)
        self.assertIn("cluster_kms_key_arn", content)

    def test_main_tf_has_no_cnpg_backup_iam_policy(self):
        # Issue #100: this root previously carried a CNPG-shaped IAM policy
        # resource (S3 backup bucket + operator role access) that was never
        # usable for Aurora -- Aurora has its own native backup mechanism
        # (backup_retention_period/preferred_backup_window in
        # modules/postgresql) and needs no S3 bucket or operator IAM role.
        content = (TF_DIR / "main.tf").read_text()
        self.assertNotIn("aws_iam_role_policy", content)
        self.assertNotIn("cnpg_backup_bucket_name", content)
        self.assertNotIn("postgresql_operator_iam_role_arn", content)

    def test_outputs_tf_exports_cluster_identifier(self):
        content = (TF_DIR / "outputs.tf").read_text()
        self.assertIn('output "cluster_identifier"', content)


if __name__ == "__main__":
    unittest.main()
