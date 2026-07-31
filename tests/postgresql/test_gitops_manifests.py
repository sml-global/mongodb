"""
Task 5 (revised): PostgreSQL GitOps Manifests — static rendering and
constraint tests. Base is operator-only; the Cluster CR lives in the `dev`
overlay to avoid a CRD race condition (see docs/superpowers/specs/
2026-07-31-postgresql-orchestration-design.md, decision D2).
"""
import pathlib
import subprocess
import unittest

BASE_DIR = pathlib.Path("gitops/postgresql/base")
DEV_DIR = pathlib.Path("gitops/postgresql/overlays/dev")


class PostgresqlGitopsBaseTests(unittest.TestCase):

    def test_base_has_no_cluster_resource(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertNotIn("cluster.yaml", content)

    def test_base_cluster_file_does_not_exist(self):
        self.assertFalse((BASE_DIR / "cluster.yaml").exists())

    def test_helmrelease_postgresql_operator_exists(self):
        operator_file = BASE_DIR / "operator.yaml"
        self.assertTrue(operator_file.exists())

    def test_helmrelease_postgresql_operator_valid_yaml(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: HelmRelease", content)

    def test_helmrelease_references_correct_namespace(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("postgresql-operator", content)

    def test_operator_service_account_not_hardcoded_with_arn(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertNotIn("arn:aws:iam", content)

    def test_kustomize_build_base_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/base"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HelmRelease", result.stdout)
        self.assertNotIn("kind: Cluster\n", result.stdout)


class PostgresqlGitopsDevOverlayTests(unittest.TestCase):

    def test_cluster_manifest_exists_and_valid_yaml(self):
        cluster_file = DEV_DIR / "cluster.yaml"
        self.assertTrue(cluster_file.exists())
        content = cluster_file.read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: Cluster", content)

    def test_cluster_manifest_uses_iam_workload_identity(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("inheritFromIAMRole: true", content)

    def test_cluster_manifest_has_no_hardcoded_aws_credentials(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertNotIn("accessKey", content)
        self.assertNotIn("secretKey", content)
        self.assertNotIn("credentialsSecret", content)

    def test_cluster_manifest_uses_workload_service_account(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("serviceAccountName: oms-postgresql-workload", content)

    def test_cluster_manifest_uses_wffc_storageclass(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("storageClass: gp3-postgresql", content)

    def test_dev_overlay_lists_cluster_as_resource_not_patch(self):
        content = (DEV_DIR / "kustomization.yaml").read_text()
        self.assertIn("cluster.yaml", content)
        # cluster.yaml must be a standalone resource, not a strategic-merge
        # patch target (nothing in base exists to patch anymore).
        self.assertIn("resources:", content)

    def test_kustomize_build_dev_overlay_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/overlays/dev"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("kind: Cluster", result.stdout)
        self.assertIn("HelmRelease", result.stdout)


class PostgresqlUatOverlayRemovedTests(unittest.TestCase):

    def test_uat_overlay_directory_does_not_exist(self):
        self.assertFalse(pathlib.Path("gitops/postgresql/overlays/uat").exists())


if __name__ == "__main__":
    unittest.main()
