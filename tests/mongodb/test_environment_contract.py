import pathlib
import unittest

FRAGMENT = pathlib.Path("config/environment-schema/fragments/30-mongodb.manifest")


class MongodbSchemaFragmentTests(unittest.TestCase):
    def test_fragment_exists(self):
        self.assertTrue(FRAGMENT.exists())

    def test_fragment_declares_replica_count(self):
        self.assertIn("MONGODB_REPLICA_COUNT", FRAGMENT.read_text())

    def test_fragment_declares_storage_class(self):
        self.assertIn("MONGODB_STORAGE_CLASS", FRAGMENT.read_text())

    def test_fragment_has_no_hardcoded_arns(self):
        content = FRAGMENT.read_text()
        self.assertNotIn("arn:aws:", content)


if __name__ == "__main__":
    unittest.main()
