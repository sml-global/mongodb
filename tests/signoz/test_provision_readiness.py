"""
Test suite for SigNoz provision readiness checks.

Verifies that scripts/provision-signoz-observability.sh includes proper
readiness gates before provisioning SigNoz observability resources.
"""

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROVISION_SCRIPT = REPO_ROOT / "scripts" / "provision-signoz-observability.sh"


def read(path: Path) -> str:
    """Read file contents as text."""
    return path.read_text(encoding="utf-8")


class SignozReadinessTests(unittest.TestCase):
    """Test cases for SigNoz readiness gate implementation."""

    def test_provision_script_includes_kubectl_wait_for_query_service(self):
        """Verify provision script waits for query-service Ready state.
        
        The script must explicitly wait for the query-service pod to reach
        Ready status before attempting any SigNoz API calls or provisioning.
        Requirement: Must include 'kubectl wait' AND 'query-service' AND '--timeout=' 
        to ensure a bounded wait.
        """
        provision_script = read(PROVISION_SCRIPT)
        
        self.assertIn('kubectl wait', provision_script,
                      "provision script must include 'kubectl wait' command")
        self.assertIn('query-service', provision_script,
                      "provision script must wait for 'query-service' pod")
        self.assertIn('--timeout=', provision_script,
                      "provision script must specify timeout for kubectl wait")

    def test_provision_script_includes_kubectl_wait_for_frontend(self):
        """Verify provision script waits for frontend Ready state.
        
        The script must explicitly wait for the frontend pod to reach
        Ready status before attempting to access the SigNoz API.
        Requirement: Must include 'kubectl wait' AND 'frontend'.
        """
        provision_script = read(PROVISION_SCRIPT)
        
        self.assertIn('kubectl wait', provision_script,
                      "provision script must include 'kubectl wait' command")
        self.assertIn('frontend', provision_script,
                      "provision script must wait for 'frontend' pod")

    def test_provision_script_has_exit_on_readiness_failure(self):
        """Verify provision script exits if readiness check fails.
        
        The script must exit with error code 1 if any readiness check fails,
        preventing downstream provisioning from proceeding with an unready
        SigNoz platform.
        Requirement: Must include 'exit 1' to abort on failure.
        """
        provision_script = read(PROVISION_SCRIPT)
        
        self.assertIn('exit 1', provision_script,
                      "provision script must exit with code 1 on readiness failure")

    def test_provision_script_uses_kubectl_exec_not_ephemeral_pods(self):
        """Verify connectivity test uses kubectl exec (not kubectl run).
        
        The API connectivity check must use 'kubectl exec' into the existing
        frontend pod. Using 'kubectl run' creates ephemeral pods that:
        - Cause race conditions if provision runs concurrently
        - Pollute Kubernetes audit logs with garbage pods
        - Use non-reproducible 'latest' image tags
        
        Requirement: Must use 'kubectl exec', must NOT use 'kubectl run --rm'.
        """
        provision_script = read(PROVISION_SCRIPT)
        
        self.assertIn('kubectl exec', provision_script,
                      "provision script must use 'kubectl exec' for API tests")
        self.assertNotIn('kubectl run -it --rm', provision_script,
                         "provision script must NOT use ephemeral 'kubectl run' pods")
        self.assertNotIn('--image=curlimages/curl:latest', provision_script,
                         "provision script must NOT use non-reproducible 'latest' tag")

    def test_provision_script_validates_endpoint_is_internal(self):
        """Verify provision script validates SIGNOZ_ENDPOINT (prevent AWS egress).
        
        If ENDPOINT is external to cluster (not .svc.cluster.local/127.0.0.1/localhost),
        traffic routes through AWS NAT gateway → egress charges.
        
        Requirement: Must include validation check for internal endpoints.
        """
        provision_script = read(PROVISION_SCRIPT)
        
        # Check for endpoint validation logic
        self.assertTrue(
            ('svc.cluster.local' in provision_script or '127.0.0.1' in provision_script),
            "provision script must validate endpoint is internal"
        )


if __name__ == '__main__':
    unittest.main()
