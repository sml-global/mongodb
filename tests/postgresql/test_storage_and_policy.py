"""Static/structural tests for the PostgreSQL StorageClass and Kyverno WFFC policy."""
import pathlib
import unittest

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


class PostgresqlStorageClassTests(unittest.TestCase):
    def test_storageclass_file_exists(self):
        path = REPO_ROOT / "k8s/base/storageclass-gp3-postgresql.yaml"
        self.assertTrue(path.exists())

    def test_storageclass_uses_wait_for_first_consumer(self):
        path = REPO_ROOT / "k8s/base/storageclass-gp3-postgresql.yaml"
        doc = yaml.safe_load(path.read_text())
        self.assertEqual(doc["kind"], "StorageClass")
        self.assertEqual(doc["metadata"]["name"], "gp3-postgresql")
        self.assertEqual(doc["volumeBindingMode"], "WaitForFirstConsumer")

    def test_storageclass_registered_in_k8s_base_kustomization(self):
        content = (REPO_ROOT / "k8s/base/kustomization.yaml").read_text()
        self.assertIn("storageclass-gp3-postgresql.yaml", content)


class PostgresqlWffcPolicyTests(unittest.TestCase):
    def test_policy_file_exists(self):
        path = REPO_ROOT / "policies/kyverno/require-wffc-storageclass-postgresql.yaml"
        self.assertTrue(path.exists())

    def test_policy_matches_storageclass_by_name_only(self):
        path = REPO_ROOT / "policies/kyverno/require-wffc-storageclass-postgresql.yaml"
        doc = yaml.safe_load(path.read_text())
        self.assertEqual(doc["kind"], "ClusterPolicy")
        match = doc["spec"]["rules"][0]["match"]["any"][0]
        self.assertEqual(match["resources"]["kinds"], ["StorageClass"])
        self.assertEqual(match["resources"]["names"], ["gp3-postgresql"])
        self.assertNotIn("namespaces", match["resources"])

    def test_policy_registered_in_kyverno_kustomization(self):
        content = (REPO_ROOT / "policies/kyverno/kustomization.yaml").read_text()
        self.assertIn("require-wffc-storageclass-postgresql.yaml", content)


if __name__ == "__main__":
    unittest.main()
