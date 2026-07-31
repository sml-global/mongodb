import pathlib
import unittest

FRAGMENT = pathlib.Path("config/environment-schema/fragments/40-postgresql.manifest")


class PostgresqlSchemaFragmentTests(unittest.TestCase):
    def test_postgresql_schema_fragment_exists(self):
        self.assertTrue(FRAGMENT.exists())

    def test_postgresql_fragment_has_eks_platform_requires_dependency(self):
        content = FRAGMENT.read_text()
        self.assertIn("@requires eks-platform", content)

    def test_postgresql_fragment_declares_no_dead_keys(self):
        # Regression test for Issue #4: POSTGRESQL_REPLICA_COUNT,
        # POSTGRESQL_STORAGE_CLASS, POSTGRESQL_IMAGE_REPO,
        # POSTGRESQL_OPERATOR_VERSION, POSTGRESQL_BACKUP_ENABLED, and
        # POSTGRESQL_BACKUP_SCHEDULE were declared here since Phase 3
        # planning but never consumed anywhere in the codebase (verified via
        # repo-wide search); they were removed 2026-07-31. Guard against
        # reintroducing them as actual schema rows (the header comment
        # documenting their removal legitimately mentions these names in
        # prose, so check for the row syntax specifically).
        rows = [
            line for line in FRAGMENT.read_text().splitlines()
            if line and not line.startswith("#")
        ]
        row_keys = [row.split("|", 1)[0] for row in rows]
        for dead_key in (
            "POSTGRESQL_REPLICA_COUNT",
            "POSTGRESQL_STORAGE_CLASS",
            "POSTGRESQL_IMAGE_REPO",
            "POSTGRESQL_OPERATOR_VERSION",
            "POSTGRESQL_BACKUP_ENABLED",
            "POSTGRESQL_BACKUP_SCHEDULE",
        ):
            self.assertNotIn(dead_key, row_keys)


if __name__ == "__main__":
    unittest.main()
