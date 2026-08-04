"""
Test suite for EKS Platform documentation gate (Task 8).

Validates that the EKS Platform contract document and implementation
follow the Task 8 preflight rubric checklist:
  1. Command Authorization: Every shell block begins with '# AUTHORIZED-ONLY'
  2. Mutation Refusal: Documentation forbids manual execution, commits, dev mutations
  3. No New Public API: No new modes, CLI flags, or executable wrappers
  4. Guard Semantics Accuracy: Read-only checks → identity/digest → exactly-once callback → matching exit
  5. Artifact Ownership Clarity: Foundation ALONE creates/reads/validates/owns; EKS writes nothing
  6. Promotion Modes: Accurate uat-build vs. modeled distinction
  7. Workload Identity Shape: Exact schema (namespace, service_account, policy_json, description)
  8. Canonical Resource Identity: Explicit derivations for all three scopes
  9. Handler Behavior: Handlers recheck before mutation but cannot bypass pre-destroy gate
  10. Documentation Tests: Test module validates AUTHORIZED-ONLY prefix and forbidden patterns
  11. No Execution Claims: No UAT deployment/acceptance/verification claims

Test Structure:
  - ContractDocumentationTests: Validates core contract document presence, structure, and required sections
  - AuthorizationCommandTests: Validates every shell command block begins with '# AUTHORIZED-ONLY'
  - ForbiddenCommandTests: Validates documentation forbids manual mutations, commits, or dev operations
  - GuardSemanticsTests: Validates exact callback signature, field formats, status-exit agreement
  - ArtifactOwnershipTests: Validates foundation-only artifact ownership and package code constraints
  - ResourceIdentityTests: Validates canonical identity derivations for all three scopes
  - PromotionModeTests: Validates uat-build vs. modeled distinction and pre-destroy gate behavior
  - WorkloadIdentitySchemaTests: Validates exact identities map shape and field requirements
  - HandlerBehaviorTests: Validates handler rechecks and gate ordering
  - NoExecutionClaimsTests: Validates no execution/deployment/acceptance claims

Minimum Test Count: 8+ tests across 6+ test classes
"""

import os
import re
import unittest
from pathlib import Path


class ContractDocumentationTests(unittest.TestCase):
    """Validate EKS Platform contract document structure and required sections."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.assertTrue(self.contract_path.exists(), f"Contract document not found: {self.contract_path}")
        self.contract_content = self.contract_path.read_text()

    def test_contract_document_exists(self):
        """Contract document must exist and be readable."""
        self.assertTrue(len(self.contract_content) > 1000, "Contract document too short or empty")

    def test_contract_has_ownership_section(self):
        """Contract must explicitly state ownership of lifecycle-handlers.sh, verifiers.sh, and pre-destroy-guards.sh."""
        self.assertIn("lifecycle-handlers.sh", self.contract_content)
        self.assertIn("verifiers.sh", self.contract_content)
        self.assertIn("pre-destroy-guards.sh", self.contract_content)

    def test_contract_defines_canonical_identities(self):
        """Contract must define canonical identities for eks-platform, workload-identity, and platform-controllers."""
        self.assertIn("Canonical Resource Identities", self.contract_content)
        self.assertIn("eks-platform", self.contract_content)
        self.assertIn("workload-identity", self.contract_content)
        self.assertIn("platform-controllers", self.contract_content)

    def test_contract_explains_guard_callback_semantics(self):
        """Contract must explain exactly-once callback signature and field validation."""
        self.assertIn("record_pre_destroy_guard_result", self.contract_content)
        self.assertIn("exactly once", self.contract_content.lower())
        self.assertIn("PASS|FAIL", self.contract_content)

    def test_contract_explains_artifact_ownership(self):
        """Contract must explain that foundation alone owns evidence artifacts and package writes none."""
        self.assertIn("Evidence Artifact Ownership", self.contract_content)
        self.assertIn("Foundation-Owned Durable Artifact", self.contract_content)
        self.assertIn("Package Code: Zero Artifact Access", self.contract_content)


class AuthorizationCommandTests(unittest.TestCase):
    """Validate that every shell command block in the contract begins with '# AUTHORIZED-ONLY'."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_shell_blocks_have_authorization_prefix(self):
        """Every shell/bash code block must begin with '# AUTHORIZED-ONLY'."""
        # Extract all markdown code blocks with bash/shell language markers
        bash_block_pattern = r'```(?:bash|shell|sh)\s*\n(.+?)\n```'
        bash_blocks = re.findall(bash_block_pattern, self.contract_content, re.DOTALL)
        
        self.assertTrue(len(bash_blocks) > 0, "No shell code blocks found in contract (expected at least one)")
        
        for i, block in enumerate(bash_blocks):
            lines = block.strip().split('\n')
            # First non-empty line must be '# AUTHORIZED-ONLY'
            first_line = next((ln for ln in lines if ln.strip()), '')
            self.assertTrue(
                first_line.startswith('# AUTHORIZED-ONLY'),
                f"Shell block {i} does not begin with '# AUTHORIZED-ONLY': {first_line}"
            )

    def test_terraform_blocks_not_required(self):
        """Terraform code blocks (hcl) are informational and do not require AUTHORIZED-ONLY."""
        # This test documents that we only enforce AUTHORIZED-ONLY on bash/shell blocks
        hcl_block_pattern = r'```(?:hcl|terraform)\s*\n(.+?)\n```'
        hcl_blocks = re.findall(hcl_block_pattern, self.contract_content, re.DOTALL)
        # No assertion; just documenting that hcl blocks are allowed without the prefix


class ForbiddenCommandTests(unittest.TestCase):
    """Validate that documentation forbids manual mutations and dev operations."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_forbids_direct_terraform_apply(self):
        """Contract must forbid 'terraform apply' outside the orchestrator."""
        # Look for a section forbidding manual terraform apply
        self.assertIn("terraform apply", self.contract_content.lower())
        # Verify it's in a "Strictly Disallowed" or similar context
        self.assertIn("Strictly Disallowed", self.contract_content)

    def test_forbids_direct_handler_invocation(self):
        """Contract must forbid invoking handler/verifier/guard functions as commands."""
        self.assertIn("Strictly Disallowed", self.contract_content)
        forbidden_section = self.contract_content[self.contract_content.find("Strictly Disallowed"):]
        self.assertIn("handlers", forbidden_section.lower())
        self.assertIn("verifiers", forbidden_section.lower())

    def test_forbids_dev_operations(self):
        """Contract must forbid dev-mode mutations, commits, or direct Git operations."""
        forbidden_section = self.contract_content[self.contract_content.find("Strictly Disallowed"):]
        self.assertIn("dev", forbidden_section.lower())


class GuardSemanticsTests(unittest.TestCase):
    """Validate guard callback semantics: signature, field formats, status-exit agreement."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_callback_signature_defined(self):
        """Contract must define exact callback signature."""
        self.assertIn("record_pre_destroy_guard_result", self.contract_content)
        self.assertIn("<scope>", self.contract_content)
        self.assertIn("<sha256-digest>", self.contract_content)
        self.assertIn("<summary-code>", self.contract_content)

    def test_field_format_validation(self):
        """Contract must specify field format constraints (regex patterns or descriptions)."""
        self.assertIn("^sha256:[0-9a-f]{64}$", self.contract_content)
        self.assertIn("^[A-Z][A-Z0-9_]{0,63}$", self.contract_content)

    def test_status_exit_agreement(self):
        """Contract must require PASS+exit0 and FAIL+exit≠0 agreement."""
        self.assertIn("Exit code agreement", self.contract_content)
        self.assertIn("PASS", self.contract_content)
        self.assertIn("exit code", self.contract_content.lower())

    def test_exactly_once_callback_required(self):
        """Contract must require callback exactly once per invocation."""
        self.assertIn("exactly once", self.contract_content.lower())
        self.assertIn("GUARD_DUPLICATE_RESULT", self.contract_content)


class ArtifactOwnershipTests(unittest.TestCase):
    """Validate foundation-only artifact ownership and package code constraints."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_foundation_creates_artifact(self):
        """Contract must state foundation ALONE creates evidence artifact."""
        artifact_section = self.contract_content[self.contract_content.find("Evidence Artifact Ownership"):]
        self.assertIn("Foundation", artifact_section)
        self.assertIn("creates", artifact_section.lower())

    def test_package_writes_no_artifact(self):
        """Contract must state package code writes no artifact."""
        artifact_section = self.contract_content[self.contract_content.find("Package Code: Zero Artifact Access"):]
        self.assertIn("Creates **NO** evidence artifact", artifact_section)
        self.assertIn("Reads **NO** evidence artifact", artifact_section)
        self.assertIn("Writes **NO** evidence artifact", artifact_section)

    def test_callback_is_only_interface(self):
        """Contract must state callback invocation is the ONLY interface to evidence layer."""
        self.assertIn("callback invocation is the **only** interface", self.contract_content)

    def test_artifact_format_defined(self):
        """Contract must define evidence artifact format (JSON, ordered array, etc.)."""
        self.assertIn("Ordered JSON array", self.contract_content)


class ResourceIdentityTests(unittest.TestCase):
    """Validate canonical resource identity derivations for all three scopes."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_eks_platform_identity_derivation(self):
        """Contract must define eks-platform identity as Cluster ARN."""
        identity_section = self.contract_content[self.contract_content.find("Identity Derivation"):]
        self.assertIn("eks-platform", identity_section)
        self.assertIn("Cluster ARN", identity_section)

    def test_workload_identity_suffix(self):
        """Contract must define workload-identity as Cluster ARN + /workload-identity suffix."""
        identity_section = self.contract_content[self.contract_content.find("Identity Derivation"):]
        self.assertIn("workload-identity", identity_section)
        self.assertIn("/workload-identity", identity_section)

    def test_platform_controllers_suffix(self):
        """Contract must define platform-controllers as Cluster ARN + /platform-controllers suffix."""
        identity_section = self.contract_content[self.contract_content.find("Identity Derivation"):]
        self.assertIn("platform-controllers", identity_section)
        self.assertIn("/platform-controllers", identity_section)

    def test_example_identities(self):
        """Contract must provide example identity values with explicit suffix derivations."""
        self.assertIn("arn:aws:eks:", self.contract_content)
        # Verify example shows all three variants with same base ARN
        self.assertIn("arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster", self.contract_content)


class PromotionModeTests(unittest.TestCase):
    """Validate promotion mode distinction (uat-build vs. modeled) and pre-destroy gate behavior."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_uat_build_mode_requires_gate(self):
        """Contract must state uat-build mode requires pre-destroy guard gate."""
        self.assertIn("PROMOTION_MODE=uat-build", self.contract_content)
        uat_section = self.contract_content[self.contract_content.find("PROMOTION_MODE=uat-build"):]
        self.assertIn("Pre-Destroy Gate", uat_section)

    def test_modeled_mode_skips_gate(self):
        """Contract must state modeled mode skips pre-destroy guard."""
        self.assertIn("PROMOTION_MODE=modeled", self.contract_content)
        modeled_section = self.contract_content[self.contract_content.find("PROMOTION_MODE=modeled"):]
        self.assertIn("No pre-destroy guard", modeled_section)

    def test_gate_cannot_be_overridden(self):
        """Contract must state pre-destroy gate cannot be overridden by operators or package code."""
        self.assertIn("cannot be overridden", self.contract_content.lower())


class WorkloadIdentitySchemaTests(unittest.TestCase):
    """Validate exact workload-identity schema shape and field requirements."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_schema_section_exists(self):
        """Contract must have a Workload Identity Schema section."""
        self.assertIn("Workload Identity Schema", self.contract_content)

    def test_required_fields_documented(self):
        """Contract must document all four required fields: namespace, service_account, policy_json, description."""
        schema_section = self.contract_content[self.contract_content.find("Workload Identity Schema"):]
        self.assertIn("namespace", schema_section)
        self.assertIn("service_account", schema_section)
        self.assertIn("policy_json", schema_section)
        self.assertIn("description", schema_section)

    def test_field_types_documented(self):
        """Contract must specify field types (string, etc.)."""
        schema_section = self.contract_content[self.contract_content.find("Workload Identity Schema"):]
        self.assertIn("<string>", schema_section)

    def test_example_schema_provided(self):
        """Contract must provide an example identities map entry."""
        self.assertIn("mongodb", self.contract_content)
        self.assertIn("identities =", self.contract_content)


class HandlerBehaviorTests(unittest.TestCase):
    """Validate handler behavior: recheck before mutation but cannot bypass pre-destroy gate."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_destroy_handler_rechecks(self):
        """Contract must state destroy handler rechecks live state before mutation."""
        self.assertIn("Destroy Handler", self.contract_content)
        destroy_section = self.contract_content[self.contract_content.find("Destroy Handler"):]
        self.assertIn("Immediate recheck", destroy_section)
        self.assertIn("before the first mutation", destroy_section.lower())

    def test_recheck_is_not_sole_gate(self):
        """Contract must clarify recheck is not the sole destroy gate; pre-destroy guard is primary."""
        self.assertIn("not the sole destroy gate", self.contract_content.lower())
        self.assertIn("pre-destroy guard", self.contract_content)


class DeploymentStatusAccuracyTests(unittest.TestCase):
    """Validate the contract's deployment-status claims match reality.

    Originally this class (as NoExecutionClaimsTests) asserted the document
    always claims NOT deployed/accepted -- correct while the component was
    static scaffolding only. eks-platform, workload-identity, and
    platform-controllers are now live-provisioned, live-verified, and
    destroy-tested against real UAT (see #35/#37/#38/#41/#43/#44/#46 and
    their PRs) -- the document must say so, not the opposite."""

    def setUp(self):
        """Load the contract document."""
        self.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "eks-platform-contract.md"
        self.contract_content = self.contract_path.read_text()

    def test_states_deployed_and_verified_status(self):
        """Contract must state the component is deployed and verified in UAT."""
        self.assertIn("Deployed", self.contract_content)
        self.assertIn("live-verified", self.contract_content.lower())

    def test_does_not_claim_not_deployed(self):
        """Contract must not carry the stale 'NOT deployed' claim."""
        self.assertNotIn("NOT deployed", self.contract_content)

    def test_references_the_operator_runbook_procedure(self):
        """Contract must point operators to the actual how-to procedure."""
        self.assertIn("Operator Runbook", self.contract_content)


if __name__ == "__main__":
    unittest.main()
