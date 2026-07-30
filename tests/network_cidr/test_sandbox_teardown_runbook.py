import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNBOOK = REPO_ROOT / "docs/references/sandbox-teardown-runbook.md"


class SandboxTeardownRunbookTests(unittest.TestCase):
    def test_runbook_exists(self):
        self.assertTrue(RUNBOOK.is_file())

    def test_runbook_documents_correct_destroy_order(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        mongodb_pos = text.find("terraform destroy")
        # The destroy order (mongodb/postgresql -> workload-identity -> eks-platform)
        # is verified in the design spec's 4-Perspective Critique Findings section.
        self.assertIn("mongodb", text)
        self.assertIn("postgresql", text)
        self.assertIn("workload-identity", text)
        self.assertIn("eks-platform", text)
        order_workload_identity = text.find("cd platform-prerequisites/terraform/workload-identity")
        order_eks_platform = text.find("cd platform-prerequisites/terraform/eks-platform")
        order_mongodb = text.find("cd platform-prerequisites/terraform/mongodb")
        self.assertGreater(order_workload_identity, order_mongodb)
        self.assertGreater(order_eks_platform, order_workload_identity)

    def test_runbook_documents_prevent_destroy_override(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        self.assertIn("prevent_destroy", text)
        self.assertIn("modules/efs/main.tf", text)

    def test_runbook_requires_explicit_confirmation(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        self.assertIn("CONFIRM", text)


if __name__ == "__main__":
    unittest.main()
