import pathlib
import unittest

TF_DIR = pathlib.Path(__file__).parents[2] / "platform-prerequisites" / "terraform" / "mongodb"


class MongodbTerraformContractTests(unittest.TestCase):
    def test_checks_tf_exists(self):
        self.assertTrue((TF_DIR / "checks.tf").exists())

    def test_outputs_tf_declares_pbm_policy_id(self):
        content = (TF_DIR / "outputs.tf").read_text()
        self.assertIn('output "pbm_policy_id"', content)

    def test_variables_tf_declares_expected_account_id(self):
        content = (TF_DIR / "variables.tf").read_text()
        self.assertIn('variable "expected_account_id"', content)

    def test_sandbox_tfvars_uses_production_account(self):
        tfvars = (
            TF_DIR.parents[0] / "environments" / "sandbox" / "mongodb.tfvars"
        )
        self.assertIn("632674123947", tfvars.read_text())

    def test_checks_tf_has_operator_role_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "operator_role_is_provided"', content)
        self.assertIn("Direct IAM bypass is not allowed", content)

    def test_checks_tf_has_pbm_bucket_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "pbm_bucket_is_provided"', content)

    def test_checks_tf_has_kms_arn_check_block(self):
        content = (TF_DIR / "checks.tf").read_text()
        self.assertIn('check "cluster_kms_key_is_valid_arn"', content)

    def test_main_tf_grants_both_s3_and_kms_permissions(self):
        content = (TF_DIR / "main.tf").read_text()
        for action in ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]:
            self.assertIn(action, content, f"Missing S3 action: {action}")
        for action in ["kms:Decrypt", "kms:GenerateDataKey"]:
            self.assertIn(action, content, f"Missing KMS action: {action}")

    def test_no_hardcoded_iam_arns_in_module_hcl(self):
        for hcl_file in ["main.tf", "variables.tf", "outputs.tf", "versions.tf"]:
            content = (TF_DIR / hcl_file).read_text()
            self.assertNotIn("arn:aws:iam::", content, f"Hardcoded IAM ARN in {hcl_file}")

    def test_versions_tf_declares_correct_constraints(self):
        content = (TF_DIR / "versions.tf").read_text()
        self.assertIn(">= 1.10.0", content)
        self.assertIn(">= 6.0, < 7.0", content)


if __name__ == "__main__":
    unittest.main()
