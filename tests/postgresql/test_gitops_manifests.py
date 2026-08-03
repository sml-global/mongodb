"""
Task 5 (revised): PostgreSQL GitOps Manifests — static rendering and
constraint tests. Base (gitops/postgresql/base) is operator-only and shared
by both clusters. Each cluster (core, brand) has its own overlay tree
(gitops/postgresql-coredb/, gitops/postgresql-branddb/) with its own
namespace + Cluster CR, so either can be provisioned, resized, or destroyed
independently — see docs/superpowers/specs/
2026-07-31-postgresql-orchestration-design.md, decision D2, and the
core/brand CNPG split ticket.
"""
import pathlib
import subprocess
import unittest

BASE_DIR = pathlib.Path("gitops/postgresql/base")


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

    def test_base_namespace_manifest_no_longer_creates_shared_postgresql_namespace(self):
        content = (BASE_DIR / "namespace.yaml").read_text()
        self.assertNotIn("name: postgresql\n", content)
        self.assertIn("name: postgresql-operator", content)


class PostgresqlCoredbDevOverlayTests(unittest.TestCase):
    DEV_DIR = pathlib.Path("gitops/postgresql-coredb/overlays/dev")

    def test_cluster_manifest_exists_and_valid_yaml(self):
        cluster_file = self.DEV_DIR / "cluster.yaml"
        self.assertTrue(cluster_file.exists())
        content = cluster_file.read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: Cluster", content)

    def test_cluster_manifest_uses_correct_namespace_and_name(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("namespace: coredb", content)
        self.assertIn("name: oms-postgresql-coredb", content)

    def test_cluster_manifest_uses_iam_workload_identity(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("inheritFromIAMRole: true", content)

    def test_cluster_manifest_has_no_hardcoded_aws_credentials(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertNotIn("accessKey", content)
        self.assertNotIn("secretKey", content)
        self.assertNotIn("credentialsSecret", content)

    def test_cluster_manifest_uses_workload_service_account(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("serviceAccountName: oms-postgresql-workload", content)

    def test_cluster_manifest_uses_wffc_storageclass(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("storageClass: gp3-postgresql", content)

    def test_dev_overlay_lists_cluster_as_resource_not_patch(self):
        content = (self.DEV_DIR / "kustomization.yaml").read_text()
        self.assertIn("cluster.yaml", content)
        self.assertIn("resources:", content)

    def test_kustomize_build_dev_overlay_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", str(self.DEV_DIR)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("kind: Cluster", result.stdout)
        self.assertIn("name: coredb", result.stdout)


class PostgresqlBranddbDevOverlayTests(unittest.TestCase):
    DEV_DIR = pathlib.Path("gitops/postgresql-branddb/overlays/dev")

    def test_cluster_manifest_exists_and_valid_yaml(self):
        cluster_file = self.DEV_DIR / "cluster.yaml"
        self.assertTrue(cluster_file.exists())
        content = cluster_file.read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: Cluster", content)

    def test_cluster_manifest_uses_correct_namespace_and_name(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("namespace: branddb", content)
        self.assertIn("name: oms-postgresql-branddb", content)

    def test_cluster_manifest_uses_iam_workload_identity(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("inheritFromIAMRole: true", content)

    def test_cluster_manifest_has_no_hardcoded_aws_credentials(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertNotIn("accessKey", content)
        self.assertNotIn("secretKey", content)
        self.assertNotIn("credentialsSecret", content)

    def test_cluster_manifest_uses_workload_service_account(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("serviceAccountName: oms-postgresql-brand-workload", content)

    def test_cluster_manifest_uses_wffc_storageclass(self):
        content = (self.DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("storageClass: gp3-postgresql", content)

    def test_dev_overlay_lists_cluster_as_resource_not_patch(self):
        content = (self.DEV_DIR / "kustomization.yaml").read_text()
        self.assertIn("cluster.yaml", content)
        self.assertIn("resources:", content)

    def test_kustomize_build_dev_overlay_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", str(self.DEV_DIR)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("kind: Cluster", result.stdout)
        self.assertIn("name: branddb", result.stdout)


class PostgresqlUatOverlayRemovedTests(unittest.TestCase):

    def test_uat_overlay_directory_does_not_exist(self):
        self.assertFalse(pathlib.Path("gitops/postgresql/overlays/uat").exists())

    def test_old_shared_dev_overlay_directory_does_not_exist(self):
        self.assertFalse(pathlib.Path("gitops/postgresql/overlays/dev").exists())


if __name__ == "__main__":
    unittest.main()
