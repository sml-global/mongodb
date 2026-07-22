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
EKS_ACCESS_ENTRY_DECLARATION_PATTERN = re.compile(
    r'^\s*resource\s+"aws_eks_access_entry"\s+"[^"]+"\s*\{', re.MULTILINE
)
EKS_POLICY_ASSOCIATION_DECLARATION_PATTERN = re.compile(
    r'^\s*resource\s+"aws_eks_access_policy_association"\s+"[^"]+"\s*\{',
    re.MULTILINE,
)
OUTPUT_DECLARATION_PATTERN = re.compile(
    r'^\s*output\s+"(?P<name>[a-z][a-z0-9_]*)"\s*\{', re.MULTILINE
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
CLUSTER_ADMIN_POLICY_ARN = (
    '"arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"'
)
BOOMI_ADMIN_POLICY_ARN = (
    '"arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"'
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


def terraform_block(contents, declaration_pattern):
    declaration = re.search(declaration_pattern, contents, re.MULTILINE)
    if declaration is None:
        return None

    opening_brace = contents.find("{", declaration.start(), declaration.end())
    depth = 0
    for index in range(opening_brace, len(contents)):
        if contents[index] == "{":
            depth += 1
        elif contents[index] == "}":
            depth -= 1
            if depth == 0:
                return contents[declaration.start() : index + 1]

    return None


def block_body(block):
    return block[block.index("{") + 1 : block.rindex("}")]


def normalized_expression(expression):
    return re.sub(r"\s+", "", expression)


def simple_map_assignments(expression):
    expression = expression.strip()
    if not expression.startswith("{") or not expression.endswith("}"):
        return None

    assignments = {}
    for line in expression[1:-1].splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(
            r"\s*([a-z][a-z0-9_]*)\s*=\s*(\S(?:.*\S)?)\s*", line
        )
        if match is None or match.group(1) in assignments:
            return None
        assignments[match.group(1)] = normalized_expression(match.group(2))
    return assignments


def assert_exact_line_assignment(test_case, block, name, expected_expression):
    matches = re.findall(
        rf"^\s*{re.escape(name)}\s*=\s*(\S(?:.*\S)?)\s*$", block, re.MULTILINE
    )
    test_case.assertEqual(
        [normalized_expression(match) for match in matches],
        [normalized_expression(expected_expression)],
    )


class StaticContractTests(unittest.TestCase):
    def test_access_roots_require_native_s3_lockfiles(self):
        for root_name in ("access-governance", "eks-access"):
            with self.subTest(root=root_name):
                versions_tf = (
                    TERRAFORM_ROOT / root_name / "versions.tf"
                ).read_text(encoding="utf-8")
                terraform = terraform_block(versions_tf, r"^\s*terraform\s*\{")
                backend = terraform_block(
                    versions_tf, r'^\s*backend\s+"s3"\s*\{'
                )

                self.assertIsNotNone(terraform)
                assert_exact_line_assignment(
                    self, terraform, "required_version", '">= 1.10.0"'
                )
                self.assertIsNotNone(backend)
                assert_exact_line_assignment(
                    self, backend, "use_lockfile", "true"
                )

    def test_access_governance_defines_account_access_analyzer(self):
        main_tf = (
            TERRAFORM_ROOT / "access-governance" / "main.tf"
        ).read_text(encoding="utf-8")

        self.assertRegex(main_tf, ACCESS_ANALYZER_RESOURCE_PATTERN)

    def test_eks_access_defines_exact_workforce_principals(self):
        main_tf = (TERRAFORM_ROOT / "eks-access" / "main.tf").read_text(
            encoding="utf-8"
        )
        principal_map = terraform_block(main_tf, r"^\s*principals\s*=\s*\{")

        self.assertIsNotNone(principal_map)
        self.assertEqual(
            simple_map_assignments("{" + block_body(principal_map) + "}"),
            {
                "infra_admin": "var.infra_admin_role_arn",
                "application_developer": "var.application_developer_role_arn",
                "boomi_admin": "var.boomi_admin_role_arn",
            },
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

        access_entry = terraform_block(
            main_tf,
            r'^\s*resource\s+"aws_eks_access_entry"\s+"workforce"\s*\{',
        )
        cluster_admin = terraform_block(
            main_tf,
            r'^\s*resource\s+"aws_eks_access_policy_association"\s+'
            r'"cluster_admin"\s*\{',
        )
        boomi_admin = terraform_block(
            main_tf,
            r'^\s*resource\s+"aws_eks_access_policy_association"\s+'
            r'"boomi_admin"\s*\{',
        )
        self.assertIsNotNone(access_entry)
        self.assertIsNotNone(cluster_admin)
        self.assertIsNotNone(boomi_admin)

        assert_exact_line_assignment(self, access_entry, "for_each", "local.principals")
        assert_exact_line_assignment(
            self, access_entry, "cluster_name", "var.eks_cluster_name"
        )
        assert_exact_line_assignment(self, access_entry, "principal_arn", "each.value")

        cluster_for_each = re.search(
            r"^\s*for_each\s*=\s*toset\(\[(?P<keys>.*?)\]\)\s*$",
            cluster_admin,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(cluster_for_each)
        self.assertEqual(
            set(re.findall(r'"([a-z][a-z0-9_]*)"', cluster_for_each.group("keys"))),
            {"infra_admin", "application_developer"},
        )
        self.assertEqual(
            re.sub(r'"[a-z][a-z0-9_]*"', "", cluster_for_each.group("keys"))
            .replace(",", "")
            .strip(),
            "",
        )
        assert_exact_line_assignment(
            self,
            cluster_admin,
            "principal_arn",
            "aws_eks_access_entry.workforce[each.key].principal_arn",
        )
        assert_exact_line_assignment(
            self, cluster_admin, "policy_arn", CLUSTER_ADMIN_POLICY_ARN
        )
        cluster_scope = terraform_block(cluster_admin, r"^\s*access_scope\s*\{")
        self.assertIsNotNone(cluster_scope)
        assert_exact_line_assignment(self, cluster_scope, "type", '"cluster"')

        assert_exact_line_assignment(
            self,
            boomi_admin,
            "principal_arn",
            'aws_eks_access_entry.workforce["boomi_admin"].principal_arn',
        )
        assert_exact_line_assignment(
            self, boomi_admin, "policy_arn", BOOMI_ADMIN_POLICY_ARN
        )
        boomi_scope = terraform_block(boomi_admin, r"^\s*access_scope\s*\{")
        self.assertIsNotNone(boomi_scope)
        assert_exact_line_assignment(self, boomi_scope, "type", '"namespace"')
        assert_exact_line_assignment(
            self, boomi_scope, "namespaces", "[var.boomi_namespace]"
        )

    def test_eks_access_provider_and_account_validation_are_pinned_to_uat(self):
        versions_tf = (TERRAFORM_ROOT / "eks-access" / "versions.tf").read_text(
            encoding="utf-8"
        )
        variables_tf = (TERRAFORM_ROOT / "eks-access" / "variables.tf").read_text(
            encoding="utf-8"
        )
        provider = terraform_block(versions_tf, r'^\s*provider\s+"aws"\s*\{')
        account_variable = terraform_block(
            variables_tf, r'^\s*variable\s+"expected_account_id"\s*\{'
        )

        self.assertIsNotNone(provider)
        assert_exact_line_assignment(
            self, provider, "allowed_account_ids", "[var.expected_account_id]"
        )
        self.assertIsNotNone(account_variable)
        validations = re.findall(
            r"^\s*validation\s*\{", account_variable, re.MULTILINE
        )
        self.assertEqual(len(validations), 1)
        validation = terraform_block(account_variable, r"^\s*validation\s*\{")
        assert_exact_line_assignment(
            self,
            validation,
            "condition",
            f'var.expected_account_id == "{APPROVED_ACCOUNT_ID}"',
        )
        assert_exact_line_assignment(
            self,
            validation,
            "error_message",
            f'"expected_account_id must be {APPROVED_ACCOUNT_ID}."',
        )

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
        output_names = {
            match.group("name")
            for match in OUTPUT_DECLARATION_PATTERN.finditer(outputs_tf)
        }

        self.assertEqual(
            output_names, {"access_entry_arns", "associated_policy_arns"}
        )
        access_entries = terraform_block(
            outputs_tf, r'^\s*output\s+"access_entry_arns"\s*\{'
        )
        associated_policies = terraform_block(
            outputs_tf, r'^\s*output\s+"associated_policy_arns"\s*\{'
        )
        self.assertIsNotNone(access_entries)
        self.assertIsNotNone(associated_policies)
        access_entry_value = re.fullmatch(
            r"\s*value\s*=\s*(?P<value>.*?)\s*",
            block_body(access_entries),
            re.DOTALL,
        )
        associated_policy_value = re.fullmatch(
            r"\s*value\s*=\s*(?P<value>.*?)\s*",
            block_body(associated_policies),
            re.DOTALL,
        )

        self.assertIsNotNone(access_entry_value)
        self.assertEqual(
            normalized_expression(access_entry_value.group("value")),
            normalized_expression(
                "{ for principal, entry in aws_eks_access_entry.workforce : "
                "principal => entry.access_entry_arn }"
            ),
        )
        self.assertIsNotNone(associated_policy_value)
        self.assertEqual(
            simple_map_assignments(associated_policy_value.group("value")),
            {
                "infra_admin": normalized_expression(
                    'aws_eks_access_policy_association.cluster_admin["infra_admin"].policy_arn'
                ),
                "application_developer": normalized_expression(
                    "aws_eks_access_policy_association.cluster_admin"
                    '["application_developer"].policy_arn'
                ),
                "boomi_admin": (
                    "aws_eks_access_policy_association.boomi_admin.policy_arn"
                ),
            },
        )

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

    def test_eks_access_root_uses_exactly_the_approved_account_id(self):
        account_ids = set(ACCOUNT_ID_PATTERN.findall(terraform_text("eks-access")))

        self.assertEqual(account_ids, {APPROVED_ACCOUNT_ID})


if __name__ == "__main__":
    unittest.main()
