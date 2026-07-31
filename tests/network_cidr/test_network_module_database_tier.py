import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
NETWORK_VARS = REPO_ROOT / "platform-prerequisites/terraform/modules/network/variables.tf"
NETWORK_MAIN = REPO_ROOT / "platform-prerequisites/terraform/modules/network/main.tf"
NETWORK_OUTPUTS = REPO_ROOT / "platform-prerequisites/terraform/modules/network/outputs.tf"


class DatabaseSubnetTierTests(unittest.TestCase):
    def test_database_subnet_cidrs_variable_exists_and_defaults_empty(self):
        text = NETWORK_VARS.read_text(encoding="utf-8")
        self.assertIn('variable "database_subnet_cidrs"', text)
        self.assertIn("default     = []", text)

    def test_database_subnet_resource_exists(self):
        text = NETWORK_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_subnet" "database"', text)

    def test_database_subnet_ids_output_exists(self):
        text = NETWORK_OUTPUTS.read_text(encoding="utf-8")
        self.assertIn('output "database_subnet_ids"', text)

    def test_eks_platform_wires_database_subnet_cidrs(self):
        eks_platform_main = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/main.tf"
        eks_platform_outputs = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/outputs.tf"
        self.assertIn("database_subnet_cidrs = var.database_subnet_cidrs", eks_platform_main.read_text(encoding="utf-8"))
        # Normalized to tolerate terraform fmt's column alignment (variable spacing), not just a single space.
        normalized_outputs = " ".join(eks_platform_outputs.read_text(encoding="utf-8").split())
        self.assertIn("database_subnet_ids = module.network.database_subnet_ids", normalized_outputs)


if __name__ == "__main__":
    unittest.main()
