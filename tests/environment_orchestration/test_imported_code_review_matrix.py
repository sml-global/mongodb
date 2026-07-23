import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "scripts" / "validate-imported-code-review-matrix.py"
MATRIX_PATH = REPO_ROOT / "docs" / "operations" / "imported-code-review-matrix.md"
SPEC = importlib.util.spec_from_file_location(
    "validate_imported_code_review_matrix", VALIDATOR_PATH
)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


HEADER = "| ID | Domain | Source | Target | Disposition | Evidence | Status |"
SEPARATOR = "| --- | --- | --- | --- | --- | --- | --- |"


def row(
    identifier,
    domain,
    source,
    target,
    disposition="KEEP",
    evidence="docs/review.md",
    status="REVIEWED",
):
    return {
        "ID": identifier,
        "Domain": domain,
        "Source": source,
        "Target": target,
        "Disposition": disposition,
        "Evidence": evidence,
        "Status": status,
    }


VALID_MIXED_DOMAIN_ROWS = [
    row(
        "FOUNDATION-0001",
        "FOUNDATION",
        "imported/terraform/backend.tf",
        "platform-prerequisites/terraform/dev/backend.tf",
    ),
    row(
        "EKS-0001",
        "EKS",
        "imported/eks/cluster.tf",
        "platform-prerequisites/terraform/dev/eks.tf",
        disposition="REWRITE",
        evidence="docs/reviews/eks-cluster.md",
        status="VERIFIED",
    ),
    row(
        "FOUNDATION-0002",
        "FOUNDATION",
        "imported/terraform/providers.tf",
        "platform-prerequisites/terraform/dev/providers.tf",
        disposition="REPLACE",
        evidence="docs/reviews/providers.md",
    ),
    row(
        "DATA-0001",
        "DATA",
        "imported/data/mongodb.tf",
        "platform-prerequisites/terraform/mongodb/main.tf",
        evidence="docs/reviews/mongodb.md",
        status="VERIFIED",
    ),
    row(
        "BOOMI-0001",
        "BOOMI",
        "imported/boomi/audit.groovy",
        "scripts/groovy/boomi/audit.groovy",
        disposition="REWRITE",
        evidence="docs/reviews/boomi-audit.md",
    ),
    row(
        "DOCS-0001",
        "DOCS",
        "imported/docs/legacy-runbook.md",
        "docs/history/legacy-runbook.md",
        disposition="REJECT",
        evidence="docs/reviews/legacy-runbook.md",
        status="PROPOSED",
    ),
]

EXPECTED_FOUNDATION_SOURCES = {
    *(f"mongodb@29353d6:config/environments/uat.env#{key}" for key in (
        "ENVIRONMENT",
        "EXPECTED_AWS_ACCOUNT_ID",
        "AWS_REGION",
        "EKS_CLUSTER_NAME",
        "BOOMI_NAMESPACE",
        "TF_STATE_BUCKET",
        "TF_STATE_REGION",
        "ACCESS_GOVERNANCE_STATE_KEY",
        "EKS_ACCESS_STATE_KEY",
    )),
    "mongodb@29353d6:scripts/lib/platform-env.sh",
    "mongodb@29353d6:scripts/bootstrap-terraform-s3-backend.sh",
    "mongodb@29353d6:scripts/validate-uat-workforce-principals.sh",
    "mongodb@29353d6:scripts/validate-uat-workforce-principals.sh#generated-auto-tfvars",
    "mongodb@29353d6:scripts/provision-uat-access.sh",
    "mongodb@29353d6:.gitignore#uat-local-inputs",
    *(f"mongodb@29353d6:platform-prerequisites/terraform/{root}/{name}" for root in (
        "access-governance",
        "eks-access",
    ) for name in (
        ".terraform.lock.hcl",
        "versions.tf",
        "variables.tf",
        "main.tf",
        "outputs.tf",
        "uat.tfvars",
    )),
    "mongodb@29353d6:platform-prerequisites/terraform/access-governance/main.tf#aws_accessanalyzer_analyzer.uat_account",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#local.principals",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_entry.workforce",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.cluster_admin",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.boomi_admin",
}


def markdown_table(rows):
    lines = [HEADER, SEPARATOR]
    for item in rows:
        lines.append(
            "| {ID} | {Domain} | {Source} | {Target} | {Disposition} | "
            "{Evidence} | {Status} |".format(**item)
        )
    return "\n".join(lines)


class ImportedCodeReviewMatrixTestCase(unittest.TestCase):
    def write_document(self, content):
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        path = Path(temporary_directory.name) / "matrix.md"
        path.write_text(content, encoding="utf-8")
        return path

    def assert_matrix_error(self, callable_under_test, *args):
        with self.assertRaises(Exception) as raised:
            callable_under_test(*args)
        return str(raised.exception)


class ParseMatrixTests(ImportedCodeReviewMatrixTestCase):
    def test_parse_matrix_rejects_a_document_without_the_canonical_table(self):
        for content in ("", "# Imported code review\n\nNo decisions yet.\n"):
            with self.subTest(content=content):
                message = self.assert_matrix_error(
                    validator.parse_matrix, self.write_document(content)
                )
                self.assertIn("table", message.lower())

    def test_parse_matrix_reads_one_table_and_ignores_surrounding_prose(self):
        document = (
            "# Imported code review\n\n"
            "Owner notes may contain prose | with punctuation.\n\n"
            f"{markdown_table(VALID_MIXED_DOMAIN_ROWS)}\n\n"
            "Reviewers update the table above after evidence is captured.\n"
        )

        parsed_rows = validator.parse_matrix(self.write_document(document))

        self.assertEqual(VALID_MIXED_DOMAIN_ROWS, parsed_rows)

    def test_parse_matrix_rejects_unknown_extra_missing_and_reordered_columns(self):
        invalid_headers = {
            "unknown": "| ID | Area | Source | Target | Disposition | Evidence | Status |",
            "extra": (
                "| ID | Domain | Source | Target | Disposition | Evidence | Status | Owner |"
            ),
            "missing": "| ID | Domain | Source | Target | Disposition | Status |",
            "reordered": (
                "| ID | Domain | Target | Source | Disposition | Evidence | Status |"
            ),
            "id not first": (
                "| Domain | ID | Source | Target | Disposition | Evidence | Status |"
            ),
        }
        body = (
            "| FOUNDATION-0001 | FOUNDATION | imported/main.tf | "
            "platform/main.tf | KEEP | docs/review.md | REVIEWED |"
        )

        for case, invalid_header in invalid_headers.items():
            with self.subTest(case=case):
                message = self.assert_matrix_error(
                    validator.parse_matrix,
                    self.write_document(f"{invalid_header}\n{SEPARATOR}\n{body}\n"),
                )
                self.assertIn("header", message.lower())

    def test_parse_matrix_allows_a_supporting_noncanonical_table(self):
        supporting_table = (
            "| Name | Domain | Decision |\n"
            "| --- | --- | --- |\n"
            "| old-module | FOUNDATION | KEEP |"
        )
        document = (
            f"{markdown_table(VALID_MIXED_DOMAIN_ROWS)}\n\n{supporting_table}\n"
        )

        self.assertEqual(
            VALID_MIXED_DOMAIN_ROWS,
            validator.parse_matrix(self.write_document(document)),
        )

    def test_parse_matrix_rejects_a_second_canonical_table(self):
        document = (
            f"{markdown_table(VALID_MIXED_DOMAIN_ROWS[:1])}\n\n"
            f"{markdown_table(VALID_MIXED_DOMAIN_ROWS[1:2])}\n"
        )

        message = self.assert_matrix_error(
            validator.parse_matrix, self.write_document(document)
        )

        self.assertIn("table", message.lower())

    def test_parse_matrix_rejects_a_malformed_row_without_truncating_the_table(self):
        malformed_row = (
            "| FOUNDATION-0001 | FOUNDATION | src/main.tf | target/main.tf | "
            "KEEP | docs/review.md | REVIEWED"
        )
        valid_row = markdown_table(VALID_MIXED_DOMAIN_ROWS[1:2]).splitlines()[2]
        document = f"{HEADER}\n{SEPARATOR}\n{malformed_row}\n{valid_row}\n"

        message = self.assert_matrix_error(
            validator.parse_matrix, self.write_document(document)
        )

        self.assertIn("row", message.lower())

    def test_parse_matrix_rejects_a_separator_with_the_wrong_column_count(self):
        short_separator = "| --- | --- | --- | --- | --- | --- |"
        document = f"{HEADER}\n{short_separator}\n"

        message = self.assert_matrix_error(
            validator.parse_matrix, self.write_document(document)
        )

        self.assertIn("separator", message.lower())

    def test_parse_matrix_rejects_outer_pipe_less_rows_and_repeated_separators(self):
        outer_pipe_less = (
            "FOUNDATION-0001 | FOUNDATION | src/main.tf | target/main.tf | "
            "KEEP | docs/review.md | REVIEWED"
        )
        documents = {
            "outer-pipe-less row": f"{HEADER}\n{SEPARATOR}\n{outer_pipe_less}\n",
            "repeated separator": f"{HEADER}\n{SEPARATOR}\n{SEPARATOR}\n",
        }

        for case, document in documents.items():
            with self.subTest(case=case):
                message = self.assert_matrix_error(
                    validator.parse_matrix, self.write_document(document)
                )
                self.assertIn("row", message.lower())

    def test_parse_matrix_reports_multiple_structural_row_errors(self):
        incomplete = (
            "| FOUNDATION-0001 | FOUNDATION | src/one.tf | target/one.tf | "
            "KEEP | docs/one.md | REVIEWED"
        )
        short = (
            "| FOUNDATION-0002 | FOUNDATION | src/two.tf | target/two.tf | "
            "KEEP | docs/two.md |"
        )
        document = f"{HEADER}\n{SEPARATOR}\n{incomplete}\n{short}\n"

        message = self.assert_matrix_error(
            validator.parse_matrix, self.write_document(document)
        )

        self.assertIn("line 3", message.lower())
        self.assertIn("line 4", message.lower())


class ValidateRowsTests(ImportedCodeReviewMatrixTestCase):
    def test_validate_rows_rejects_an_empty_matrix(self):
        message = self.assert_matrix_error(validator.validate_rows, [])

        self.assertIn("row", message.lower())

    def test_validate_rows_accepts_a_valid_mixed_domain_matrix(self):
        self.assertIsNone(validator.validate_rows(VALID_MIXED_DOMAIN_ROWS))

    def test_validate_rows_requires_domain_ids_to_be_unique_and_sequential(self):
        invalid_rows = [
            row("FOUNDATION-0001", "FOUNDATION", "src/one.tf", "target/one.tf"),
            row("EKS-0001", "EKS", "src/eks.tf", "target/eks.tf"),
            row("FOUNDATION-0003", "FOUNDATION", "src/three.tf", "target/three.tf"),
            row("FOUNDATION-0003", "FOUNDATION", "src/four.tf", "target/four.tf"),
        ]

        message = self.assert_matrix_error(validator.validate_rows, invalid_rows)

        self.assertIn("FOUNDATION-0002", message)
        self.assertIn("FOUNDATION-0003", message)
        self.assertIn("unique", message.lower())

    def test_validate_rows_rejects_malformed_mismatched_and_out_of_order_ids(self):
        cases = {
            "too few digits": [
                row("FOUNDATION-1", "FOUNDATION", "src/one.tf", "target/one.tf")
            ],
            "leading material": [
                row("xFOUNDATION-0001", "FOUNDATION", "src/one.tf", "target/one.tf")
            ],
            "trailing material": [
                row("FOUNDATION-0001-extra", "FOUNDATION", "src/one.tf", "target/one.tf")
            ],
            "non-ascii digits": [
                row("FOUNDATION-٠٠٠١", "FOUNDATION", "src/one.tf", "target/one.tf")
            ],
            "domain mismatch": [
                row("EKS-0001", "FOUNDATION", "src/one.tf", "target/one.tf")
            ],
            "does not start at 0001": [
                row("DATA-0002", "DATA", "src/one.tf", "target/one.tf")
            ],
            "out of order": [
                row("BOOMI-0001", "BOOMI", "src/one.tf", "target/one.tf"),
                row("BOOMI-0003", "BOOMI", "src/three.tf", "target/three.tf"),
                row("BOOMI-0002", "BOOMI", "src/two.tf", "target/two.tf"),
            ],
        }

        for case, invalid_rows in cases.items():
            with self.subTest(case=case):
                message = self.assert_matrix_error(
                    validator.validate_rows, invalid_rows
                )
                self.assertTrue(message)

    def test_validate_rows_rejects_unknown_domains_dispositions_and_statuses(self):
        cases = {
            "domain": ("Domain", "SECURITY"),
            "disposition": ("Disposition", "MERGE"),
            "status": ("Status", "APPROVED"),
        }

        for case, (field, invalid_value) in cases.items():
            with self.subTest(case=case):
                invalid_row = row(
                    "FOUNDATION-0001", "FOUNDATION", "src/main.tf", "target/main.tf"
                )
                invalid_row[field] = invalid_value
                message = self.assert_matrix_error(
                    validator.validate_rows, [invalid_row]
                )
                self.assertIn(invalid_value, message)

    def test_validate_rows_rejects_nonconcrete_source_target_and_evidence(self):
        invalid_values = ("", "UNCLASSIFIED", "TBD", "TODO", "<placeholder>")

        for field in ("Source", "Target", "Evidence"):
            for invalid_value in invalid_values:
                with self.subTest(field=field, invalid_value=invalid_value):
                    invalid_row = row(
                        "FOUNDATION-0001",
                        "FOUNDATION",
                        "src/main.tf",
                        "target/main.tf",
                    )
                    invalid_row[field] = invalid_value
                    message = self.assert_matrix_error(
                        validator.validate_rows, [invalid_row]
                    )
                    self.assertIn(field.lower(), message.lower())
                    self.assertIn("concrete", message.lower())

    def test_validate_rows_rejects_whitespace_only_concrete_fields(self):
        for field in ("Source", "Target", "Evidence"):
            with self.subTest(field=field):
                invalid_row = row(
                    "FOUNDATION-0001", "FOUNDATION", "src/main.tf", "target/main.tf"
                )
                invalid_row[field] = "   "
                message = self.assert_matrix_error(
                    validator.validate_rows, [invalid_row]
                )
                self.assertIn(field.lower(), message.lower())
                self.assertIn("concrete", message.lower())

    def test_validate_rows_accepts_repository_relative_and_explicit_external_identifiers(self):
        rows = [
            row(
                "FOUNDATION-0001",
                "FOUNDATION",
                "main.tf",
                "scripts/provision.sh",
            ),
            row(
                "EKS-0001",
                "EKS",
                "../../Boomi/boomi-infra/infra/tf/main.tf",
                "platform-prerequisites/terraform/eks-platform/main.tf",
            ),
        ]

        self.assertIsNone(validator.validate_rows(rows))

    def test_validate_rows_rejects_duplicate_source_target_decisions(self):
        duplicate_decisions = [
            row("DATA-0001", "DATA", "src/mongodb.tf", "target/mongodb.tf"),
            row(
                "DATA-0002",
                "DATA",
                "src/mongodb.tf",
                "target/mongodb.tf",
                disposition="REWRITE",
            ),
        ]

        message = self.assert_matrix_error(
            validator.validate_rows, duplicate_decisions
        )

        self.assertIn("duplicate", message.lower())
        self.assertIn("src/mongodb.tf", message)
        self.assertIn("target/mongodb.tf", message)

    def test_validate_rows_rejects_a_duplicate_source_candidate(self):
        duplicate_sources = [
            row("DATA-0001", "DATA", "src/mongodb.tf", "target/keep.tf"),
            row("DATA-0002", "DATA", "src/mongodb.tf", "target/rewrite.tf"),
        ]

        message = self.assert_matrix_error(validator.validate_rows, duplicate_sources)

        self.assertIn("duplicate", message.lower())
        self.assertIn("src/mongodb.tf", message)

    def test_validate_rows_rejects_non_identifier_source_and_target_values(self):
        invalid_values = ("not a path", "/Users/reviewer/private/main.tf")

        for field in ("Source", "Target"):
            for invalid_value in invalid_values:
                with self.subTest(field=field, invalid_value=invalid_value):
                    invalid_row = row(
                        "FOUNDATION-0001",
                        "FOUNDATION",
                        "src/main.tf",
                        "target/main.tf",
                    )
                    invalid_row[field] = invalid_value
                    message = self.assert_matrix_error(
                        validator.validate_rows, [invalid_row]
                    )
                    self.assertIn(field.lower(), message.lower())
                    self.assertIn("identifier", message.lower())

    def test_validate_rows_rejects_non_identifier_evidence(self):
        for invalid_value in ("review complete", "/Users/reviewer/review.md"):
            with self.subTest(invalid_value=invalid_value):
                invalid_row = row(
                    "FOUNDATION-0001",
                    "FOUNDATION",
                    "src/main.tf",
                    "target/main.tf",
                    evidence=invalid_value,
                )
                message = self.assert_matrix_error(
                    validator.validate_rows, [invalid_row]
                )
                self.assertIn("evidence", message.lower())
                self.assertIn("reference", message.lower())

    def test_validate_rows_normalizes_identifiers_for_duplicate_detection(self):
        duplicate_sources = [
            row("DATA-0001", "DATA", "src/mongodb.tf", "target/one.tf"),
            row("DATA-0002", "DATA", "src//mongodb.tf", "target/two.tf"),
        ]

        message = self.assert_matrix_error(validator.validate_rows, duplicate_sources)

        self.assertIn("source", message.lower())
        self.assertIn("identifier", message.lower())

    def test_validate_rows_rejects_embedded_placeholder_markers(self):
        invalid_values = ("TODO: locate source", "docs/TBD-review.md")

        for field in ("Source", "Target", "Evidence"):
            for invalid_value in invalid_values:
                with self.subTest(field=field, invalid_value=invalid_value):
                    invalid_row = row(
                        "FOUNDATION-0001",
                        "FOUNDATION",
                        "src/main.tf",
                        "target/main.tf",
                    )
                    invalid_row[field] = invalid_value
                    message = self.assert_matrix_error(
                        validator.validate_rows, [invalid_row]
                    )
                    self.assertIn(field.lower(), message.lower())
                    self.assertIn("concrete", message.lower())

    def test_validate_rows_reports_all_row_errors_in_one_exception(self):
        invalid_rows = [
            row(
                "FOUNDATION-0002",
                "FOUNDATION",
                "UNCLASSIFIED",
                "<target>",
                disposition="MERGE",
                evidence="TODO",
                status="APPROVED",
            ),
            row(
                "SECURITY-0001",
                "SECURITY",
                "src/security.tf",
                "target/security.tf",
            ),
        ]

        message = self.assert_matrix_error(validator.validate_rows, invalid_rows)

        for expected in (
            "id",
            "source",
            "target",
            "disposition",
            "evidence",
            "status",
            "domain",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, message.lower())

    def test_validate_rows_rejects_missing_and_unknown_fields(self):
        missing_field = row(
            "FOUNDATION-0001", "FOUNDATION", "src/main.tf", "target/main.tf"
        )
        del missing_field["Evidence"]
        unknown_field = row(
            "FOUNDATION-0001", "FOUNDATION", "src/main.tf", "target/main.tf"
        )
        unknown_field["Owner"] = "platform"

        for case, invalid_row in {
            "missing": missing_field,
            "unknown": unknown_field,
        }.items():
            with self.subTest(case=case):
                message = self.assert_matrix_error(
                    validator.validate_rows, [invalid_row]
                )
                self.assertIn("schema", message.lower())


class CanonicalLedgerTests(ImportedCodeReviewMatrixTestCase):
    def test_committed_canonical_ledger_is_nonempty_and_valid(self):
        rows = validator.parse_matrix(MATRIX_PATH)

        self.assertTrue(rows)
        self.assertIsNone(validator.validate_rows(rows))
        self.assertTrue(all(item["Status"] in {"REVIEWED", "VERIFIED"} for item in rows))

    def test_committed_ledger_covers_the_phase_one_foundation_inventory(self):
        rows = validator.parse_matrix(MATRIX_PATH)
        foundation_sources = {
            item["Source"] for item in rows if item["Domain"] == "FOUNDATION"
        }

        self.assertEqual(EXPECTED_FOUNDATION_SOURCES, foundation_sources)


class ValidatorCliTests(ImportedCodeReviewMatrixTestCase):
    def run_validator(self, content):
        return subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(self.write_document(content))],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )

    def test_cli_exits_zero_and_reports_validated_row_count(self):
        result = self.run_validator(markdown_table(VALID_MIXED_DOMAIN_ROWS))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(len(VALID_MIXED_DOMAIN_ROWS)), result.stdout)

    def test_cli_exits_nonzero_and_reports_all_contract_errors(self):
        invalid_rows = [
            row(
                "FOUNDATION-0002",
                "FOUNDATION",
                "UNCLASSIFIED",
                "<target>",
                disposition="MERGE",
                evidence="TODO",
                status="APPROVED",
            )
        ]

        result = self.run_validator(markdown_table(invalid_rows))

        self.assertNotEqual(result.returncode, 0)
        for expected in (
            "id",
            "source",
            "target",
            "disposition",
            "evidence",
            "status",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, result.stderr.lower())


if __name__ == "__main__":
    unittest.main()