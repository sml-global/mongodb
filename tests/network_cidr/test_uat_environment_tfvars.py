import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
UAT_TFVARS = REPO_ROOT / "platform-prerequisites/terraform/environments/uat/eks-platform.tfvars"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class UatEnvironmentTfvarsTests(unittest.TestCase):
    def test_uat_uses_new_cidr_scheme(self):
        parsed = validator.parse_environment_cidrs(UAT_TFVARS)
        self.assertEqual(parsed["vpc_cidr"], "10.200.216.0/21")
        self.assertIn("10.200.216.0/23", parsed["subnets"])
        self.assertIn("10.200.218.0/23", parsed["subnets"])
        self.assertIn("10.200.220.0/26", parsed["subnets"])
        self.assertIn("10.200.220.128/25", parsed["subnets"])
        self.assertIn("10.200.221.0/25", parsed["subnets"])

    def test_uat_enables_prefix_delegation(self):
        text = UAT_TFVARS.read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)

    def test_uat_account_and_region_unchanged(self):
        text = UAT_TFVARS.read_text(encoding="utf-8")
        self.assertIn('expected_account_id  = "672172129937"', text)
        self.assertIn('aws_region           = "ap-east-1"', text)


if __name__ == "__main__":
    unittest.main()
