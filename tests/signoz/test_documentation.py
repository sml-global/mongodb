"""
SigNoz Platform Contract Documentation Tests

Tests verify that the SigNoz platform contract markdown file contains:
1. All required sections
2. Required keywords in each section
3. Explicit statement of "No AWS prerequisites"
4. ClickHouse secret bootstrap script requirements
"""

import unittest
import re
from pathlib import Path


class TestSigNozPlatformContract(unittest.TestCase):
    """Test suite for SigNoz Platform Contract documentation"""

    @classmethod
    def setUpClass(cls):
        """Load the SigNoz contract markdown file"""
        cls.contract_path = Path(__file__).parent.parent.parent / "docs" / "references" / "signoz-platform-contract.md"
        assert cls.contract_path.exists(), f"SigNoz contract not found: {cls.contract_path}"
        
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
    
    def test_10_aws_prerequisites_explicitly_none(self):
        """CRITICAL: AWS Prerequisites section must explicitly state 'None'"""
        # Use str.find for robust parsing instead of split/index
        aws_prereq_pos = self.content.find("### AWS Prerequisites")
        self.assertGreater(aws_prereq_pos, 0, 
                          "Missing 'AWS Prerequisites' subsection header")
        
        # Extract the AWS Prerequisites section (next 1000 chars should contain the statement)
        aws_section = self.content[aws_prereq_pos:aws_prereq_pos + 1000]
        self.assertIn("None", aws_section,
                      "AWS Prerequisites section must state 'None'")
    
    def test_11_kubernetes_native_explicitly_stated(self):
        """Contract must explicitly state SigNoz is Kubernetes-native"""
        self.assertIn("Kubernetes-native", self.content,
                      "Missing explicit statement that SigNoz is 'Kubernetes-native'")
    
    def test_12_no_aws_irsa_requirement(self):
        """Contract must explicitly state no IRSA roles needed"""
        # SigNoz should NOT mention IRSA for AWS pod identity
        identities_section = self.content[self.content.find("## Identities"):self.content.find("## Guard")]
        self.assertIn("AWS Pod Identity", identities_section,
                      "Missing 'AWS Pod Identity' subsection")
        self.assertIn("None", identities_section,
                      "AWS Pod Identity section should state 'None'")
    
    def test_13_no_aws_s3_requirement(self):
        """Contract must NOT require S3 buckets"""
        prerequisites = self.content[self.content.find("## Prerequisites"):self.content.find("## Service Dependencies")]
        self.assertNotIn("oms-pbm-backups", prerequisites,
                        "SigNoz should not require MongoDB backup bucket")
        self.assertNotIn("oms-cnpg-wal-archive", prerequisites,
                        "SigNoz should not require PostgreSQL WAL bucket")
    
    def test_14_no_aws_kms_requirement(self):
        """Contract must NOT require KMS keys in AWS Prerequisites section"""
        # Extract AWS Prerequisites section specifically
        aws_prereq_pos = self.content.find("### AWS Prerequisites")
        self.assertGreater(aws_prereq_pos, 0, "Missing AWS Prerequisites section")
        
        # Get the AWS Prerequisites subsection (until next ### or ## section)
        next_section_pos = self.content.find("###", aws_prereq_pos + 1)
        if next_section_pos == -1:
            next_section_pos = self.content.find("##", aws_prereq_pos + 4)
        
        aws_section = self.content[aws_prereq_pos:next_section_pos]
        # AWS Prerequisites section should NOT mention KMS
        self.assertNotIn("KMS", aws_section,
                        "SigNoz AWS Prerequisites should not require KMS keys")
    
    def test_15_clickhouse_secret_mentioned_in_prerequisites(self):
        """Prerequisites must explicitly reference ClickHouse secret creation"""
        self.assertIn("signoz-clickhouse", self.content,
                      "Missing 'signoz-clickhouse' secret reference in prerequisites")
    
    def test_16_bootstrap_script_referenced(self):
        """Prerequisites must reference the bootstrap script"""
        self.assertIn("create-signoz-clickhouse-secret.sh", self.content,
                      "Missing 'create-signoz-clickhouse-secret.sh' script reference")
    
    def test_17_clickhouse_password_env_var_documented(self):
        """Prerequisites must document CLICKHOUSE_ROOT_PASSWORD environment variable"""
        self.assertIn("CLICKHOUSE_ROOT_PASSWORD", self.content,
                      "Missing 'CLICKHOUSE_ROOT_PASSWORD' environment variable documentation")
    
    def test_18_guard_semantics_includes_seven_step_protocol(self):
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
    
    def test_19_guard_semantics_mentions_pre_destroy(self):
        """Guard Semantics must reference pre-destroy guard"""
        self.assertIn("pre-destroy", self.content.lower() or "pre_destroy",
                      "Missing 'pre-destroy' guard reference")
    
    def test_20_guard_semantics_mentions_sha256(self):
        """Guard Semantics must mention SHA-256 digest"""
        self.assertIn("SHA-256", self.content,
                      "Missing 'SHA-256' digest reference")
    
    def test_21_kubernetes_secrets_subsection_exists(self):
        """Identities must have Kubernetes Secrets subsection"""
        self.assertIn("### Kubernetes Secrets", self.content,
                      "Missing 'Kubernetes Secrets' subsection in Identities")
    
    def test_22_lifecycle_mentions_provisioning(self):
        """Lifecycle must include Provisioning phase"""
        self.assertIn("Provisioning", self.content,
                      "Missing 'Provisioning' in Lifecycle")
    
    def test_23_lifecycle_mentions_destruction(self):
        """Lifecycle must include Destruction phase"""
        self.assertIn("Destruction", self.content,
                      "Missing 'Destruction' in Lifecycle")
    
    def test_24_component_overview_mentions_version_source(self):
        """Component Overview must reference version configuration"""
        self.assertIn("SIGNOZ_VERSION", self.content,
                      "Missing SIGNOZ_VERSION configuration reference")
    
    def test_25_configuration_reference_complete(self):
        """Configuration Reference must include all key parameters"""
        required_params = [
            "SIGNOZ_VERSION",
            "SIGNOZ_STORAGE_CLASS",
            "SIGNOZ_REPLICA_COUNT",
            "SIGNOZ_RETENTION_DAYS"
        ]
        
        for param in required_params:
            self.assertIn(param, self.content,
                          f"Missing configuration parameter: {param}")
    
    def test_26_contract_has_minimum_length(self):
        """Contract should be comprehensive (not a stub)"""
        self.assertGreater(len(self.content), 5000,
                           f"Contract appears too short ({len(self.content)} bytes). May be incomplete.")
    
    def test_27_kubernetes_prerequisites_subsection_exists(self):
        """Prerequisites must have Kubernetes Prerequisites subsection"""
        self.assertIn("### Kubernetes Prerequisites", self.content,
                      "Missing 'Kubernetes Prerequisites' subsection header")
    
    def test_28_platform_prerequisites_subsection_exists(self):
        """Prerequisites must have Platform Prerequisites subsection"""
        self.assertIn("### Platform Prerequisites", self.content,
                      "Missing 'Platform Prerequisites' subsection header")
    
    def test_29_clickhouse_secret_creation_required_before_gitops(self):
        """Prerequisites must note that ClickHouse secret must be created before GitOps"""
        prerequisites_text = self.content[self.content.find("## Prerequisites"):self.content.find("## Service Dependencies")]
        self.assertIn("before", prerequisites_text.lower(),
                      "Prerequisites should specify when bootstrap script must be run")
    
    def test_30_component_overview_mentions_clickhouse(self):
        """Component Overview must mention ClickHouse backend"""
        self.assertIn("ClickHouse", self.content,
                      "Missing 'ClickHouse' backend reference")
    
    def test_31_no_irsa_mentioned_for_signoz(self):
        """SigNoz should not use IRSA roles"""
        # IRSA might be mentioned in general context, but SigNoz subsection should be clear
        identities_section = self.content[self.content.find("## Identities"):self.content.find("## Guard")]
        aws_subsection = identities_section[identities_section.find("### AWS Pod Identity"):identities_section.find("###", identities_section.find("### AWS Pod Identity") + 1)]
        self.assertIn("None", aws_subsection,
                      "AWS Pod Identity subsection should clearly state 'None'")


if __name__ == "__main__":
    unittest.main()
