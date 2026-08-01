"""
PostgreSQL Platform Contract Documentation Tests

Tests verify that the PostgreSQL platform contract markdown file contains:
1. All required sections
2. Required keywords in each section
3. Proper documentation structure for operational reference
"""

import unittest
import re
from pathlib import Path


class TestPostgreSQLPlatformContract(unittest.TestCase):
    """Test suite for PostgreSQL Platform Contract documentation"""

    @classmethod
    def setUpClass(cls):
        """Load the PostgreSQL contract markdown file"""
        cls.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md"
        assert cls.contract_path.exists(), f"PostgreSQL contract not found: {cls.contract_path}"
        
        with open(cls.contract_path, "r") as f:
            cls.content = f.read()
    
    def test_01_contract_file_exists(self):
        """Contract markdown file must exist"""
        self.assertTrue(self.contract_path.exists(), f"File not found: {self.contract_path}")
        self.assertTrue(self.contract_path.is_file(), f"Not a file: {self.contract_path}")
    
    def test_02_ownership_section_exists(self):
        """Contract must have Ownership & Maintenance section"""
        self.assertIn("## Ownership & Maintenance", self.content,
                      "Missing 'Ownership & Maintenance' section header")
    
    def test_03_component_overview_section_exists(self):
        """Contract must have Component Overview section"""
        self.assertIn("## Component Overview", self.content,
                      "Missing 'Component Overview' section header")
    
    def test_04_lifecycle_section_exists(self):
        """Contract must have Lifecycle section"""
        self.assertIn("## Lifecycle", self.content,
                      "Missing 'Lifecycle' section header")
    
    def test_05_identities_section_exists(self):
        """Contract must have Identities section"""
        self.assertIn("## Identities", self.content,
                      "Missing 'Identities' section header")
    
    def test_06_guard_semantics_section_exists(self):
        """Contract must have Guard Semantics section"""
        self.assertIn("## Guard Semantics", self.content,
                      "Missing 'Guard Semantics' section header")
    
    def test_07_prerequisites_section_exists(self):
        """Contract must have Prerequisites section"""
        self.assertIn("## Prerequisites", self.content,
                      "Missing 'Prerequisites' section header")
    
    def test_08_service_dependencies_section_exists(self):
        """Contract must have Service Dependencies section"""
        self.assertIn("## Service Dependencies", self.content,
                      "Missing 'Service Dependencies' section header")
    
    def test_09_configuration_reference_section_exists(self):
        """Contract must have Configuration Reference section"""
        self.assertIn("## Configuration Reference", self.content,
                      "Missing 'Configuration Reference' section header")
    
    def test_10_prerequisites_mentions_irsa_role(self):
        """Prerequisites section must reference IRSA role"""
        self.assertIn("oms-postgresql-operator-role", self.content,
                      "Missing IRSA role reference 'oms-postgresql-operator-role'")
    
    def test_11_prerequisites_mentions_s3_bucket(self):
        """Prerequisites section must reference S3 bucket"""
        self.assertIn("oms-cnpg-wal-archive", self.content,
                      "Missing S3 bucket reference 'oms-cnpg-wal-archive'")
    
    def test_12_prerequisites_mentions_kms_key(self):
        """Prerequisites section must reference KMS key"""
        self.assertIn("oms-postgresql-cluster-key", self.content,
                      "Missing KMS key reference 'oms-postgresql-cluster-key'")
    
    def test_13_guard_semantics_includes_seven_step_protocol(self):
        """Guard Semantics must describe full 7-step protocol"""
        required_steps = [
            "Seam Read",
            "Parse",
            "Validate",
            "Identity",
            "SHA-256 Digest",
            "Callback",
            "Return"
        ]
        
        for step in required_steps:
            self.assertIn(f"#### {step}", self.content,
                          f"Missing guard semantics step: {step}")
    
    def test_14_guard_semantics_mentions_pre_destroy(self):
        """Guard Semantics must reference pre-destroy guard"""
        self.assertIn("pre-destroy", self.content.lower() or "pre_destroy",
                      "Missing 'pre-destroy' guard reference")
    
    def test_15_guard_semantics_mentions_sha256(self):
        """Guard Semantics must mention SHA-256 digest"""
        self.assertIn("SHA-256", self.content,
                      "Missing 'SHA-256' digest reference")
    
    def test_16_identities_mentions_irsa(self):
        """Identities section must mention IRSA"""
        self.assertIn("IRSA", self.content,
                      "Missing 'IRSA' in Identities section")
    
    def test_17_identities_mentions_iam_permissions(self):
        """Identities section must mention IAM Permissions"""
        self.assertIn("IAM Permissions", self.content,
                      "Missing 'IAM Permissions' subsection")
    
    def test_18_identities_mentions_kubernetes_secrets(self):
        """Identities section must mention Kubernetes Secrets"""
        self.assertIn("Kubernetes Secrets", self.content,
                      "Missing 'Kubernetes Secrets' subsection")
    
    def test_19_lifecycle_mentions_provisioning(self):
        """Lifecycle must include Provisioning phase"""
        self.assertIn("Provisioning", self.content,
                      "Missing 'Provisioning' in Lifecycle")
    
    def test_20_lifecycle_mentions_destruction(self):
        """Lifecycle must include Destruction phase"""
        self.assertIn("Destruction", self.content,
                      "Missing 'Destruction' in Lifecycle")
    
    def test_21_prerequisites_mentions_terraform(self):
        """Prerequisites should mention Terraform validation"""
        self.assertIn("terraform", self.content.lower(),
                      "Missing 'terraform' reference in prerequisites")
    
    def test_22_prerequisites_mentions_aws_outputs(self):
        """Prerequisites section must reference AWS outputs from Phase 2"""
        self.assertIn("Phase 2", self.content,
                      "Missing 'Phase 2' reference for AWS prerequisites")
    
    def test_23_component_overview_mentions_engine_split(self):
        """Component Overview must reference the Dev/SIT (CNPG) vs UAT/Prod
        (Aurora) engine split (Issue #4: POSTGRESQL_VERSION was never a real
        env-schema key or consumed anywhere)."""
        self.assertIn("Aurora", self.content,
                      "Missing Aurora engine-split reference")

    def test_24_configuration_reference_documents_dead_key_removal(self):
        """Configuration Reference must document the Issue #4 removal of the
        dead env-schema keys (POSTGRESQL_STORAGE_CLASS, POSTGRESQL_REPLICA_COUNT,
        POSTGRESQL_IMAGE_REPO, POSTGRESQL_OPERATOR_VERSION,
        POSTGRESQL_BACKUP_ENABLED, POSTGRESQL_BACKUP_SCHEDULE), rather than
        presenting them as live configuration."""
        self.assertIn("Issue #4", self.content,
                      "Missing Issue #4 cleanup reference")
    
    def test_25_contract_has_minimum_length(self):
        """Contract should be comprehensive (not a stub)"""
        self.assertGreater(len(self.content), 5000,
                           f"Contract appears too short ({len(self.content)} bytes). May be incomplete.")
    
    def test_26_prerequisites_mentions_aws_prerequisites_header(self):
        """Prerequisites must have AWS Prerequisites subsection"""
        self.assertIn("### AWS Prerequisites", self.content,
                      "Missing 'AWS Prerequisites' subsection header")
    
    def test_27_prerequisites_mentions_kubernetes_prerequisites_header(self):
        """Prerequisites must have Kubernetes Prerequisites subsection"""
        self.assertIn("### Kubernetes Prerequisites", self.content,
                      "Missing 'Kubernetes Prerequisites' subsection header")
    
    def test_28_identities_mentions_service_account(self):
        """Identities section must mention ServiceAccount"""
        self.assertIn("ServiceAccount", self.content,
                      "Missing 'ServiceAccount' in Identities section")
    
    def test_29_guard_mentions_replication_health(self):
        """Guard Semantics must reference replication health checks"""
        self.assertIn("replication", self.content.lower(),
                      "Missing 'replication' health reference in Guard Semantics")
    
    def test_30_component_overview_mentions_cloudnativepg(self):
        """Component Overview must mention CloudNativePG operator"""
        self.assertIn("CloudNativePG", self.content,
                      "Missing 'CloudNativePG' operator reference")


class TestPostgreSQLDocumentationOrchestrationFixes(unittest.TestCase):
    """Tests for PostgreSQL orchestration documentation fixes (Task 5 additions)"""

    def test_contract_references_real_pod_name(self):
        """Contract must reference oms-postgresql-1 pod name consistently"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertIn("oms-postgresql-1", content)
        self.assertNotIn("exec -it postgresql-1", content)

    def test_contract_references_gp3_postgresql_storageclass(self):
        """Contract must reference the gp3-postgresql StorageClass at its real path"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        # After C1 fix, the StorageClass file lives under gitops/postgresql/base/,
        # not k8s/base/ (MongoDB's kustomize base) or the old missing k8s/base/storage-classes.yaml.
        self.assertIn("gitops/postgresql/base/storageclass-gp3-postgresql.yaml", content)
        self.assertNotIn("k8s/base/storageclass-gp3-postgresql.yaml", content)
        self.assertNotIn("k8s/base/storage-classes.yaml", content)

    def test_contract_references_real_provisioning_command(self):
        """Contract must reference scripts/provision.sh pg command"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_contract_has_no_stale_uat_decommission_warning(self):
        """Contract must not contain stale UAT decommission warnings"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertNotIn("requires a manual decommission step", content)

    def test_component_catalog_references_real_provisioning_command(self):
        """Component catalog must reference scripts/provision.sh pg command"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "component-catalog.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_verification_commands_reference_real_cluster_name(self):
        """Verification commands must reference oms-postgresql-1 pod name"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "verification-commands.md").read_text()
        self.assertIn("oms-postgresql-1", content)

    def test_index_has_no_stale_uat_decommission_followup(self):
        """Index must not contain stale UAT decommission follow-up notes"""
        content = (Path(__file__).parent.parent.parent / "docs" / "index.md").read_text()
        self.assertNotIn("needs an explicit, manual decommission step", content)

    def test_contract_postgresql_cluster_name_defaults_to_oms_postgresql(self):
        """Contract must define POSTGRESQL_CLUSTER_NAME default as oms-postgresql (I4 fix)"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertIn('POSTGRESQL_CLUSTER_NAME:-"oms-postgresql"', content)
        self.assertNotIn('POSTGRESQL_CLUSTER_NAME:-"postgresql"}', content)

    def test_recovery_procedures_documents_devsit_cnpg_restore(self):
        """recovery-procedures.md must cover Dev/SIT CNPG restore, not just Aurora"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "recovery-procedures.md").read_text()
        self.assertIn("Dev/SIT PostgreSQL Recovery (CNPG)", content)
        self.assertIn("s3://oms-postgresql-backup", content)
        self.assertIn("recoveryTarget", content)

    def test_platform_contract_links_to_devsit_recovery_section(self):
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertIn("recovery-procedures.md", content)


if __name__ == "__main__":
    unittest.main()
