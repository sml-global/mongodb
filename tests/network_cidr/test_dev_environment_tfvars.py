import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEV_TFVARS = REPO_ROOT / "platform-prerequisites/terraform/environments/dev/eks-platform.tfvars"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class DevEnvironmentTfvarsTests(unittest.TestCase):
    def test_dev_uses_new_cidr_scheme_with_two_azs(self):
        parsed = validator.parse_environment_cidrs(DEV_TFVARS)
        self.assertEqual(parsed["vpc_cidr"], "10.200.208.0/21")
        self.assertIn("10.200.208.0/23", parsed["subnets"])
        self.assertIn("10.200.210.0/23", parsed["subnets"])
        self.assertIn("10.200.212.0/26", parsed["subnets"])
        self.assertIn("10.200.212.64/26", parsed["subnets"])

    def test_dev_has_no_database_subnet_tier(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertNotIn("database_subnet_cidrs", text)

    def test_dev_still_uses_two_availability_zones(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertIn('availability_zones   = ["ap-east-1a", "ap-east-1b"]', text)

    def test_dev_enables_prefix_delegation(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)


if __name__ == "__main__":
    unittest.main()
