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
EKS_ACCESS_ENTRY_RESOURCE_PATTERN = re.compile(
    r'^resource\s+"aws_eks_access_entry"\s+"workforce"\s*\{'
    r'(?:(?!^\}).)*?^\s*for_each\s*=\s*local\.principals\s*$'
    r'(?:(?!^\}).)*?^\s*cluster_name\s*=\s*var\.eks_cluster_name\s*$'
    r'(?:(?!^\}).)*?^\s*principal_arn\s*=\s*each\.value\s*$'
    r'(?:(?!^\}).)*?^\}',
    re.MULTILINE | re.DOTALL,
)
EKS_CLUSTER_POLICY_RESOURCE_PATTERN = re.compile(
    r'^resource\s+"aws_eks_access_policy_association"\s+"cluster_admin"\s*\{'
    r'(?:(?!^\}).)*?^\s*for_each\s*=\s*toset\(\['
    r'\s*"infra_admin",\s*"application_developer",?\s*\]\)\s*$'
    r'(?:(?!^\}).)*?^\s*policy_arn\s*=\s*'
    r'"arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"\s*$'
    r'(?:(?!^\}).)*?^\s*type\s*=\s*"cluster"\s*$'
    r'(?:(?!^\}).)*?^\}',
    re.MULTILINE | re.DOTALL,
)
EKS_BOOMI_POLICY_RESOURCE_PATTERN = re.compile(
    r'^resource\s+"aws_eks_access_policy_association"\s+"boomi_admin"\s*\{'
    r'(?:(?!^\}).)*?^\s*principal_arn\s*=\s*'
    r'aws_eks_access_entry\.workforce\["boomi_admin"\]\.principal_arn\s*$'
    r'(?:(?!^\}).)*?^\s*policy_arn\s*=\s*'
    r'"arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"\s*$'
    r'(?:(?!^\}).)*?^\s*type\s*=\s*"namespace"\s*$'
    r'(?:(?!^\}).)*?^\s*namespaces\s*=\s*\[var\.boomi_namespace\]\s*$'
    r'(?:(?!^\}).)*?^\}',
    re.MULTILINE | re.DOTALL,
)
PRINCIPAL_MAP_PATTERN = re.compile(
    r'^\s*principals\s*=\s*\{(?P<body>.*?)^\s*\}',
    re.MULTILINE | re.DOTALL,
)
PRINCIPAL_KEY_PATTERN = re.compile(r'^\s*([a-z][a-z0-9_]*)\s*=', re.MULTILINE)
EKS_ACCESS_ENTRY_DECLARATION_PATTERN = re.compile(
    r'^resource\s+"aws_eks_access_entry"\s+"[^"]+"\s*\{', re.MULTILINE
)
EKS_POLICY_ASSOCIATION_DECLARATION_PATTERN = re.compile(
    r'^resource\s+"aws_eks_access_policy_association"\s+"[^"]+"\s*\{',
    re.MULTILINE,
)
OUTPUT_DECLARATION_PATTERN = re.compile(
    r'^output\s+"(?P<name>[a-z][a-z0-9_]*)"\s*\{', re.MULTILINE
)
TOP_LEVEL_ASSIGNMENT_PATTERN = re.compile(
    r'^[ \t]*(?P<name>[a-z][a-z0-9_]*)[ \t]*=', re.MULTILINE
)
ROLE_ARN_VARIABLE_PATTERN = re.compile(
    r'^variable\s+"([a-z][a-z0-9_]*_role_arn)"\s*\{', re.MULTILINE
)
EXPECTED_PERMISSION_SET_PREFIXES = {
    "infra_admin_role_arn": "AWSReservedSSO_UATInfraAdminEA_",
    "application_developer_role_arn": "AWSReservedSSO_UATApplicationDeveloper_",
    "boomi_admin_role_arn": "AWSReservedSSO_UATBoomiAdmin_",
}


def terraform_text(root_name):
    root = TERRAFORM_ROOT / root_name
    if not root.exists():
        return ""

    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.suffix in {".tf", ".tfvars"}
    )


def output_blocks(contents):
    declarations = list(OUTPUT_DECLARATION_PATTERN.finditer(contents))
    return {
        declaration.group("name"): contents[
            declaration.start() : (
                declarations[index + 1].start()
                if index + 1 < len(declarations)
                else len(contents)
            )
        ]
        for index, declaration in enumerate(declarations)
    }


class StaticContractTests(unittest.TestCase):
    def test_access_governance_defines_account_access_analyzer(self):
        main_tf = (
            TERRAFORM_ROOT / "access-governance" / "main.tf"
        ).read_text(encoding="utf-8")

        self.assertRegex(main_tf, ACCESS_ANALYZER_RESOURCE_PATTERN)

    def test_eks_access_defines_exact_workforce_principals(self):
        main_tf = (TERRAFORM_ROOT / "eks-access" / "main.tf").read_text(
            encoding="utf-8"
        )
        principal_map = PRINCIPAL_MAP_PATTERN.search(main_tf)

        self.assertIsNotNone(principal_map)
        self.assertEqual(
            set(PRINCIPAL_KEY_PATTERN.findall(principal_map.group("body"))),
            {"infra_admin", "application_developer", "boomi_admin"},
        )
        self.assertNotIn("process_owner", terraform_text("eks-access"))

    def test_eks_access_defines_entry_and_policy_resource_shapes(self):
        main_tf = (TERRAFORM_ROOT / "eks-access" / "main.tf").read_text(
            encoding="utf-8"
        )

        self.assertEqual(len(EKS_ACCESS_ENTRY_DECLARATION_PATTERN.findall(main_tf)), 1)
        self.assertEqual(
            len(EKS_POLICY_ASSOCIATION_DECLARATION_PATTERN.findall(main_tf)), 2
        )
        self.assertRegex(main_tf, EKS_ACCESS_ENTRY_RESOURCE_PATTERN)
        self.assertRegex(main_tf, EKS_CLUSTER_POLICY_RESOURCE_PATTERN)
        self.assertRegex(main_tf, EKS_BOOMI_POLICY_RESOURCE_PATTERN)

    def test_eks_access_defines_exact_role_arn_inputs(self):
        variables_tf = (TERRAFORM_ROOT / "eks-access" / "variables.tf").read_text(
            encoding="utf-8"
        )
        uat_tfvars = (TERRAFORM_ROOT / "eks-access" / "uat.tfvars").read_text(
            encoding="utf-8"
        )

        self.assertEqual(
            set(ROLE_ARN_VARIABLE_PATTERN.findall(variables_tf)),
            set(EXPECTED_PERMISSION_SET_PREFIXES),
        )
        expected_arn_prefix = (
            "^arn:aws:iam::672172129937:role/aws-reserved/"
            "sso\\\\.amazonaws\\\\.com/[^/]+/"
        )
        for variable_name, permission_set_prefix in (
            EXPECTED_PERMISSION_SET_PREFIXES.items()
        ):
            with self.subTest(variable=variable_name):
                self.assertIn(
                    f'"{expected_arn_prefix}{permission_set_prefix}[A-Za-z0-9]+$"',
                    variables_tf,
                )
                self.assertNotIn(variable_name, uat_tfvars)

    def test_eks_access_uat_tfvars_targets_runtime_cluster_and_namespace(self):
        uat_tfvars = (TERRAFORM_ROOT / "eks-access" / "uat.tfvars").read_text(
            encoding="utf-8"
        )

        self.assertEqual(
            set(TOP_LEVEL_ASSIGNMENT_PATTERN.findall(uat_tfvars)),
            {
                "aws_region",
                "expected_account_id",
                "eks_cluster_name",
                "boomi_namespace",
            },
        )
        expected_values = {
            "aws_region": "ap-east-1",
            "expected_account_id": "672172129937",
            "eks_cluster_name": "EKS-boomi-runtime-cluster",
            "boomi_namespace": "boomi-uat",
        }
        for variable_name, expected_value in expected_values.items():
            with self.subTest(variable=variable_name):
                self.assertRegex(
                    uat_tfvars,
                    re.compile(
                        rf'^\s*{variable_name}\s*=\s*"{expected_value}"\s*$',
                        re.MULTILINE,
                    ),
                )

    def test_eks_access_outputs_only_entry_and_policy_association_arns(self):
        outputs_tf = (TERRAFORM_ROOT / "eks-access" / "outputs.tf").read_text(
            encoding="utf-8"
        )
        output_names = [
            match.group("name")
            for match in OUTPUT_DECLARATION_PATTERN.finditer(outputs_tf)
        ]
        outputs = output_blocks(outputs_tf)

        self.assertEqual(
            output_names, ["access_entry_arns", "associated_policy_arns"]
        )
        self.assertRegex(outputs["access_entry_arns"], r"\.access_entry_arn\b")
        self.assertNotRegex(outputs["access_entry_arns"], r"\.association_arn\b")
        self.assertRegex(outputs["associated_policy_arns"], r"\.policy_arn\b")
        self.assertNotRegex(outputs["associated_policy_arns"], r"\.association_arn\b")

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
                self.assertNotRegex(contents, r'(?m)^\s*(?:data|resource)\s+"aws_iam_')
                self.assertNotIn("aws-auth", contents)
                self.assertNotIn("saml", contents.lower())

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
