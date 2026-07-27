"""
Task 5: PostgreSQL GitOps Manifests — static rendering and constraint tests.
"""
import pathlib
import subprocess
import unittest

BASE_DIR = pathlib.Path("gitops/postgresql/base")
UAT_DIR = pathlib.Path("gitops/postgresql/overlays/uat")


class PostgresqlGitopsManifestTests(unittest.TestCase):

    # ── file presence ──────────────────────────────────────────────────────

    def test_cluster_manifest_exists_and_valid_yaml(self):
        cluster_file = BASE_DIR / "cluster.yaml"
        self.assertTrue(cluster_file.exists())
        content = cluster_file.read_text()
        # Basic YAML structure check
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: Cluster", content)

    def test_helmrelease_postgresql_operator_exists(self):
        operator_file = BASE_DIR / "operator.yaml"
        self.assertTrue(operator_file.exists())

    def test_helmrelease_postgresql_operator_valid_yaml(self):
        operator_file = BASE_DIR / "operator.yaml"
        self.assertTrue(operator_file.exists())
        content = operator_file.read_text()
        # Basic YAML structure check
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: HelmRelease", content)

    # ── IRSA service account enforcement ──────────────────────────────────

    def test_cluster_manifest_uses_iam_workload_identity(self):
        content = (BASE_DIR / "cluster.yaml").read_text()
        # Verify IRSA is configured
        self.assertIn("inheritFromIAMRole: true", content)

    def test_cluster_manifest_has_no_hardcoded_aws_credentials(self):
        content = (BASE_DIR / "cluster.yaml").read_text()
        # Verify no accessKey/secretKey hardcoded
        self.assertNotIn("accessKey", content)
        self.assertNotIn("secretKey", content)
        self.assertNotIn("credentialsSecret", content)

    def test_cluster_manifest_uses_workload_service_account(self):
        content = (BASE_DIR / "cluster.yaml").read_text()
        self.assertIn("serviceAccountName: oms-postgresql-workload", content)

    # ── kustomize build ────────────────────────────────────────────────────

    def test_kustomize_build_base_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/base"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HelmRelease", result.stdout)

    def test_kustomize_build_uat_overlay_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/overlays/uat"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    # ── no hardcoded IAM ARNs ─────────────────────────────────────────────

    def test_helmrelease_references_correct_namespace(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("postgresql-operator", content)

    def test_operator_service_account_not_hardcoded_with_arn(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        # Verify no hardcoded IAM ARN in operator manifest
        self.assertNotIn("arn:aws:iam", content)

    def test_uat_overlay_applies_cluster_patches(self):
        uat_kustomization = UAT_DIR / "kustomization.yaml"
        self.assertTrue(uat_kustomization.exists())
        content = uat_kustomization.read_text()
        # Verify patches are referenced
        self.assertIn("patches", content.lower() or "patchesStrategicMerge" in content)


if __name__ == "__main__":
    unittest.main()
