"""
Task 3: MongoDB GitOps Manifests — static rendering and constraint tests.
"""
import pathlib
import subprocess
import unittest

BASE_DIR = pathlib.Path("gitops/mongodb/base")
UAT_DIR = pathlib.Path("gitops/mongodb/overlays/uat")


class MongodbGitopsManifestTests(unittest.TestCase):

    # ── file presence ──────────────────────────────────────────────────────

    def test_base_kustomization_exists(self):
        self.assertTrue((BASE_DIR / "kustomization.yaml").exists())

    def test_namespace_yaml_exists(self):
        self.assertTrue((BASE_DIR / "namespace.yaml").exists())

    def test_helmrepository_yaml_exists(self):
        self.assertTrue((BASE_DIR / "helmrepository.yaml").exists())

    def test_operator_yaml_exists(self):
        self.assertTrue((BASE_DIR / "operator.yaml").exists())

    def test_cluster_yaml_exists(self):
        self.assertTrue((BASE_DIR / "cluster.yaml").exists())

    def test_uat_kustomization_exists(self):
        self.assertTrue((UAT_DIR / "kustomization.yaml").exists())

    def test_uat_cluster_patch_exists(self):
        self.assertTrue((UAT_DIR / "cluster-patch.yaml").exists())

    # ── kustomization.yaml lists required resources ────────────────────────

    def test_base_kustomization_includes_helmrepository(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertIn("helmrepository.yaml", content)

    def test_base_kustomization_includes_namespace(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertIn("namespace.yaml", content)

    def test_base_kustomization_includes_operator(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertIn("operator.yaml", content)

    def test_base_kustomization_includes_cluster(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertIn("cluster.yaml", content)

    # ── HelmRelease API version ────────────────────────────────────────────

    def test_operator_uses_v2_helmrelease_api(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("helm.toolkit.fluxcd.io/v2", content)
        self.assertNotIn("v2beta1", content)

    # ── IRSA service account enforcement ──────────────────────────────────

    def test_cluster_uses_oms_mongodb_workload_service_account(self):
        content = (BASE_DIR / "cluster.yaml").read_text()
        self.assertIn("oms-mongodb-workload", content)

    # ── no hardcoded IAM ARNs ─────────────────────────────────────────────

    def test_no_hardcoded_iam_arns_in_manifests(self):
        for f in pathlib.Path("gitops/mongodb").rglob("*.yaml"):
            content = f.read_text()
            self.assertNotIn(
                "arn:aws:iam",
                content,
                f"Hardcoded IAM ARN found in {f}",
            )

    # ── kustomize build ────────────────────────────────────────────────────

    def test_base_kustomize_build_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/mongodb/base"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HelmRelease", result.stdout)

    def test_uat_overlay_renders(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/mongodb/overlays/uat"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    # ── YAML syntax validity ───────────────────────────────────────────────

    def test_cluster_yaml_is_valid_yaml(self):
        import yaml  # noqa: PLC0415
        with open(BASE_DIR / "cluster.yaml") as fh:
            docs = list(yaml.safe_load_all(fh))
        self.assertGreater(len(docs), 0)

    def test_operator_yaml_is_valid_yaml(self):
        import yaml  # noqa: PLC0415
        with open(BASE_DIR / "operator.yaml") as fh:
            docs = list(yaml.safe_load_all(fh))
        self.assertGreater(len(docs), 0)


if __name__ == "__main__":
    unittest.main()
