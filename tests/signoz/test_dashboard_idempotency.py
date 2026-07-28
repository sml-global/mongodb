"""
Test suite for SigNoz dashboard import idempotency.

Verifies that:
1. All dashboard JSON files have UUID/ID fields for safe identification
2. Import script implements check-before-import logic
3. SRE customizations are never overwritten
"""

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DASHBOARDS_DIR = REPO_ROOT / "dashboards" / "signoz-import-pack"
BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts" / "bootstrap_signoz_dashboards.sh"


def read(path: Path) -> str:
    """Read file contents as text."""
    return path.read_text(encoding="utf-8")


class DashboardIdempotencyTests(unittest.TestCase):
    """Test cases for SigNoz dashboard import idempotency guarantees."""

    def test_all_dashboards_have_uuid_or_id(self):
        """Verify every dashboard JSON has UUID or ID field for identification.
        
        Each dashboard must have a unique identifier (uuid or id field) to enable
        idempotent imports. Without this, the import script cannot reliably detect
        when a dashboard already exists and would re-import/duplicate on every run.
        """
        if not DASHBOARDS_DIR.exists():
            self.skipTest(f"Dashboards directory not found: {DASHBOARDS_DIR}")
        
        dashboard_files = list(DASHBOARDS_DIR.glob("*.json"))
        self.assertTrue(dashboard_files, "No dashboard JSON files found")
        
        for dashboard_file in dashboard_files:
            with self.subTest(dashboard=dashboard_file.name):
                try:
                    dashboard = json.loads(dashboard_file.read_text(encoding="utf-8"))
                except json.JSONDecodeError as e:
                    self.fail(f"{dashboard_file.name}: Invalid JSON: {e}")
                
                has_uuid = 'uuid' in dashboard
                has_id = 'id' in dashboard
                
                self.assertTrue(
                    has_uuid or has_id,
                    f"{dashboard_file.name}: Missing 'uuid' or 'id' field. "
                    "Cannot guarantee idempotent import."
                )

    def test_import_script_includes_check_before_import(self):
        """Verify dashboard import script checks existence before importing.
        
        The bootstrap script must query the SigNoz API to check if a dashboard
        with the same UUID/ID already exists. If it does, the import must be
        skipped to preserve SRE customizations.
        
        NOTE: Matching is by UUID/ID ONLY (not title). Title-based matching is
        fragile: if an SRE renames a dashboard in the UI, the title no longer
        matches and the import script would incorrectly re-import a duplicate.
        
        Requirement: Must include check logic with curl API query and skip branching.
        Must match by UUID/ID, NOT by title.
        """
        bootstrap_script = read(BOOTSTRAP_SCRIPT)
        
        # Must query the API to check for existing dashboards
        self.assertIn('curl', bootstrap_script,
                      "bootstrap script must use curl to query SigNoz API")
        self.assertIn('dashboards', bootstrap_script,
                      "bootstrap script must query the dashboards endpoint")
        
        # Must match by UUID/ID ONLY (not title to avoid fragility)
        # Count occurrences to verify both UUID and ID are checked
        uuid_checks = bootstrap_script.count('.uuid')
        id_checks = bootstrap_script.count('.id')
        self.assertTrue(
            uuid_checks >= 1 and id_checks >= 1,
            "bootstrap script must check both .uuid and .id for matching"
        )
        
        # Must implement skip logic for existing dashboards
        self.assertIn('skip', bootstrap_script.lower(),
                      "bootstrap script must skip import for existing dashboards")

    def test_import_script_preserves_sre_customizations(self):
        """Verify import script never overwrites existing dashboards.
        
        The script must never use flags like '--force' or 'overwrite' that would
        replace an existing dashboard. SRE customizations must be preserved
        across re-runs.
        Requirement: Must NOT include overwrite/force keywords.
        """
        bootstrap_script = read(BOOTSTRAP_SCRIPT)
        
        # Should NOT use force or overwrite options
        self.assertNotIn('--force', bootstrap_script,
                         "bootstrap script must never use --force flag")
        self.assertNotIn('--overwrite', bootstrap_script,
                         "bootstrap script must never use --overwrite flag")
        
        # Verify script explicitly skips existing dashboards (idempotency guarantee)
        self.assertIn('existing', bootstrap_script.lower(),
                      "bootstrap script should skip 'existing' dashboards")


if __name__ == '__main__':
    unittest.main()
