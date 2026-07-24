import importlib.util
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

CANONICAL_HEADER = "| ID | Domain | Source | Target | Disposition | Evidence | Status |"

BOOMI_INFRA_ROOT = REPO_ROOT.parents[3] / "Boomi" / "boomi-infra" / "infra"


def discover_boomi_inventory_sources():
    sources = set()
    for relative_root in ("scripts", "envs", "tf"):
        for path in (BOOMI_INFRA_ROOT / relative_root).rglob("*"):
            if path.is_file() and ".terraform" not in path.parts:
                sources.add(
                    f"boomi-infra@inventory:infra/{path.relative_to(BOOMI_INFRA_ROOT).as_posix()}"
                )
    return sources

EXPECTED_FOUNDATION_SOURCES = {
    *(
        f"mongodb@29353d6:config/environments/uat.env#{key}"
        for key in (
            "ENVIRONMENT",
            "EXPECTED_AWS_ACCOUNT_ID",
            "AWS_REGION",
            "EKS_CLUSTER_NAME",
            "BOOMI_NAMESPACE",
            "TF_STATE_BUCKET",
            "TF_STATE_REGION",
            "ACCESS_GOVERNANCE_STATE_KEY",
            "EKS_ACCESS_STATE_KEY",
        )
    ),
    "mongodb@29353d6:scripts/lib/platform-env.sh",
    "mongodb@29353d6:scripts/bootstrap-terraform-s3-backend.sh",
    "mongodb@29353d6:scripts/validate-uat-workforce-principals.sh",
    "mongodb@29353d6:scripts/validate-uat-workforce-principals.sh#generated-auto-tfvars",
    "mongodb@29353d6:scripts/provision-uat-access.sh",
    "mongodb@29353d6:.gitignore#uat-local-inputs",
    *(
        f"mongodb@29353d6:platform-prerequisites/terraform/{root}/{name}"
        for root in ("access-governance", "eks-access")
        for name in (
            ".terraform.lock.hcl",
            "versions.tf",
            "variables.tf",
            "main.tf",
            "outputs.tf",
            "uat.tfvars",
        )
    ),
    "mongodb@29353d6:platform-prerequisites/terraform/access-governance/main.tf#aws_accessanalyzer_analyzer.uat_account",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#local.principals",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_entry.workforce",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.cluster_admin",
    "mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.boomi_admin",
}


class EksImportReviewTests(unittest.TestCase):
    def test_matrix_header_uses_exact_canonical_schema_without_test_column(self):
        lines = MATRIX_PATH.read_text(encoding="utf-8").splitlines()
        header = next(line for line in lines if line.startswith("| ID |"))

        self.assertEqual(CANONICAL_HEADER, header)
        self.assertNotIn("| Test |", header)

    def test_committed_matrix_is_valid_under_the_foundation_validator(self):
        rows = validator.parse_matrix(MATRIX_PATH)

        self.assertTrue(rows)
        self.assertIsNone(validator.validate_rows(rows))

    @unittest.skipUnless(BOOMI_INFRA_ROOT.exists(), "Boomi legacy repository not found on host disk")
    def test_eks_rows_cover_the_expected_inventory_sources_exactly(self):
        rows = validator.parse_matrix(MATRIX_PATH)
        eks_rows = [row for row in rows if row["Domain"] == "EKS"]
        file_sources = {row["Source"] for row in eks_rows if "#" not in row["Source"]}
        fragment_sources = {row["Source"] for row in eks_rows if "#" in row["Source"]}

        self.assertEqual(discover_boomi_inventory_sources(), file_sources)
        self.assertIn(
            "boomi-infra@inventory:infra/tf/modules/node_groups/main.tf#remote_access",
            fragment_sources,
        )
        self.assertIn(
            "boomi-infra@inventory:infra/tf/modules/iam/main.tf#aws_iam_role_policy.node_autoscaling",
            fragment_sources,
        )

    def test_eks_ids_are_unique_and_sequential_from_eks_0001(self):
        rows = validator.parse_matrix(MATRIX_PATH)
        ids = [row["ID"] for row in rows if row["Domain"] == "EKS"]

        self.assertTrue(ids)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(
            [f"EKS-{index:04d}" for index in range(1, len(ids) + 1)],
            ids,
        )

    def test_eks_enums_are_uppercase_and_gate_ready(self):
        rows = validator.parse_matrix(MATRIX_PATH)
        eks_rows = [row for row in rows if row["Domain"] == "EKS"]

        self.assertTrue(eks_rows)
        allowed_statuses = {"REVIEWED", "VERIFIED"}
        for row in eks_rows:
            self.assertEqual(row["Domain"], row["Domain"].upper())
            self.assertEqual(row["Disposition"], row["Disposition"].upper())
            self.assertEqual(row["Status"], row["Status"].upper())
            self.assertIn(row["Disposition"], validator.DISPOSITIONS)
            self.assertIn(row["Status"], validator.STATUSES)
            self.assertIn(row["Status"], allowed_statuses)

        self.assertNotIn("PROPOSED", {row["Status"] for row in eks_rows})

    def test_non_eks_rows_match_the_foundation_baseline_inventory(self):
        rows = validator.parse_matrix(MATRIX_PATH)
        non_eks_rows = [row for row in rows if row["Domain"] != "EKS"]
        non_eks_sources = {row["Source"] for row in non_eks_rows}

        self.assertEqual(32, len(non_eks_rows))
        self.assertTrue(all(row["Domain"] == "FOUNDATION" for row in non_eks_rows))
        self.assertEqual(EXPECTED_FOUNDATION_SOURCES, non_eks_sources)
        self.assertEqual(
            [f"FOUNDATION-{index:04d}" for index in range(1, 33)],
            [row["ID"] for row in non_eks_rows],
        )


if __name__ == "__main__":
    unittest.main()
