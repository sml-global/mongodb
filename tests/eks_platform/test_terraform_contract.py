import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULES_ROOT = REPO_ROOT / "platform-prerequisites" / "terraform" / "modules"
ROOT_STACK = REPO_ROOT / "platform-prerequisites" / "terraform" / "eks-platform"
ENV_ROOT = REPO_ROOT / "platform-prerequisites" / "terraform" / "environments"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class TerraformContractTests(unittest.TestCase):
    def test_provider_constraints_match_bounds(self):
        versions_tf = read(ROOT_STACK / "versions.tf")
        self.assertIn('required_version = ">= 1.10.0"', versions_tf)
        self.assertIn('version = ">= 6.0, < 7.0"', versions_tf)

    def test_root_stack_uses_only_aws_provider(self):
        terraform_text = "\n".join(
            read(path) for path in sorted(ROOT_STACK.glob("*.tf"))
        )
        self.assertNotIn('source  = "hashicorp/kubernetes"', terraform_text)
        self.assertNotIn('source  = "hashicorp/helm"', terraform_text)
        self.assertNotIn('source  = "fluxcd/flux"', terraform_text)
        self.assertNotRegex(terraform_text, r'provider\s+"kubernetes"\s*\{')
        self.assertNotRegex(terraform_text, r'provider\s+"helm"\s*\{')
        self.assertNotRegex(terraform_text, r'provider\s+"flux"\s*\{')

    def test_efs_module_prevent_destroy_is_enabled(self):
        efs_main = read(MODULES_ROOT / "efs" / "main.tf")
        self.assertIn("prevent_destroy = true", efs_main)

    def test_backup_module_has_vault_lock_resource(self):
        backup_main = read(MODULES_ROOT / "backup" / "main.tf")
        self.assertIn("resource \"aws_backup_vault_lock_configuration\" \"this\"", backup_main)
        self.assertIn("min_retention_days", backup_main)
        self.assertIn("max_retention_days", backup_main)

    def test_uat_backup_retention_floor_is_enforced(self):
        checks_tf = read(ROOT_STACK / "checks.tf")
        uat_tfvars = read(ENV_ROOT / "uat" / "eks-platform.tfvars")
        self.assertIn("backup_retention_days >= 35", checks_tf)

        match = re.search(r"^backup_retention_days\s*=\s*(\d+)\s*$", uat_tfvars, re.MULTILINE)
        self.assertIsNotNone(match)
        self.assertGreaterEqual(int(match.group(1)), 35)

    def test_single_non_secret_platform_contract_output(self):
        outputs_tf = read(ROOT_STACK / "outputs.tf")
        output_names = re.findall(r'^output\s+"([a-zA-Z0-9_]+)"\s*\{', outputs_tf, re.MULTILINE)
        self.assertEqual(output_names, ["platform_contract"])
        self.assertNotIn("sensitive = true", outputs_tf)

    def test_dev_tfvars_are_static_inputs_without_backend_keys(self):
        dev_tfvars = read(ENV_ROOT / "dev" / "eks-platform.tfvars")
        forbidden_backend_tokens = (
            "backend",
            "bucket",
            "dynamodb_table",
            "terraform_state",
            "state_key",
            "use_lockfile",
        )
        for token in forbidden_backend_tokens:
            with self.subTest(token=token):
                self.assertNotIn(token, dev_tfvars)

    def test_authentication_mode_is_api_only(self):
        checks_tf = read(ROOT_STACK / "checks.tf")
        dev_tfvars = read(ENV_ROOT / "dev" / "eks-platform.tfvars")
        uat_tfvars = read(ENV_ROOT / "uat" / "eks-platform.tfvars")

        self.assertIn('var.authentication_mode == "API"', checks_tf)
        self.assertIsNotNone(re.search(r'^authentication_mode\s*=\s*"API"\s*$', dev_tfvars, re.MULTILINE))
        self.assertIsNotNone(re.search(r'^authentication_mode\s*=\s*"API"\s*$', uat_tfvars, re.MULTILINE))

    def test_nat_mode_is_explicit_and_single_mode_is_consistent(self):
        network_vars_tf = read(MODULES_ROOT / "network" / "variables.tf")
        dev_tfvars = read(ENV_ROOT / "dev" / "eks-platform.tfvars")
        uat_tfvars = read(ENV_ROOT / "uat" / "eks-platform.tfvars")

        self.assertIn('var.nat_mode == "single"', network_vars_tf)
        self.assertIn('var.nat_mode == "one-per-az"', network_vars_tf)
        self.assertIsNotNone(re.search(r'^nat_mode\s*=\s*"single"\s*$', dev_tfvars, re.MULTILINE))
        self.assertIsNotNone(re.search(r'^nat_mode\s*=\s*"single"\s*$', uat_tfvars, re.MULTILINE))

    def test_load_balancer_controller_identity_is_conditional(self):
        iam_main_tf = read(MODULES_ROOT / "iam" / "main.tf")
        iam_outputs_tf = read(MODULES_ROOT / "iam" / "outputs.tf")
        root_main_tf = read(ROOT_STACK / "main.tf")

        self.assertIn("count              = var.enable_load_balancer_controller ? 1 : 0", iam_main_tf)
        self.assertIn("enable_load_balancer_controller = var.enable_load_balancer_controller", root_main_tf)
        self.assertIn("var.enable_load_balancer_controller ? aws_iam_role.lbc_role[0].arn : null", iam_outputs_tf)

    def test_addons_use_explicit_versions_not_latest(self):
        variables_tf = read(ROOT_STACK / "variables.tf")
        dev_tfvars = read(ENV_ROOT / "dev" / "eks-platform.tfvars")
        uat_tfvars = read(ENV_ROOT / "uat" / "eks-platform.tfvars")

        self.assertIn("addons[*].addon_version must be explicit and cannot be latest", variables_tf)
        self.assertNotRegex(dev_tfvars, r'addon_version\s*=\s*"latest"')
        self.assertNotRegex(uat_tfvars, r'addon_version\s*=\s*"latest"')


if __name__ == "__main__":
    unittest.main()