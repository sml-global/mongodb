import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EKS_MODULE_VARS = REPO_ROOT / "platform-prerequisites/terraform/modules/eks/variables.tf"
EKS_MODULE_MAIN = REPO_ROOT / "platform-prerequisites/terraform/modules/eks/main.tf"
EKS_PLATFORM_VARS = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/variables.tf"


class PrefixDelegationTests(unittest.TestCase):
    def test_addons_object_type_has_configuration_values_field(self):
        module_text = EKS_MODULE_VARS.read_text(encoding="utf-8")
        platform_text = EKS_PLATFORM_VARS.read_text(encoding="utf-8")
        self.assertIn("configuration_values = optional(string)", module_text)
        self.assertIn("configuration_values = optional(string)", platform_text)

    def test_addon_resource_passes_configuration_values(self):
        text = EKS_MODULE_MAIN.read_text(encoding="utf-8")
        self.assertIn("configuration_values", text)
        self.assertIn("each.value.configuration_values", text)


if __name__ == "__main__":
    unittest.main()
