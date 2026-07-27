#!/usr/bin/env python3
"""
tests/signoz/test_gitops_manifests.py

Test GitOps manifest validation for SigNoz.
Tests: 12

- test_kustomize_build_base_succeeds
- test_kustomize_build_uat_overlay_succeeds
- test_helmrepository_uses_correct_signoz_chart_url
- test_helmrelease_signoz_uses_pinned_version
- test_helmrelease_has_no_hardcoded_clickhouse_password
- test_helmrelease_clickhouse_password_uses_secret_ref
- test_helmrelease_uses_gp3_storage_class
- test_k8s_infra_helmrelease_exists
- test_k8s_infra_uses_otel_collector_endpoint
- test_uat_overlay_patches_cluster_name
- test_uat_overlay_exists
- test_namespace_manifest_exists
"""

import unittest
import subprocess
import yaml
from pathlib import Path


class TestSignozGitOpsManifests(unittest.TestCase):
    """Validate SigNoz GitOps manifests."""

    @classmethod
    def setUpClass(cls):
        """Load manifest files."""
        cls.base_dir = Path(__file__).parent.parent.parent / "gitops" / "signoz" / "base"
        cls.overlays_uat_dir = cls.base_dir.parent / "overlays" / "uat"
        
        # Load base manifests
        cls.helmreleases_path = cls.base_dir / "helmreleases.yaml"
        cls.helmrelease_k8s_infra_path = cls.base_dir / "helmrelease-k8s-infra.yaml"
        cls.helmrepositories_path = cls.base_dir / "helmrepositories.yaml"
        cls.namespace_path = cls.base_dir / "namespace.yaml"
        cls.kustomization_base_path = cls.base_dir / "kustomization.yaml"
        
        # Load overlay manifests
        cls.kustomization_uat_path = cls.overlays_uat_dir / "kustomization.yaml"
        cls.helmrelease_patch_uat_path = cls.overlays_uat_dir / "helmrelease-patch.yaml"

        # Load YAML content
        cls.helmreleases_content = cls._load_yaml_file(cls.helmreleases_path)
        cls.helmrelease_k8s_infra_content = cls._load_yaml_file(cls.helmrelease_k8s_infra_path)
        cls.helmrepositories_content = cls._load_yaml_file(cls.helmrepositories_path)
        cls.namespace_content = cls._load_yaml_file(cls.namespace_path)

    @staticmethod
    def _load_yaml_file(path):
        """Load YAML file content."""
        if not path.exists():
            return None
        with open(path, 'r') as f:
            return yaml.safe_load(f)

    @staticmethod
    def _load_raw_file(path):
        """Load raw file content as text."""
        if not path.exists():
            return ""
        with open(path, 'r') as f:
            return f.read()

    def test_kustomize_build_base_succeeds(self):
        """kustomize build on base directory must succeed."""
        result = subprocess.run(
            ["kustomize", "build", str(self.base_dir)],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0,
            f"kustomize build base failed: {result.stderr}")

    def test_kustomize_build_uat_overlay_succeeds(self):
        """kustomize build on UAT overlay must succeed."""
        result = subprocess.run(
            ["kustomize", "build", str(self.overlays_uat_dir)],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0,
            f"kustomize build uat overlay failed: {result.stderr}")

    def test_helmrepository_uses_correct_signoz_chart_url(self):
        """HelmRepository must reference official SigNoz chart."""
        self.assertIsNotNone(self.helmrepositories_content,
            "helmrepositories.yaml not found")
        url = self.helmrepositories_content.get("spec", {}).get("url", "")
        self.assertIn("signoz", url.lower(),
            f"HelmRepository URL does not reference SigNoz: {url}")

    def test_helmrelease_signoz_uses_pinned_version(self):
        """HelmRelease must use a pinned SigNoz chart version."""
        self.assertIsNotNone(self.helmreleases_content,
            "helmreleases.yaml not found")
        version = self.helmreleases_content.get("spec", {}).get("chart", {}).get("spec", {}).get("version", "")
        self.assertRegex(version, r"^\d+\.\d+\.\d+$",
            f"Chart version must be pinned (semver): {version}")

    def test_helmrelease_has_no_hardcoded_clickhouse_password(self):
        """HelmRelease must NOT contain hardcoded ClickHouse password."""
        content = self._load_raw_file(self.helmreleases_path)
        # Check for both the placeholder and literal string password
        self.assertNotIn("CHANGE_ME", content,
            "HelmRelease contains CHANGE_ME placeholder")
        self.assertNotIn('password: "', content,
            "HelmRelease contains hardcoded password (literal string)")

    def test_helmrelease_clickhouse_password_uses_secret_ref(self):
        """HelmRelease must reference ClickHouse password from Secret."""
        content = self._load_raw_file(self.helmreleases_path)
        self.assertIn("secretKeyRef", content,
            "ClickHouse password must use secretKeyRef")
        self.assertIn("signoz-clickhouse", content,
            "ClickHouse password must reference signoz-clickhouse Secret")
        self.assertIn("key: password", content,
            "ClickHouse password must reference 'password' key in Secret")

    def test_helmrelease_uses_gp3_storage_class(self):
        """HelmRelease must use gp3-mongodb StorageClass."""
        self.assertIsNotNone(self.helmreleases_content,
            "helmreleases.yaml not found")
        storage_class = self.helmreleases_content.get("spec", {}).get("values", {}).get("global", {}).get("storageClass", "")
        self.assertEqual(storage_class, "gp3-mongodb",
            f"StorageClass must be gp3-mongodb, got: {storage_class}")

    def test_k8s_infra_helmrelease_exists(self):
        """k8s-infra HelmRelease must exist."""
        self.assertTrue(self.helmrelease_k8s_infra_path.exists(),
            f"helmrelease-k8s-infra.yaml not found: {self.helmrelease_k8s_infra_path}")
        self.assertIsNotNone(self.helmrelease_k8s_infra_content,
            "helmrelease-k8s-infra.yaml could not be parsed")

    def test_k8s_infra_uses_otel_collector_endpoint(self):
        """k8s-infra must configure OTEL collector endpoint."""
        self.assertIsNotNone(self.helmrelease_k8s_infra_content,
            "helmrelease-k8s-infra.yaml not found")
        otel_endpoint = self.helmrelease_k8s_infra_content.get("spec", {}).get("values", {}).get("otelCollectorEndpoint", "")
        self.assertTrue(len(otel_endpoint) > 0,
            "otelCollectorEndpoint must be configured")

    def test_uat_overlay_patches_cluster_name(self):
        """UAT overlay must patch clusterName to EKS-uat-cluster."""
        patch_content = self._load_raw_file(self.helmrelease_patch_uat_path)
        self.assertIn("EKS-uat-cluster", patch_content,
            "UAT overlay must patch clusterName to EKS-uat-cluster")
        self.assertIn("clusterName", patch_content,
            "UAT overlay must patch clusterName field")

    def test_uat_overlay_exists(self):
        """UAT overlay directory and files must exist."""
        self.assertTrue(self.overlays_uat_dir.exists(),
            f"UAT overlay directory not found: {self.overlays_uat_dir}")
        self.assertTrue(self.kustomization_uat_path.exists(),
            f"UAT kustomization.yaml not found: {self.kustomization_uat_path}")
        self.assertTrue(self.helmrelease_patch_uat_path.exists(),
            f"UAT helmrelease-patch.yaml not found: {self.helmrelease_patch_uat_path}")

    def test_namespace_manifest_exists(self):
        """Namespace manifest must exist."""
        self.assertTrue(self.namespace_path.exists(),
            f"namespace.yaml not found: {self.namespace_path}")
        self.assertIsNotNone(self.namespace_content,
            "namespace.yaml could not be parsed")


if __name__ == '__main__':
    unittest.main()
