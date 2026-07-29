import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"
ENVIRONMENTS_DIR = REPO_ROOT / "platform-prerequisites" / "terraform" / "environments"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class CidrAllocationTests(unittest.TestCase):
    def test_parse_environment_cidrs_extracts_vpc_and_subnets(self):
        dev_tfvars = ENVIRONMENTS_DIR / "dev" / "eks-platform.tfvars"
        parsed = validator.parse_environment_cidrs(dev_tfvars)
        self.assertTrue(parsed["vpc_cidr"].startswith("10."))
        self.assertGreaterEqual(len(parsed["subnets"]), 2)

    def test_no_overlaps_across_current_dev_uat_sandbox(self):
        environments = {
            "dev": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "dev" / "eks-platform.tfvars"),
            "uat": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "uat" / "eks-platform.tfvars"),
            "sandbox": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "sandbox" / "eks-platform.tfvars"),
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertEqual(conflicts, [])

    def test_detects_overlap_when_present(self):
        environments = {
            "a": {"vpc_cidr": "10.0.0.0/24", "subnets": ["10.0.0.0/25"]},
            "b": {"vpc_cidr": "10.0.0.0/24", "subnets": ["10.0.0.128/25"]},
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertTrue(any("a" in c and "b" in c for c in conflicts))

    def test_detects_subnet_not_contained_in_own_vpc(self):
        environments = {
            "a": {"vpc_cidr": "10.0.0.0/28", "subnets": ["10.0.1.0/28"]},
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertTrue(any("not contained" in c for c in conflicts))


if __name__ == "__main__":
    unittest.main()
