#!/usr/bin/env python3
"""
tests/signoz/test_environment_contract.py

Test environment schema fragment validation for SigNoz.
Tests: 3

- test_signoz_schema_fragment_exists
- test_signoz_fragment_has_eks_platform_requires_dependency
- test_signoz_fragment_declares_no_dead_keys
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

    def test_signoz_fragment_has_eks_platform_requires_dependency(self):
        """Fragment must declare @requires eks-platform dependency."""
        self.assertIn("@requires eks-platform", self.schema_content,
            "Fragment must declare @requires eks-platform dependency")

    def test_signoz_fragment_declares_no_dead_keys(self):
        """Regression test for Issue #4: SIGNOZ_NAMESPACE (a duplicate of the
        row in base.manifest, with a conflicting fixed:signoz constraint that
        would have rejected UAT's real value signoz-uat), SIGNOZ_VERSION,
        SIGNOZ_K8S_INFRA_VERSION, SIGNOZ_STORAGE_CLASS, SIGNOZ_OTEL_ENDPOINT,
        and SIGNOZ_CLICKHOUSE_SECRET_NAME were declared here since Phase 3
        planning but never consumed anywhere in the codebase (verified via
        repo-wide search); all were removed 2026-07-31. Guard against
        reintroducing them as actual schema rows (the header comment
        documenting their removal legitimately mentions these names in
        prose, so check for the row syntax specifically)."""
        rows = [
            line for line in self.schema_content.splitlines()
            if line and not line.startswith("#")
        ]
        row_keys = [row.split("|", 1)[0] for row in rows]
        for dead_key in (
            "SIGNOZ_NAMESPACE",
            "SIGNOZ_VERSION",
            "SIGNOZ_K8S_INFRA_VERSION",
            "SIGNOZ_STORAGE_CLASS",
            "SIGNOZ_OTEL_ENDPOINT",
            "SIGNOZ_CLICKHOUSE_SECRET_NAME",
        ):
            self.assertNotIn(dead_key, row_keys,
                f"{dead_key} should have been removed from this fragment")


if __name__ == '__main__':
    unittest.main()
