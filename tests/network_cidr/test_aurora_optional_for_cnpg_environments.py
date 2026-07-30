import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PG_VARS = REPO_ROOT / "platform-prerequisites/terraform/postgresql/variables.tf"
PG_MAIN = REPO_ROOT / "platform-prerequisites/terraform/postgresql/main.tf"


class AuroraOptionalForCnpgEnvironmentsTests(unittest.TestCase):
    def test_aurora_variables_have_safe_defaults(self):
        text = PG_VARS.read_text(encoding="utf-8")
        self.assertIn("default     = []", text)
        for name in [
            "vpc_id",
            "database_subnet_ids",
            "allowed_source_security_group_id",
            "aurora_engine_version",
            "aurora_instance_class",
            "aurora_database_name",
            "aurora_master_username",
        ]:
            start = text.index(f'variable "{name}"')
            end = text.index("}", start)
            block = text[start:end]
            if name == "database_subnet_ids":
                self.assertIn("default     = []", block, f"{name} missing empty-list default")
            else:
                self.assertIn('default     = ""', block, f"{name} missing empty-string default")

    def test_database_subnet_ids_validation_allows_empty(self):
        text = PG_VARS.read_text(encoding="utf-8")
        self.assertIn(
            "length(var.database_subnet_ids) == 0 || length(var.database_subnet_ids) >= 2",
            text,
        )

    def test_aurora_resources_gated_on_database_subnet_ids(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        gate = re.compile(r"count\s*=\s*length\(var\.database_subnet_ids\) > 0 \? 1 : 0")
        self.assertGreaterEqual(
            len(gate.findall(text)),
            3,
            "expected aws_db_subnet_group, aws_security_group, and aws_rds_cluster aurora resources to be gated",
        )

    def test_aurora_cluster_instance_gated_on_database_subnet_ids(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        gate = re.compile(
            r"count\s*=\s*length\(var\.database_subnet_ids\) > 0 \? var\.aurora_instance_count : 0"
        )
        self.assertTrue(gate.search(text))


if __name__ == "__main__":
    unittest.main()
