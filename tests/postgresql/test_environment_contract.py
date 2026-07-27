import pathlib
import unittest

FRAGMENT = pathlib.Path("config/environment-schema/fragments/40-postgresql.manifest")


class PostgresqlSchemaFragmentTests(unittest.TestCase):
    def test_postgresql_schema_fragment_exists(self):
        self.assertTrue(FRAGMENT.exists())

    def test_postgresql_fragment_registers_all_required_variables(self):
        content = FRAGMENT.read_text()
        for var in [
            "POSTGRESQL_REPLICA_COUNT",
            "POSTGRESQL_STORAGE_CLASS",
            "POSTGRESQL_IMAGE_REPO",
            "POSTGRESQL_OPERATOR_VERSION",
            "POSTGRESQL_BACKUP_ENABLED",
        ]:
            self.assertIn(var, content)

    def test_postgresql_fragment_has_mongodb_requires_dependency(self):
        content = FRAGMENT.read_text()
        self.assertIn("@requires eks-platform", content)

    def test_postgresql_fragment_validates_variable_constraints(self):
        content = FRAGMENT.read_text()
        # Verify that replica_count has integer constraints
        self.assertIn("POSTGRESQL_REPLICA_COUNT|required|integer:1:10", content)
        # Verify that storage class is fixed to gp3
        self.assertIn("POSTGRESQL_STORAGE_CLASS|required|fixed:gp3", content)
        # Verify backup_enabled is enum
        self.assertIn("POSTGRESQL_BACKUP_ENABLED|required|enum:true,false", content)


if __name__ == "__main__":
    unittest.main()
