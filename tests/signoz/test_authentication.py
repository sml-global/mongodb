"""
Test suite for SigNoz API authentication strategy.

Verifies that:
1. Dashboard import uses Kubernetes Secret (not hardcoded credentials)
2. Bootstrap script handles missing Secret gracefully
"""

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts" / "bootstrap_signoz_dashboards.sh"


def read(path: Path) -> str:
    """Read file contents as text."""
    return path.read_text(encoding="utf-8")


class SignozAuthenticationTests(unittest.TestCase):
    """Test cases for SigNoz API authentication security."""

    def test_import_script_uses_kubernetes_secret_not_hardcoded_credentials(self):
        """Verify bootstrap script retrieves credentials from Kubernetes Secret.
        
        The script must use the 'signoz-root-user' Kubernetes Secret to retrieve
        admin credentials. Credentials must NEVER be hardcoded or obtained from
        environment variables without Secret backing.
        
        Requirement: Must include 'signoz-root-user' AND 'kubectl get secret'.
        Must NOT include hardcoded password patterns like 'password=' literals.
        """
        bootstrap_script = read(BOOTSTRAP_SCRIPT)
        
        # Must reference the Kubernetes Secret
        self.assertIn('signoz-root-user', bootstrap_script,
                      "bootstrap script must reference 'signoz-root-user' Secret")
        self.assertIn('kubectl get secret', bootstrap_script,
                      "bootstrap script must use 'kubectl get secret' to retrieve credentials")
        
        # Must NOT have hardcoded credentials
        # (Check for patterns that would indicate hardcoded secrets)
        self.assertNotIn('password=admin', bootstrap_script,
                         "bootstrap script must not hardcode password")
        self.assertNotIn("password='", bootstrap_script,
                         "bootstrap script must not hardcode password in quotes")

    def test_bootstrap_script_exits_if_secret_missing(self):
        """Verify bootstrap script exits with error if Secret doesn't exist.
        
        If the Kubernetes Secret 'signoz-root-user' is not found, the script
        must exit with error code 1 and provide a clear error message directing
        the operator to create the Secret first.
        
        Requirement: Must include error handling for missing Secret with exit 1.
        """
        bootstrap_script = read(BOOTSTRAP_SCRIPT)
        
        # Must check for Secret existence
        self.assertIn('get secret signoz-root-user', bootstrap_script,
                      "bootstrap script must check for Secret existence")
        
        # Must exit on failure
        self.assertIn('exit 1', bootstrap_script,
                      "bootstrap script must exit with code 1 if Secret is missing")


if __name__ == '__main__':
    unittest.main()
