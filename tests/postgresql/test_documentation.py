"""Assertions that PostgreSQL docs reflect the corrected orchestration reality."""
import pathlib
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


class PostgresqlDocumentationTests(unittest.TestCase):

    def test_contract_references_real_pod_name(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("oms-postgresql-1", content)
        self.assertNotIn("exec -it postgresql-1", content)

    def test_contract_references_gp3_postgresql_storageclass(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("k8s/base/storageclass-gp3-postgresql.yaml", content)
        self.assertNotIn("k8s/base/storage-classes.yaml", content)

    def test_contract_references_real_provisioning_command(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_contract_has_no_stale_uat_decommission_warning(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertNotIn("requires a manual decommission step", content)

    def test_component_catalog_references_real_provisioning_command(self):
        content = (REPO_ROOT / "docs/references/component-catalog.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_verification_commands_reference_real_cluster_name(self):
        content = (REPO_ROOT / "docs/references/verification-commands.md").read_text()
        self.assertIn("oms-postgresql-1", content)

    def test_index_has_no_stale_uat_decommission_followup(self):
        content = (REPO_ROOT / "docs/index.md").read_text()
        self.assertNotIn("needs an explicit, manual decommission step", content)


if __name__ == "__main__":
    unittest.main()
