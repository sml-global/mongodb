import pathlib
import unittest

TF_DIR = pathlib.Path("platform-prerequisites/terraform/mongodb")


class MongodbTerraformContractTests(unittest.TestCase):
    def test_main_tf_exists(self):
        self.assertTrue((TF_DIR / "main.tf").exists())

    def test_outputs_tf_declares_pbm_policy_arn(self):
        content = (TF_DIR / "outputs.tf").read_text()
        self.assertIn('output "pbm_policy_arn"', content)

    def test_variables_tf_declares_expected_account_id(self):
        content = (TF_DIR / "variables.tf").read_text()
        self.assertIn('variable "expected_account_id"', content)

    def test_sandbox_tfvars_uses_production_account(self):
        tfvars = pathlib.Path(
            "platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars"
        )
        self.assertIn("632674123947", tfvars.read_text())


if __name__ == "__main__":
    unittest.main()
