import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROD_DIR = REPO_ROOT / "platform-prerequisites/terraform/environments/prod"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class ProdEnvironmentTfvarsTests(unittest.TestCase):
    def test_prod_eks_platform_tfvars_exists_with_expected_cidrs(self):
        path = PROD_DIR / "eks-platform.tfvars"
        self.assertTrue(path.is_file())
        parsed = validator.parse_environment_cidrs(path)
        self.assertEqual(parsed["vpc_cidr"], "10.200.0.0/17")
        self.assertIn("10.200.0.0/19", parsed["subnets"])
        self.assertIn("10.200.32.0/19", parsed["subnets"])
        self.assertIn("10.200.64.0/19", parsed["subnets"])
        self.assertIn("10.200.96.0/26", parsed["subnets"])
        self.assertIn("10.200.97.0/24", parsed["subnets"])

    def test_prod_targets_the_correct_account_and_region(self):
        text = (PROD_DIR / "eks-platform.tfvars").read_text(encoding="utf-8")
        self.assertIn('expected_account_id  = "632674123947"', text)
        self.assertIn('aws_region           = "ap-east-1"', text)

    def test_prod_enables_prefix_delegation(self):
        text = (PROD_DIR / "eks-platform.tfvars").read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)

    def test_prod_workload_identity_tfvars_exists(self):
        path = PROD_DIR / "workload-identity.tfvars"
        self.assertTrue(path.is_file())
        text = path.read_text(encoding="utf-8")
        self.assertIn('expected_account_id             = "632674123947"', text)

    def test_prod_does_not_overlap_with_dev_uat_sandbox(self):
        environments_dir = REPO_ROOT / "platform-prerequisites/terraform/environments"
        environments = {
            "prod": validator.parse_environment_cidrs(environments_dir / "prod" / "eks-platform.tfvars"),
            "dev": validator.parse_environment_cidrs(environments_dir / "dev" / "eks-platform.tfvars"),
            "uat": validator.parse_environment_cidrs(environments_dir / "uat" / "eks-platform.tfvars"),
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertEqual(conflicts, [])


if __name__ == "__main__":
    unittest.main()
