import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_ROOT = REPO_ROOT / "platform-prerequisites" / "terraform"
APPROVED_ACCOUNT_ID = "672172129937"
DEV_ACCOUNT_ID = "815402439714"
FORBIDDEN_RESOURCE_TOKENS = (
    "aws_ssoadmin_",
    "aws_identitystore_",
    "aws_iam_user",
    "aws_iam_access_key",
)
ACCOUNT_ID_PATTERN = re.compile(r"(?<!\d)\d{12}(?!\d)")
ACCESS_ANALYZER_RESOURCE_PATTERN = re.compile(
    r'^\s*resource\s+"aws_accessanalyzer_analyzer"\s+"[^"]+"\s*\{',
    re.MULTILINE,
)


def terraform_text(root_name):
    root = TERRAFORM_ROOT / root_name
    if not root.exists():
        return ""

    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.suffix in {".tf", ".tfvars"}
    )


class StaticContractTests(unittest.TestCase):
    def test_access_governance_defines_account_access_analyzer(self):
        main_tf = (
            TERRAFORM_ROOT / "access-governance" / "main.tf"
        ).read_text(encoding="utf-8")

        self.assertRegex(main_tf, ACCESS_ANALYZER_RESOURCE_PATTERN)

    def test_access_roots_exclude_identity_center_and_iam_users(self):
        for root_name in ("access-governance", "eks-access"):
            root = TERRAFORM_ROOT / root_name
            if not root.exists():
                continue

            contents = terraform_text(root_name)
            with self.subTest(root=root_name):
                for token in FORBIDDEN_RESOURCE_TOKENS:
                    self.assertNotIn(token, contents)
                self.assertNotIn(DEV_ACCOUNT_ID, contents)

    def test_access_roots_use_only_approved_account_id(self):
        for root_name in ("access-governance", "eks-access"):
            root = TERRAFORM_ROOT / root_name
            if not root.exists():
                continue

            account_ids = set(ACCOUNT_ID_PATTERN.findall(terraform_text(root_name)))
            with self.subTest(root=root_name):
                self.assertLessEqual(account_ids, {APPROVED_ACCOUNT_ID})


if __name__ == "__main__":
    unittest.main()
