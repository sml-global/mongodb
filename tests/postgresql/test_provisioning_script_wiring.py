"""Structural (text-parsing) tests asserting provision-k8s-components.sh
wires the postgresql scope correctly. No live kubectl/terraform execution."""
import pathlib
import re
import unittest

SCRIPT = pathlib.Path("scripts/provision-k8s-components.sh").read_text()


class PostgresqlScopeWiringTests(unittest.TestCase):

    def test_postgresql_crd_name_defined(self):
        self.assertIn('POSTGRESQL_CRD_NAME="clusters.postgresql.cnpg.io"', SCRIPT)

    def test_apply_postgresql_operator_function_targets_postgresql_base(self):
        self.assertIn("apply_postgresql_operator()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_operator()", 1)[1].split("\n}", 1)[0]
        self.assertIn("gitops/postgresql/base", func_body)

    def test_apply_postgresql_overlay_function_delegates_to_both_clusters(self):
        self.assertIn("apply_postgresql_overlay()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_overlay()", 1)[1].split("\n}", 1)[0]
        self.assertIn("apply_postgresql_coredb_overlay", func_body)
        self.assertIn("apply_postgresql_branddb_overlay", func_body)

    def test_apply_postgresql_coredb_overlay_function_targets_coredb_dev_overlay(self):
        self.assertIn("apply_postgresql_coredb_overlay()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_coredb_overlay()", 1)[1].split("\n}", 1)[0]
        self.assertIn("gitops/postgresql-coredb/overlays/", func_body)

    def test_apply_postgresql_branddb_overlay_function_targets_branddb_dev_overlay(self):
        self.assertIn("apply_postgresql_branddb_overlay()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_branddb_overlay()", 1)[1].split("\n}", 1)[0]
        self.assertIn("gitops/postgresql-branddb/overlays/", func_body)

    def test_postgresql_case_does_not_call_mongodb_specific_functions(self):
        # The postgresql scope must call its own apply_postgresql_* functions,
        # never the MongoDB-only apply_operators/apply_overlay (which target
        # gitops/operators/base and k8s/overlays/dev respectively).
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        postgresql_case = case_block.split("postgresql)", 1)[1].split(";;", 1)[0]
        self.assertNotIn("apply_operators", postgresql_case)
        self.assertNotIn("apply_overlay()", postgresql_case)
        self.assertNotIn("apply_overlay\n", postgresql_case)

    def test_postgresql_coredb_scope_case_exists_and_calls_coredb_overlay_only(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        coredb_case = case_block.split("postgresql-coredb)", 1)[1].split(";;", 1)[0]
        self.assertIn("apply_postgresql_coredb_overlay", coredb_case)
        self.assertNotIn("apply_postgresql_branddb_overlay", coredb_case)

    def test_postgresql_branddb_scope_case_exists_and_calls_branddb_overlay_only(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        branddb_case = case_block.split("postgresql-branddb)", 1)[1].split(";;", 1)[0]
        self.assertIn("apply_postgresql_branddb_overlay", branddb_case)
        self.assertNotIn("apply_postgresql_coredb_overlay", branddb_case)

    def test_wait_for_postgresql_crd_function_exists(self):
        self.assertIn("wait_for_postgresql_crd()", SCRIPT)
        func_body = SCRIPT.split("wait_for_postgresql_crd()", 1)[1].split("\n}", 1)[0]
        self.assertIn("POSTGRESQL_CRD_NAME", func_body)

    def test_preflight_scope_has_postgresql_case(self):
        preflight_body = SCRIPT.split("preflight_scope() {", 1)[1]
        self.assertIn("postgresql)", preflight_body)

    def test_postgresql_scope_case_calls_functions_in_order(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        postgresql_case = case_block.split("postgresql)", 1)[1].split(";;", 1)[0]
        operator_pos = postgresql_case.find("apply_postgresql_operator")
        policies_pos = postgresql_case.find("apply_policies")
        wait_pos = postgresql_case.find("wait_for_postgresql_crd")
        overlay_pos = postgresql_case.find("apply_postgresql_overlay")
        self.assertTrue(
            -1 < operator_pos < policies_pos < wait_pos < overlay_pos,
            f"expected order operator < policies < wait < overlay, got "
            f"{operator_pos}, {policies_pos}, {wait_pos}, {overlay_pos}",
        )

    def test_usage_text_documents_postgresql_scope(self):
        # Extract content between the heredoc start and the closing EOF marker
        usage_start = SCRIPT.find("usage() {")
        closing_eof = SCRIPT.find("\nEOF", usage_start)
        usage_block = SCRIPT[usage_start:closing_eof] if usage_start != -1 and closing_eof != -1 else ""
        self.assertIn("postgresql", usage_block)
        self.assertIn("postgresql-coredb", usage_block)
        self.assertIn("postgresql-branddb", usage_block)


if __name__ == "__main__":
    unittest.main()
