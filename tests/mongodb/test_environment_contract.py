import pathlib
import unittest

FRAGMENT = pathlib.Path("config/environment-schema/fragments/30-mongodb.manifest")


class MongodbSchemaFragmentTests(unittest.TestCase):
    def test_fragment_exists(self):
        self.assertTrue(FRAGMENT.exists())

    def test_fragment_has_no_hardcoded_arns(self):
        content = FRAGMENT.read_text()
        self.assertNotIn("arn:aws:", content)

    def test_fragment_declares_no_dead_keys(self):
        # Regression test for Issue #4: MONGODB_REPLICA_COUNT,
        # MONGODB_STORAGE_CLASS, MONGODB_IMAGE_REPO, MONGODB_OPERATOR_VERSION,
        # MONGODB_BACKUP_ENABLED, and MONGODB_BACKUP_SCHEDULE were declared
        # here since Phase 3 planning but never consumed anywhere in the
        # codebase (verified via repo-wide search); they were removed
        # 2026-07-31. Guard against reintroducing them as actual schema rows
        # (the header comment documenting their removal legitimately
        # mentions these names in prose, so check for the row syntax
        # specifically, not any substring match).
        rows = [
            line for line in FRAGMENT.read_text().splitlines()
            if line and not line.startswith("#")
        ]
        row_keys = [row.split("|", 1)[0] for row in rows]
        for dead_key in (
            "MONGODB_REPLICA_COUNT",
            "MONGODB_STORAGE_CLASS",
            "MONGODB_IMAGE_REPO",
            "MONGODB_OPERATOR_VERSION",
            "MONGODB_BACKUP_ENABLED",
            "MONGODB_BACKUP_SCHEDULE",
        ):
            self.assertNotIn(dead_key, row_keys)


if __name__ == "__main__":
    unittest.main()
