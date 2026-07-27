#!/usr/bin/env python3
"""
tests/signoz/test_verifiers.py

Test bash verifier fragment validation for SigNoz.
Tests: 8

- test_verifier_fragment_sources_internal_verifiers
- test_verifier_fragment_sources_internal_pre_destroy_guards
- test_scope_verifiers_signoz_exports_canonical_symbol
- test_scope_verifiers_signoz_exports_pre_destroy_symbol
- test_scope_verifiers_signoz_observability_exports_canonical_symbol
- test_scope_verifiers_signoz_observability_exports_pre_destroy_symbol
- test_guard_contract_uses_seam_callback_mechanism
- test_pre_destroy_guard_computes_sha256_digest
"""

import unittest
import subprocess
from pathlib import Path


class TestSignozVerifiers(unittest.TestCase):
    """Validate SigNoz bash verifier fragments."""

    @classmethod
    def setUpClass(cls):
        """Load verifier files."""
        cls.verifiers_path = (
            Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages" 
            / "50-signoz" / "internal" / "verifiers.sh"
        )
        cls.pre_destroy_guards_path = (
            Path(__file__).parent.parent.parent / "scripts" / "lib" / "packages" 
            / "50-signoz" / "internal" / "pre-destroy-guards.sh"
        )
        cls.scope_verifiers_path = (
            Path(__file__).parent.parent.parent / "scripts" / "lib" / "scope-verifiers.d" 
            / "50-signoz.sh"
        )
        
        # Load file content
        cls.verifiers_content = cls._load_file(cls.verifiers_path)
        cls.pre_destroy_guards_content = cls._load_file(cls.pre_destroy_guards_path)
        cls.scope_verifiers_content = cls._load_file(cls.scope_verifiers_path)

    @staticmethod
    def _load_file(path):
        """Load file content."""
        if not path.exists():
            return ""
        with open(path, 'r') as f:
            return f.read()

    def test_verifier_fragment_sources_internal_verifiers(self):
        """Scope verifiers must source internal verifiers.sh."""
        self.assertIn("50-signoz/internal/verifiers.sh", self.scope_verifiers_content,
            "scope-verifiers.d/50-signoz.sh must source verifiers.sh")

    def test_verifier_fragment_sources_internal_pre_destroy_guards(self):
        """Scope verifiers must source internal pre-destroy-guards.sh."""
        self.assertIn("50-signoz/internal/pre-destroy-guards.sh", self.scope_verifiers_content,
            "scope-verifiers.d/50-signoz.sh must source pre-destroy-guards.sh")

    def test_scope_verifiers_signoz_exports_canonical_symbol(self):
        """Must export scope_registry_verify_signoz."""
        self.assertIn("scope_registry_verify_signoz", self.scope_verifiers_content,
            "Must export scope_registry_verify_signoz")
        self.assertIn("signoz_internal_signoz_verifier", self.scope_verifiers_content,
            "Must delegate to signoz_internal_signoz_verifier")

    def test_scope_verifiers_signoz_exports_pre_destroy_symbol(self):
        """Must export verify_signoz_pre_destroy."""
        self.assertIn("verify_signoz_pre_destroy", self.scope_verifiers_content,
            "Must export verify_signoz_pre_destroy")
        self.assertIn("signoz_internal_signoz_pre_destroy_guard", self.scope_verifiers_content,
            "Must delegate to signoz_internal_signoz_pre_destroy_guard")

    def test_scope_verifiers_signoz_observability_exports_canonical_symbol(self):
        """Must export scope_registry_verify_signoz_observability."""
        self.assertIn("scope_registry_verify_signoz_observability", self.scope_verifiers_content,
            "Must export scope_registry_verify_signoz_observability")
        self.assertIn("signoz_internal_signoz_observability_verifier", self.scope_verifiers_content,
            "Must delegate to signoz_internal_signoz_observability_verifier")

    def test_scope_verifiers_signoz_observability_exports_pre_destroy_symbol(self):
        """Must export verify_signoz_observability_pre_destroy."""
        self.assertIn("verify_signoz_observability_pre_destroy", self.scope_verifiers_content,
            "Must export verify_signoz_observability_pre_destroy")
        self.assertIn("signoz_internal_signoz_observability_pre_destroy_guard", self.scope_verifiers_content,
            "Must delegate to signoz_internal_signoz_observability_pre_destroy_guard")

    def test_guard_contract_uses_seam_callback_mechanism(self):
        """Pre-destroy guards must use seam for observations."""
        self.assertIn("signoz_internal_live_guard_observations", self.pre_destroy_guards_content,
            "Guards must use signoz_internal_live_guard_observations seam")
        self.assertIn("record_pre_destroy_guard_result", self.pre_destroy_guards_content,
            "Guards must invoke record_pre_destroy_guard_result callback")

    def test_pre_destroy_guard_computes_sha256_digest(self):
        """Pre-destroy guards must compute SHA-256 digest."""
        self.assertIn("sha256", self.pre_destroy_guards_content,
            "Guards must compute SHA-256 digest")
        self.assertIn("signoz_internal_guard_sha256", self.pre_destroy_guards_content,
            "Guards must use signoz_internal_guard_sha256 helper")
        self.assertIn("digest_hex", self.pre_destroy_guards_content,
            "Guards must store computed digest")


if __name__ == '__main__':
    unittest.main()
