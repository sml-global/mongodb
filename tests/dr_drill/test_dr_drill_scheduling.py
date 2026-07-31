"""Structural test suite for DR drill IAM least-privilege and CronJob
scheduling.

Terraform is verified with `terraform validate` (this repo's existing
verification convention -- see AGENTS.md), which parses the real HCL and
catches reference errors (e.g. an assume_role_policy pointing at a data
source that was never defined) that no grep could ever catch. The CronJob
is verified by parsing the YAML with PyYAML and asserting on structured
fields, matching tests/signoz/test_gitops_manifests.py. Per
writing-good-tests.md (v6.2.0): string-presence assertions counterfeit
falsifiability.

Note: `terraform validate` proves the HCL is internally consistent (types,
references, required arguments). It does not prove the IAM policy behaves
correctly against live AWS -- that is proven independently by the runtime
identity guard (`aws sts get-caller-identity`) built into each drill script
in Tasks 1-3, and ultimately by the drills actually passing in UAT.
"""
import os
import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
TF_DIR = REPO_ROOT / "platform-prerequisites" / "terraform" / "dr-drill"
CRONJOB = REPO_ROOT / "k8s" / "dr-drill" / "cronjob.yaml"
BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts" / "bootstrap-dr-drill-role-arns-configmap.sh"


class DrDrillTerraformValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(
            ["terraform", "init", "-backend=false", "-input=false"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=120,
        )

    def test_terraform_directory_exists(self):
        self.assertTrue(TF_DIR.exists(), "platform-prerequisites/terraform/dr-drill must exist")

    def test_terraform_validate_succeeds(self):
        # Catches real reference errors -- e.g. assume_role_policy pointing
        # at an undefined data source -- that grep cannot detect.
        result = subprocess.run(
            ["terraform", "validate", "-json"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0,
                          f"terraform validate failed:\n{result.stdout}\n{result.stderr}")

    def test_terraform_fmt_check_passes(self):
        result = subprocess.run(
            ["terraform", "fmt", "-check", "-recursive"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
                          f"terraform fmt -check failed:\n{result.stdout}")

    def test_terraform_never_defines_a_kubernetes_provider(self):
        # This repo's convention: Terraform manages AWS only. Kubernetes
        # objects are always created via GitOps/kubectl scripts (see
        # bootstrap-dr-drill-role-arns-configmap.sh below), never the
        # `kubernetes` Terraform provider.
        for tf_file in TF_DIR.glob("*.tf"):
            self.assertNotIn('provider "kubernetes"', tf_file.read_text())
            self.assertNotIn("resource \"kubernetes_", tf_file.read_text())

    def test_terraform_outputs_all_three_role_arns(self):
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=TF_DIR, capture_output=True, text=True, timeout=30,
        )
        # Without real AWS credentials `terraform output` returns an empty
        # object (no state), but it must at least declare the output names --
        # verified structurally by grepping the parsed HCL output blocks via
        # `terraform validate`'s success above, plus this direct check that
        # the output declarations exist in the source.
        main_tf = (TF_DIR / "main.tf").read_text()
        for output_name in (
            "dr_drill_mongodb_role_arn",
            "dr_drill_postgresql_role_arn",
            "dr_drill_clickhouse_role_arn",
        ):
            self.assertIn(f'output "{output_name}"', main_tf)

    def test_pod_identity_associations_exist_for_all_three_fixed_restore_target_namespaces(self):
        # The 3 restore-target pods (pbm-agent / CNPG Postgres / clickhouse-
        # backup) each do the actual S3 GetObject/PutObject calls -- distinct
        # from the orchestrator CronJob pod (dr-drill-uat), which only runs
        # `aws sts get-caller-identity` guard checks (and, for clickhouse,
        # `aws s3 ls` verification). EKS Pod Identity requires an exact
        # static namespace+ServiceAccount match, so each fixed restore-target
        # namespace needs its own association, reusing the already-defined
        # least-privilege IAM roles (no new roles needed).
        main_tf = (TF_DIR / "main.tf").read_text()
        expected = {
            "dr_drill_mongodb_restore_target": (
                "dr-drill-mongodb-restore-target", "dr-drill-mongodb-runner",
                "aws_iam_role.dr_drill_mongodb_restore_role.arn",
            ),
            "dr_drill_postgresql_restore_target": (
                "dr-drill-postgresql-restore-target", "dr-drill-postgresql-runner",
                "aws_iam_role.dr_drill_postgresql_restore_role.arn",
            ),
            "dr_drill_clickhouse_restore_target": (
                "dr-drill-clickhouse-restore-target", "dr-drill-clickhouse-runner",
                "aws_iam_role.dr_drill_clickhouse_backup_role.arn",
            ),
        }
        for resource_name, (namespace, service_account, role_arn_ref) in expected.items():
            match = re.search(
                r'resource\s+"aws_eks_pod_identity_association"\s+"%s"\s*\{(.*?)\n\}'
                % re.escape(resource_name),
                main_tf, re.DOTALL,
            )
            self.assertIsNotNone(
                match, f"aws_eks_pod_identity_association.{resource_name} must be defined")
            block = match.group(1)
            self.assertIn(f'namespace       = "{namespace}"', block)
            self.assertIn(f'service_account = "{service_account}"', block)
            self.assertIn(f'role_arn        = {role_arn_ref}', block)

    def test_restore_target_associations_reuse_existing_iam_roles_not_new_ones(self):
        # These 3 new associations must NOT define their own aws_iam_role --
        # they intentionally reuse the same least-privilege roles already
        # bound to the orchestrator ServiceAccounts in dr-drill-uat.
        main_tf = (TF_DIR / "main.tf").read_text()
        role_resource_names = set(re.findall(r'resource\s+"aws_iam_role"\s+"(\w+)"', main_tf))
        self.assertEqual(
            role_resource_names,
            {
                "dr_drill_mongodb_restore_role",
                "dr_drill_postgresql_restore_role",
                "dr_drill_clickhouse_backup_role",
                "signoz_clickhouse_backup_writer_role",
            },
            "no new aws_iam_role resources should have been added",
        )


class DrDrillRoleArnsBootstrapScriptBehaviorTests(unittest.TestCase):
    """Behavioral test for the kubectl-based bootstrap script (PATH-mocked
    terraform + kubectl), matching the D6 convention for bash scripts."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.log_path = self.bin_dir / "calls.log"
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin_dir}:{self.env['PATH']}"

    def tearDown(self):
        self.tmp.cleanup()

    def _mock(self, name, body):
        path = self.bin_dir / name
        path.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "{name} $*" >> "{self.log_path}"\n'
            f"{body}\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _log(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def test_reads_all_three_outputs_and_creates_configmap(self):
        self._mock("terraform", (
            'if [[ "$*" == *"dr_drill_mongodb_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-mongodb-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_postgresql_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-postgresql-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_clickhouse_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-clickhouse-backup-role"; fi\n'
        ))
        self._mock("kubectl", "cat > /dev/null 2>/dev/null; exit 0")
        result = subprocess.run(
            ["bash", str(BOOTSTRAP_SCRIPT)],
            env=self.env, capture_output=True, text=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dr-drill-role-arns", self._log())
        self.assertIn("DR_DRILL_MONGODB_ROLE_ARN", self._log())

    def test_creates_three_dedicated_service_accounts_with_pod_identity(self):
        # Regression test for a critical bug (C1) caught in whole-branch
        # review: a single ServiceAccount cannot bind three different IAM
        # roles. Each drill needs its own dedicated ServiceAccount. Updated
        # for the IRSA -> EKS Pod Identity migration (see commit 4beefb7):
        # Pod Identity binds a role to a ServiceAccount via a separate AWS-side
        # association (Terraform), not a ServiceAccount annotation -- so the
        # bootstrap script now creates plain ServiceAccounts with no
        # role-arn annotation at all.
        self._mock("terraform", (
            'if [[ "$*" == *"dr_drill_mongodb_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-mongodb-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_postgresql_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-postgresql-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_clickhouse_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-clickhouse-backup-role"; fi\n'
        ))
        self._mock("kubectl", "cat > /dev/null 2>/dev/null; exit 0")
        result = subprocess.run(
            ["bash", str(BOOTSTRAP_SCRIPT)],
            env=self.env, capture_output=True, text=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self._log()
        for sa_name in (
            "dr-drill-mongodb-runner",
            "dr-drill-postgresql-runner",
            "dr-drill-clickhouse-runner",
        ):
            self.assertIn(sa_name, log, f"must create ServiceAccount {sa_name}")
        # No IRSA-style role-arn annotation flag anywhere in the invocation
        # log -- Pod Identity needs none.
        self.assertNotIn("eks.amazonaws.com/role-arn", log)

    def test_provisions_fixed_namespaces_and_rbac_before_the_configmap(self):
        # Regression test for the D18/D19 provision-once model: this script
        # is now the ONLY place that creates the 3 fixed restore-target
        # namespaces, the ServiceAccounts inside them, and applies
        # k8s/dr-drill/rbac.yaml -- and it must do so in an order where
        # every namespace/SA a RoleBinding references already exists before
        # rbac.yaml is applied. This exact area (RBAC provisioning) has
        # regressed twice across review cycles, so lock the order in.
        self._mock("terraform", (
            'if [[ "$*" == *"dr_drill_mongodb_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-mongodb-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_postgresql_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-postgresql-restore-role"; fi\n'
            'if [[ "$*" == *"dr_drill_clickhouse_role_arn"* ]]; then echo "arn:aws:iam::123:role/dr-drill-clickhouse-backup-role"; fi\n'
        ))
        self._mock("kubectl", "cat > /dev/null 2>/dev/null; exit 0")
        result = subprocess.run(
            ["bash", str(BOOTSTRAP_SCRIPT)],
            env=self.env, capture_output=True, text=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self._log()
        for restore_namespace in (
            "dr-drill-mongodb-restore-target",
            "dr-drill-postgresql-restore-target",
            "dr-drill-clickhouse-restore-target",
        ):
            self.assertIn(f"create namespace {restore_namespace}", log,
                          f"must create the fixed namespace {restore_namespace}")
        self.assertIn("apply -f", log)
        self.assertIn("rbac.yaml", log, "must apply k8s/dr-drill/rbac.yaml")

        namespace_idx = max(
            log.index(f"create namespace {ns}") for ns in (
                "dr-drill-mongodb-restore-target",
                "dr-drill-postgresql-restore-target",
                "dr-drill-clickhouse-restore-target",
            )
        )
        rbac_idx = log.index("rbac.yaml")
        self.assertLess(namespace_idx, rbac_idx,
                         "all fixed namespaces must exist before rbac.yaml is applied")


class DrDrillCronJobStructureTests(unittest.TestCase):
    """Structural (parsed-field) assertions, not substring search.

    THREE separate CronJob documents are expected (multi-doc YAML) -- a
    regression guard for a critical bug (C1) caught in whole-branch review:
    a single CronJob running all three drill scripts under one
    ServiceAccount can satisfy at most one script's IRSA identity guard.
    """

    @classmethod
    def setUpClass(cls):
        cls.docs = [d for d in yaml.safe_load_all(CRONJOB.read_text()) if d]
        cls.by_script = {}
        for doc in cls.docs:
            pod_spec = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
            command_str = pod_spec["containers"][0]["command"][-1]
            for script_name in (
                "dr-drill-mongodb-restore.sh",
                "dr-drill-postgresql-restore.sh",
                "dr-drill-clickhouse-backup-restore.sh",
            ):
                if script_name in command_str:
                    cls.by_script[script_name] = doc

    def test_exactly_three_cronjobs_defined(self):
        self.assertEqual(len(self.docs), 3)
        for doc in self.docs:
            self.assertEqual(doc["kind"], "CronJob")

    def test_each_cronjob_runs_exactly_one_drill_script(self):
        self.assertEqual(len(self.by_script), 3,
                          "each of the 3 drill scripts must appear in exactly one CronJob")
        for script_name, doc in self.by_script.items():
            pod_spec = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
            command_str = pod_spec["containers"][0]["command"][-1]
            other_scripts = {
                "dr-drill-mongodb-restore.sh",
                "dr-drill-postgresql-restore.sh",
                "dr-drill-clickhouse-backup-restore.sh",
            } - {script_name}
            for other in other_scripts:
                self.assertNotIn(other, command_str,
                                  f"{script_name}'s CronJob must not also invoke {other}")

    def test_each_cronjob_targets_dr_drill_uat_namespace(self):
        for doc in self.docs:
            self.assertEqual(doc["metadata"]["namespace"], "dr-drill-uat")

    def test_each_cronjob_runs_weekly_sunday_0300_utc(self):
        for doc in self.docs:
            self.assertEqual(doc["spec"]["schedule"], "0 3 * * 0")

    def test_each_cronjob_uses_its_own_dedicated_service_account(self):
        expected_sa = {
            "dr-drill-mongodb-restore.sh": "dr-drill-mongodb-runner",
            "dr-drill-postgresql-restore.sh": "dr-drill-postgresql-runner",
            "dr-drill-clickhouse-backup-restore.sh": "dr-drill-clickhouse-runner",
        }
        for script_name, doc in self.by_script.items():
            pod_spec = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
            self.assertEqual(pod_spec["serviceAccountName"], expected_sa[script_name])

    def test_service_accounts_are_all_distinct(self):
        sa_names = {
            doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]["serviceAccountName"]
            for doc in self.docs
        }
        self.assertEqual(len(sa_names), 3, "all 3 CronJobs must use distinct ServiceAccounts")

    def test_cronjobs_use_a_real_publicly_available_image(self):
        # Regression test for M4: an earlier version referenced
        # oms/dr-drill-runner:latest, which was never built and does not
        # exist. alpine/k8s is a real, actively maintained public image
        # bundling kubectl + aws-cli (verified via Docker Hub).
        for doc in self.docs:
            container = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]
            self.assertNotEqual(container["image"], "oms/dr-drill-runner:latest")
            self.assertTrue(container["image"].startswith("alpine/k8s:"))

    def test_each_cronjob_sources_role_arns_from_bootstrapped_configmap(self):
        # No hardcoded AWS account ID/ARNs in the YAML -- real values come
        # from the dr-drill-role-arns ConfigMap (created by
        # scripts/bootstrap-dr-drill-role-arns-configmap.sh from Terraform
        # outputs).
        for doc in self.docs:
            container = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]
            config_map_refs = [
                ref["configMapRef"]["name"] for ref in container.get("envFrom", [])
            ]
            self.assertIn("dr-drill-role-arns", config_map_refs)


if __name__ == "__main__":
    unittest.main()
