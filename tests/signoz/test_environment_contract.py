#!/usr/bin/env python3
"""
tests/signoz/test_environment_contract.py

Test environment schema fragment validation for SigNoz.
Tests: 4

- test_signoz_schema_fragment_exists
- test_signoz_fragment_registers_all_required_variables
- test_signoz_fragment_has_eks_platform_requires_dependency
- test_signoz_fragment_validates_variable_constraints
"""

import unittest
import os
from pathlib import Path


class TestSignozEnvironmentContract(unittest.TestCase):
    """Validate SigNoz environment schema fragment."""

    @classmethod
    def setUpClass(cls):
        """Load schema fragment."""
        cls.schema_path = Path(__file__).parent.parent.parent / "config" / "environment-schema" / "fragments" / "50-signoz.manifest"
        if cls.schema_path.exists():
            with open(cls.schema_path, 'r') as f:
                cls.schema_content = f.read()
        else:
            cls.schema_content = ""

    def test_signoz_schema_fragment_exists(self):
        """Schema fragment file must exist."""
        self.assertTrue(self.schema_path.exists(),
            f"Schema fragment not found: {self.schema_path}")

    def test_signoz_fragment_registers_all_required_variables(self):
        """Fragment must define all 6 required variables."""
        required_vars = [
            "SIGNOZ_NAMESPACE",
            "SIGNOZ_VERSION",
            "SIGNOZ_K8S_INFRA_VERSION",
            "SIGNOZ_STORAGE_CLASS",
            "SIGNOZ_OTEL_ENDPOINT",
            "SIGNOZ_CLICKHOUSE_SECRET_NAME",
        ]
        for var in required_vars:
            self.assertIn(var, self.schema_content,
                f"Required variable {var} not found in schema fragment")

    def test_signoz_fragment_has_eks_platform_requires_dependency(self):
        """Fragment must declare @requires eks-platform dependency."""
        self.assertIn("@requires eks-platform", self.schema_content,
            "Fragment must declare @requires eks-platform dependency")

    def test_signoz_fragment_validates_variable_constraints(self):
        """Fragment must specify constraints for each variable."""
        # SIGNOZ_NAMESPACE must have fixed constraint
        self.assertIn("SIGNOZ_NAMESPACE|required|fixed:signoz", self.schema_content,
            "SIGNOZ_NAMESPACE must be fixed to 'signoz'")
        
        # SIGNOZ_STORAGE_CLASS must have fixed constraint
        self.assertIn("SIGNOZ_STORAGE_CLASS|required|fixed:gp3-mongodb", self.schema_content,
            "SIGNOZ_STORAGE_CLASS must be fixed to 'gp3-mongodb'")
        
        # Other variables must have nonempty constraint
        self.assertIn("SIGNOZ_VERSION|required|nonempty", self.schema_content,
            "SIGNOZ_VERSION must have nonempty constraint")
        self.assertIn("SIGNOZ_K8S_INFRA_VERSION|required|nonempty", self.schema_content,
            "SIGNOZ_K8S_INFRA_VERSION must have nonempty constraint")
        self.assertIn("SIGNOZ_OTEL_ENDPOINT|required|nonempty", self.schema_content,
            "SIGNOZ_OTEL_ENDPOINT must have nonempty constraint")
        self.assertIn("SIGNOZ_CLICKHOUSE_SECRET_NAME|required|nonempty", self.schema_content,
            "SIGNOZ_CLICKHOUSE_SECRET_NAME must have nonempty constraint")


if __name__ == '__main__':
    unittest.main()
