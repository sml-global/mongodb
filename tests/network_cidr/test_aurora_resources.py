import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PG_VARS = REPO_ROOT / "platform-prerequisites/terraform/postgresql/variables.tf"
PG_MAIN = REPO_ROOT / "platform-prerequisites/terraform/postgresql/main.tf"


class AuroraResourceTests(unittest.TestCase):
    def test_new_variables_exist(self):
        text = PG_VARS.read_text(encoding="utf-8")
        for name in [
            "vpc_id",
            "database_subnet_ids",
            "aurora_engine_version",
            "aurora_instance_class",
            "aurora_instance_count",
            "aurora_database_name",
            "aurora_master_username",
            "allowed_source_security_group_id",
        ]:
            self.assertIn(f'variable "{name}"', text)

    def test_db_subnet_group_resource_exists(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_db_subnet_group" "aurora"', text)

    def test_rds_cluster_resource_exists_and_uses_managed_password(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_rds_cluster" "aurora"', text)
        self.assertIn("manage_master_user_password = true", text)
        self.assertNotIn("master_password", text)

    def test_rds_cluster_instance_resource_exists(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_rds_cluster_instance" "aurora"', text)

    def test_security_group_restricts_ingress_to_source_sg_only(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_security_group" "aurora"', text)
        self.assertIn("var.allowed_source_security_group_id", text)


if __name__ == "__main__":
    unittest.main()
