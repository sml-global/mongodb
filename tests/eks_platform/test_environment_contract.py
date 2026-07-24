from pathlib import Path
import os
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "config" / "environment-schema" / "fragments" / "20-eks-platform.manifest"

EXPECTED_KEYS = {
    "EKS_KUBERNETES_VERSION",
    "EKS_AUTHENTICATION_MODE",
    "EKS_ENDPOINT_PUBLIC_ACCESS",
    "EKS_ENDPOINT_PRIVATE_ACCESS",
    "EKS_DELETION_PROTECTION",
    "EKS_VPC_CIDR",
    "EKS_CONNECTED_CIDR",
    "EKS_AZ_LAYOUT_MODE",
    "EKS_AZ_COUNT",
    "EKS_PRIVATE_SUBNET_A_CIDR",
    "EKS_PRIVATE_SUBNET_B_CIDR",
    "EKS_PRIVATE_SUBNET_C_CIDR",
    "EKS_PUBLIC_SUBNET_A_CIDR",
    "EKS_PUBLIC_SUBNET_B_CIDR",
    "EKS_PUBLIC_SUBNET_C_CIDR",
    "EKS_NAT_GATEWAY_COUNT",
    "EKS_NODE_INSTANCE_TYPE",
    "EKS_NODE_MIN_SIZE",
    "EKS_NODE_DESIRED_SIZE",
    "EKS_NODE_MAX_SIZE",
    "EKS_NODE_ROOT_VOLUME_GB",
    "EKS_SPOT_ENABLED",
    "EKS_EFS_ENABLED",
    "EKS_EFS_THROUGHPUT_MODE",
    "EKS_EFS_BACKUP_ENABLED",
    "EKS_BACKUP_RETENTION_DAYS",
    "EKS_ADDON_DELIVERY_MODE",
    "EKS_ENABLE_VPC_CNI",
    "EKS_ENABLE_COREDNS",
    "EKS_ENABLE_KUBE_PROXY",
    "EKS_ENABLE_EBS_CSI",
    "EKS_ENABLE_EFS_CSI",
    "EKS_ENABLE_POD_IDENTITY_AGENT",
    "EKS_ENABLE_CLUSTER_AUTOSCALER",
    "EKS_ENABLE_METRICS_SERVER",
}


class EksEnvironmentContractTests(unittest.TestCase):
    def run_bash(self, script):
        return subprocess.run(
            ["bash", "-lc", script],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            env=os.environ.copy(),
        )

    def test_fragment_contains_only_expected_eks_keys(self):
        self.assertTrue(SCHEMA_PATH.exists(), f"Missing fragment at {SCHEMA_PATH}")
        keys = set()
        for line in SCHEMA_PATH.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith("@constraint"):
                continue
            key, required, validator, immutable = stripped.split("|")
            self.assertIn(required, {"required", "optional"})
            self.assertTrue(key.startswith("EKS_"))
            keys.add(key)

        self.assertEqual(EXPECTED_KEYS, keys)

    def test_fragment_rejects_invalid_enum_and_bound_values(self):
        manifest = SCHEMA_PATH.read_text(encoding="utf-8")
        self.assertIn("EKS_AZ_LAYOUT_MODE|optional|fixed:one-per-az|-", manifest)
        self.assertIn("EKS_ADDON_DELIVERY_MODE|optional|enum:managed-addon,helm-fallback|-", manifest)
        self.assertIn("@constraint|cidr-contained-by|EKS_CONNECTED_CIDR,EKS_VPC_CIDR|-", manifest)
        self.assertIn("@constraint|cidr-nonoverlap|EKS_PRIVATE_SUBNET_A_CIDR,EKS_PRIVATE_SUBNET_B_CIDR,EKS_PRIVATE_SUBNET_C_CIDR,EKS_PUBLIC_SUBNET_A_CIDR,EKS_PUBLIC_SUBNET_B_CIDR,EKS_PUBLIC_SUBNET_C_CIDR|-", manifest)
        self.assertIn("@constraint|integer-order|EKS_NODE_MIN_SIZE,EKS_NODE_DESIRED_SIZE,EKS_NODE_MAX_SIZE|-", manifest)

    def test_composed_schema_has_no_duplicate_keys(self):
        script = f'''
set -euo pipefail
source "{REPO_ROOT / "scripts" / "lib" / "platform-env.sh"}"
_platform_env_schema_keys=()
_platform_env_schema_required=()
_platform_env_schema_validator=()
_platform_env_schema_immutable=()
_platform_env_schema_constraint_predicate=()
_platform_env_schema_constraint_keys=()
_platform_env_schema_constraint_argument=()

_platform_env_load_manifest "{REPO_ROOT / "config" / "environment-schema" / "base.manifest"}"
_platform_env_load_manifest "{REPO_ROOT / "config" / "environment-schema" / "fragments" / "20-eks-platform.manifest"}"
_platform_env_validate_composed_schema

printf '%s\n' "${{_platform_env_schema_keys[@]}}"
'''
        result = self.run_bash(script)
        self.assertEqual(0, result.returncode, result.stderr)
        keys = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertIn("ENVIRONMENT", keys)
        self.assertIn("EKS_PLATFORM_STATE_KEY", keys)


if __name__ == "__main__":
    unittest.main()
