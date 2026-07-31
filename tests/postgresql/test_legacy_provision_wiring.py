"""Structural tests asserting legacy/dev/provision.sh's pg and all scopes
apply the PostgreSQL k8s manifests, not just Terraform prerequisites."""
import pathlib
import unittest

SCRIPT = pathlib.Path("scripts/legacy/dev/provision.sh").read_text()


class LegacyProvisionPostgresqlWiringTests(unittest.TestCase):

    def test_pg_case_calls_run_k8s_postgresql(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        pg_case = case_block.split("pg)", 1)[1].split(";;", 1)[0]
        self.assertIn("run_platform pg", pg_case)
        self.assertIn("run_k8s postgresql", pg_case)

    def test_all_case_calls_run_k8s_postgresql_after_mongodb(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        all_case = case_block.split("all)", 1)[1].split(";;", 1)[0]
        mongodb_pos = all_case.find("run_k8s mongodb")
        postgresql_pos = all_case.find("run_k8s postgresql")
        self.assertTrue(-1 < mongodb_pos < postgresql_pos)


if __name__ == "__main__":
    unittest.main()
