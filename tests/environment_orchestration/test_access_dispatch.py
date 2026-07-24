"""Tests for Task 5: Supply Reviewed UAT Access Symbols To Unified
Provisioning.

See docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
lines 1550-1758 for the full requirement text. This file covers the 13
numbered requirements exclusively through the real
scripts/lib/packages/10-foundation-access/internal/access-scopes.sh,
scripts/lib/scope-handlers.d/10-foundation-access.sh, and
scripts/lib/scope-verifiers.d/10-foundation-access.sh dispatched via the
real scripts/lib/orchestrator.sh + run_unified_command, with aws/kubectl/
terraform mocked and the real system jq and real
scripts/validate-uat-workforce-principals.sh exercised unmocked.

Requirement -> test class mapping:
  1.  GovernanceDispatchOrderTests
  2.  EksAccessDispatchOrderTests
  3.  PrincipalInputPathTests
  4.  LocalArtifactLocationTests
  5.  GeneratedTfvarsCleanupTimingTests
  6.  AppliedPlanInvocationTests
  7.  InteractiveApprovalTests
  8.  AutoApproveGuardsTests (positive half) +
      FailureModeCleanupIsolationTests (negative half, every scenario
      there passes --auto-approve and still stops at its guard)
  9.  FailureModeCleanupIsolationTests
  10. OriginalFailureVsCleanupFailureTests
  11. UnifiedAllPreResolutionTests
  12. NoLegacyOrDevArtifactLeakageTests
  13. CompatibilityWrapperForwardingTests

Judgment calls (flagged in the final report as DONE_WITH_CONCERNS items):

  * scripts/bootstrap-terraform-s3-backend.sh is REPLACED by a small,
    purpose-built stub in AccessDispatchFixture rather than copied as the
    real script. The real script performs its own `terraform init` and
    several additional `aws s3api` calls (bucket creation/control
    verification) that are outside the scope of this file's access-dispatch
    tests and are not part of the plan's own EXPECTED_GOVERNANCE_ORDER /
    EXPECTED_EKS_ACCESS_ORDER command lists. This mirrors the existing
    LegacyDestroyFixture precedent in test_entrypoints.py, which stubs this
    exact same script for the same reason. The stub still performs a real
    `aws s3api head-bucket --bucket ... --expected-bucket-owner ...` call
    (via the mocked aws) so the expected marker command and bucket-owner/
    state-key values remain independently verifiable.
  * The real system `jq` binary is used (via shutil.which), wrapped by a
    thin logging passthrough in mock_bin, rather than mocking jq's
    behavior. This lets scripts/validate-uat-workforce-principals.sh run
    for real (as its own existing test suite already relies on real jq),
    while still letting the command log capture "jq -e" invocations for
    ordering assertions. If jq is not on PATH, these tests are skipped.
  * Command-order assertions use a forward-scanning "ordered subsequence"
    helper (assert_ordered_prefixes) rather than exact list equality for
    the eks-access path, because the real principal validator issues
    several independent "jq -e" calls (object shape, string/prefix
    checks, uniqueness, and one regex check per role) that the plan's
    abbreviated EXPECTED_EKS_ACCESS_ORDER represents with a single "jq -e"
    marker. The governance path (no jq calls at all) is checked the same
    way for consistency, plus one exact-equality assertion where the
    full sequence is short and deterministic.
  * `run_provision` dispatches `eks-access` through a narrower driver than
    `access-governance`/`all`. Task 3's registry (frozen; Task 5's own
    Files: list excludes scope-registry.sh and orchestrator.sh, and its
    Step 4 text says "do not change registry dependencies/order/symbol
    mappings") gives `eks-access` a real, still-external-work-package-3
    dependency on `eks-platform`. `run_unified_command`'s whole-graph
    pre-resolution gate therefore still blocks a narrow `eks-access`
    request today with "eks-platform requires work package 3" -- this is
    exact, intentional, already-committed Task 3 behavior (see
    DecisiveDispatchTests.test_narrow_scope_cascade_also_fails_before_its_own_pending_dependency_runs
    in test_scope_registry.py). Task 6 ("UAT provision eks-access |
    implemented after existing-platform verification") is where the real
    public-CLI bypass is wired in, via a distinct dependency-status
    reclassification that only Task 6 is authorized to make. Until then,
    this fixture composes the exact same real orchestration building
    blocks `run_unified_command` itself calls (identity/region check,
    package-fragment load, path init, lock, cleanup) directly around the
    real, non-stubbed `foundation_provision_eks_access` handler, skipping
    only the whole-graph dependency gate -- never touching
    orchestrator.sh or scope-registry.sh, and never weakening any
    identity/context/auth-mode/backend/cleanup guard under test.
"""

import json
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from .helpers import REPO_ROOT

UAT_ACCOUNT_ID = "672172129937"
DEV_ACCOUNT_ID = "815402439714"
AWS_REGION = "ap-east-1"
EKS_CLUSTER_NAME = "EKS-boomi-runtime-cluster"
EXPECTED_CLUSTER_REF = f"arn:aws:eks:{AWS_REGION}:{UAT_ACCOUNT_ID}:cluster/{EKS_CLUSTER_NAME}"

REAL_JQ = shutil.which("jq")

# `eks-access` cannot yet dispatch through the real public `run_unified_command`
# entrypoint: Task 3's frozen registry gives it a real dependency on
# `eks-platform` (external work package 3), which still blocks
# `run_unified_command`'s whole-graph pre-resolution gate exactly as
# intentionally tested by test_scope_registry.py's
# DecisiveDispatchTests.test_narrow_scope_cascade_also_fails_before_its_own_pending_dependency_runs.
# Task 5's own Files: list excludes both scope-registry.sh and
# orchestrator.sh, and its Step 4 text forbids changing registry
# dependencies/order/symbol mappings or adding scope-specific dispatch
# branches to orchestrator.sh -- so this fixture cannot fix that gate.
# Task 6 ("UAT provision eks-access | implemented after existing-platform
# verification") is where the real bypass is wired into the public CLI.
# Until then, this driver composes the same real orchestration building
# blocks `run_unified_command` itself calls -- identity/region check,
# package-fragment load, path init, lock, cleanup -- directly around the
# real, non-stubbed `foundation_provision_eks_access` handler, skipping only
# the whole-graph dependency gate. `access-governance` and `all` are
# unaffected by this and always go through the real `run_unified_command`.
_PROVISION_DRIVER = r"""
set -eo pipefail
source scripts/lib/orchestrator.sh

original_args=("$@")

op="$1"; shift
if [[ "$1" != "--env" ]]; then
  echo "expected --env" >&2
  exit 1
fi
shift
env_name="$1"; shift
scope="$1"; shift

auto_approve="false"
for arg in "$@"; do
  if [[ "$arg" == "--auto-approve" ]]; then
    auto_approve="true"
  fi
done

if [[ "$op" == "provision" && "$scope" == "eks-access" ]]; then
  reject_execution_environment_overrides
  load_platform_env "$env_name"
  require_environment_mutation_authorized "$env_name"
  verify_aws_identity_and_region
  _orchestrator_load_package_fragments provision eks-access
  initialize_orchestration_paths "$env_name"
  acquire_orchestration_lock
  export UNIFIED_AUTO_APPROVE="$auto_approve"
  status=0
  foundation_provision_eks_access || status=$?
  cleanup_orchestration_artifacts "$status"
  exit "$status"
fi

run_unified_command "${original_args[@]}"
"""

_AWS_MOCK = """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
case "$1" in
  sts)
    if [[ "$2" == "get-caller-identity" ]]; then
      printf '%s\\n' "${MOCK_AWS_ACCOUNT_ID:-672172129937}"
      exit "${MOCK_AWS_STS_EXIT:-0}"
    fi
    ;;
  configure)
    if [[ "$2" == "get" && "$3" == "region" ]]; then
      printf '%s\\n' "${MOCK_AWS_CONFIGURED_REGION:-}"
      exit 0
    fi
    ;;
  s3api)
    if [[ "$2" == "head-bucket" ]]; then
      exit "${MOCK_AWS_S3_HEAD_BUCKET_EXIT:-0}"
    fi
    ;;
  eks)
    if [[ "$2" == "describe-cluster" ]]; then
      printf '%s\\n' "${MOCK_AWS_EKS_AUTH_MODE:-API}"
      exit "${MOCK_AWS_EKS_EXIT:-0}"
    fi
    ;;
esac
exit 97
"""

_KUBECTL_MOCK = """#!/usr/bin/env bash
printf 'kubectl %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [[ "$1" == "config" && "$2" == "current-context" ]]; then
  printf '%s\\n' "${MOCK_KUBECTL_CONTEXT:-uat-context}"
  exit "${MOCK_KUBECTL_CONTEXT_EXIT:-0}"
fi
if [[ "$1" == "config" && "$2" == "view" ]]; then
  printf '%s\\n' "${MOCK_KUBECTL_CLUSTER_REF:-arn:aws:eks:ap-east-1:672172129937:cluster/EKS-boomi-runtime-cluster}"
  exit "${MOCK_KUBECTL_VIEW_EXIT:-0}"
fi
exit 97
"""

_TERRAFORM_MOCK = """#!/usr/bin/env bash
printf 'terraform %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
subcommand="$2"
case "$subcommand" in
  fmt)
    exit "${MOCK_TERRAFORM_FMT_EXIT:-0}"
    ;;
  validate)
    exit "${MOCK_TERRAFORM_VALIDATE_EXIT:-0}"
    ;;
  plan)
    exit "${MOCK_TERRAFORM_PLAN_EXIT:-0}"
    ;;
  apply)
    if [[ -n "${GENERATED_DIR_FOR_CHECK:-}" ]]; then
      shopt -s nullglob
      leftover=("$GENERATED_DIR_FOR_CHECK"/eks-access.*.auto.tfvars.json)
      shopt -u nullglob
      if [[ "${#leftover[@]}" -gt 0 ]]; then
        printf 'GENERATED_TFVARS_STILL_EXISTS %s\\n' "${leftover[*]}" >> "$MOCK_COMMAND_LOG"
      fi
    fi
    exit "${MOCK_TERRAFORM_APPLY_EXIT:-0}"
    ;;
  *)
    exit 0
    ;;
esac
"""

_JQ_MOCK_TEMPLATE = """#!/usr/bin/env bash
printf 'jq %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
exec "{real_jq}" "$@"
"""

_BACKEND_BOOTSTRAP_STUB = """#!/usr/bin/env bash
printf 'bootstrap-terraform-s3-backend.sh %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
bucket=""
owner=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) bucket="$2"; shift 2 ;;
    --expected-bucket-owner) owner="$2"; shift 2 ;;
    *) shift ;;
  esac
done
aws s3api head-bucket --bucket "$bucket" --expected-bucket-owner "$owner"
"""


class AccessDispatchFixture(unittest.TestCase):
    """Shared fixture for requirements 1-9, 11, and 12. Builds a clean,
    explicit child-process environment (never os.environ.copy()) with
    dispatch-aware, independently controllable mocks for aws/kubectl/
    terraform, a real-jq-wrapping mock for jq, and a purpose-built stub for
    scripts/bootstrap-terraform-s3-backend.sh (see module docstring)."""

    def setUp(self):
        if REAL_JQ is None:
            self.skipTest("jq must be installed and on PATH to exercise the real principal validator")

        self.temporary = tempfile.TemporaryDirectory()
        # Resolve symlinks (e.g. macOS /var -> /private/var) so self.root
        # matches the real, canonical path any `cd ... && pwd` computation
        # inside a bash script under test will naturally produce.
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = Path(self.temporary.name) / "bin"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)

        self._write_executable(self.mock_bin / "aws", _AWS_MOCK)
        self._write_executable(self.mock_bin / "kubectl", _KUBECTL_MOCK)
        self._write_executable(self.mock_bin / "terraform", _TERRAFORM_MOCK)
        self._write_executable(self.mock_bin / "jq", _JQ_MOCK_TEMPLATE.format(real_jq=REAL_JQ))

        self._copy(
            "scripts/lib/orchestrator.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "scripts/lib/scope-handlers.d/10-foundation-access.sh",
            "scripts/lib/scope-verifiers.d/10-foundation-access.sh",
            "scripts/lib/packages/10-foundation-access/internal/access-scopes.sh",
            "scripts/validate-uat-workforce-principals.sh",
            "config/environment-schema/base.manifest",
            "config/environments/uat.env",
            "platform-prerequisites/terraform/access-governance/.terraform.lock.hcl",
            "platform-prerequisites/terraform/access-governance/main.tf",
            "platform-prerequisites/terraform/access-governance/outputs.tf",
            "platform-prerequisites/terraform/access-governance/uat.tfvars",
            "platform-prerequisites/terraform/access-governance/variables.tf",
            "platform-prerequisites/terraform/access-governance/versions.tf",
            "platform-prerequisites/terraform/eks-access/.terraform.lock.hcl",
            "platform-prerequisites/terraform/eks-access/main.tf",
            "platform-prerequisites/terraform/eks-access/outputs.tf",
            "platform-prerequisites/terraform/eks-access/uat.tfvars",
            "platform-prerequisites/terraform/eks-access/variables.tf",
            "platform-prerequisites/terraform/eks-access/versions.tf",
        )
        validator = self.root / "scripts" / "validate-uat-workforce-principals.sh"
        validator.chmod(validator.stat().st_mode | stat.S_IXUSR)

        self._write_executable(
            self.root / "scripts" / "bootstrap-terraform-s3-backend.sh", _BACKEND_BOOTSTRAP_STUB
        )

        self.governance_tf_dir = self.root / "platform-prerequisites" / "terraform" / "access-governance"
        self.eks_access_tf_dir = self.root / "platform-prerequisites" / "terraform" / "eks-access"
        self.plan_dir = self.root / ".local" / "uat" / "plans"
        self.generated_dir = self.root / ".local" / "uat" / "generated"
        self.principals_path = (
            self.root / "config" / "environments" / "uat.local" / "workforce-principals.json"
        )

        self.valid_principals = {
            "infra_admin_role_arn": self._role_arn("UATInfraAdminEA", "111111"),
            "application_developer_role_arn": self._role_arn("UATApplicationDeveloper", "222222"),
            "boomi_admin_role_arn": self._role_arn("UATBoomiAdmin", "333333"),
            "process_owner_role_arn": self._role_arn("UATBoomiProcessOwner", "444444"),
        }

    def tearDown(self):
        self.temporary.cleanup()

    # -- setup helpers ----------------------------------------------------

    @staticmethod
    def _role_arn(permission_set, suffix, account=UAT_ACCOUNT_ID):
        return (
            f"arn:aws:iam::{account}:role/aws-reserved/sso.amazonaws.com/"
            f"ap-east-1/AWSReservedSSO_{permission_set}_{suffix}"
        )

    def _write_executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _copy(self, *relative_paths):
        for relative in relative_paths:
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    # -- principals fixture data -------------------------------------------

    def write_principals(self, principals):
        self.principals_path.parent.mkdir(parents=True, exist_ok=True)
        self.principals_path.write_text(json.dumps(principals), encoding="utf-8")

    def write_valid_principals(self):
        self.write_principals(self.valid_principals)

    # -- command log helpers ------------------------------------------------

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text(encoding="utf-8").splitlines() if line]

    def reset_command_log(self):
        self.command_log.write_text("", encoding="utf-8")

    def snapshot_tf_dir(self, tf_dir):
        return sorted(str(p.relative_to(tf_dir)) for p in tf_dir.rglob("*"))

    def assert_ordered_prefixes(self, lines, prefixes):
        """Assert each prefix in `prefixes` matches some line in `lines`, in
        order, allowing arbitrary extra lines in between (but none out of
        order). Returns the matched indices."""
        cursor = 0
        matched = []
        for prefix in prefixes:
            found = None
            for index in range(cursor, len(lines)):
                if lines[index].startswith(prefix):
                    found = index
                    break
            self.assertIsNotNone(
                found, f"expected a line starting with {prefix!r} at or after index {cursor} in {lines}"
            )
            matched.append(found)
            cursor = found + 1
        return matched

    def single_line_starting_with(self, lines, prefix):
        matches = [line for line in lines if line.startswith(prefix)]
        self.assertEqual(len(matches), 1, f"expected exactly one line starting with {prefix!r}, got: {lines}")
        return matches[0]

    @staticmethod
    def extract_flag_value(line, flag, occurrence=1):
        tokens = line.split()
        matches = [token[len(flag):] for token in tokens if token.startswith(flag)]
        return matches[occurrence - 1]

    def assert_only_uat_artifacts_remain(self):
        self.assertFalse((self.root / ".local" / "dev").exists())
        if self.plan_dir.exists():
            self.assertEqual(list(self.plan_dir.iterdir()), [])
        if self.generated_dir.exists():
            self.assertEqual(list(self.generated_dir.iterdir()), [])

    # -- invocation ---------------------------------------------------------

    def base_env(self, **overrides):
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
            "MOCK_AWS_ACCOUNT_ID": UAT_ACCOUNT_ID,
            "MOCK_AWS_CONFIGURED_REGION": "",
            "MOCK_AWS_S3_HEAD_BUCKET_EXIT": "0",
            "MOCK_AWS_EKS_AUTH_MODE": "API",
            "MOCK_AWS_EKS_EXIT": "0",
            "MOCK_AWS_STS_EXIT": "0",
            "MOCK_KUBECTL_CONTEXT": "uat-context",
            "MOCK_KUBECTL_CLUSTER_REF": EXPECTED_CLUSTER_REF,
            "MOCK_KUBECTL_CONTEXT_EXIT": "0",
            "MOCK_KUBECTL_VIEW_EXIT": "0",
            "MOCK_TERRAFORM_FMT_EXIT": "0",
            "MOCK_TERRAFORM_VALIDATE_EXIT": "0",
            "MOCK_TERRAFORM_PLAN_EXIT": "0",
            "MOCK_TERRAFORM_APPLY_EXIT": "0",
        }
        environment.update({key: str(value) for key, value in overrides.items()})
        return environment

    def run_provision(self, args, extra_env=None, stdin_text=None):
        environment = self.base_env(**(extra_env or {}))
        argv = [
            "bash", "-c", _PROVISION_DRIVER,
            "bash", "provision", "--env", "uat", *args,
        ]
        if stdin_text is not None:
            return subprocess.run(
                argv, cwd=self.root, env=environment, text=True, capture_output=True, input=stdin_text,
            )
        return subprocess.run(
            argv, cwd=self.root, env=environment, text=True, capture_output=True,
            stdin=subprocess.DEVNULL,
        )


class GovernanceDispatchOrderTests(AccessDispatchFixture):
    """Requirement 1: access-governance dispatch uses
    ACCESS_GOVERNANCE_STATE_KEY and the expected bucket owner, in the exact
    order aws identity -> region -> backend bucket check -> terraform
    fmt/validate/plan/apply."""

    def test_access_governance_uses_its_state_key_and_bucket_owner_in_exact_order(self):
        result = self.run_provision(["access-governance", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        self.assert_ordered_prefixes(
            lines,
            [
                "aws sts get-caller-identity",
                "aws configure get region",
                "aws s3api head-bucket",
                f"terraform -chdir={self.governance_tf_dir} fmt -check -recursive",
                f"terraform -chdir={self.governance_tf_dir} validate",
                f"terraform -chdir={self.governance_tf_dir} plan -input=false",
                f"terraform -chdir={self.governance_tf_dir} apply -input=false",
            ],
        )
        backend_line = self.single_line_starting_with(lines, "bootstrap-terraform-s3-backend.sh")
        self.assertIn("--key oms/uat/access-governance.tfstate", backend_line)
        self.assertIn(f"--expected-bucket-owner {UAT_ACCOUNT_ID}", backend_line)


class EksAccessDispatchOrderTests(AccessDispatchFixture):
    """Requirement 2: eks-access dispatch validates the canonical Kubernetes
    context, the EKS authentication mode, and the local principals input
    before ever touching the access backend, in the exact order given by
    the plan's EXPECTED_EKS_ACCESS_ORDER."""

    def test_eks_access_validates_context_auth_mode_and_principals_before_backend(self):
        self.write_valid_principals()
        result = self.run_provision(["eks-access", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        self.assert_ordered_prefixes(
            lines,
            [
                "aws sts get-caller-identity",
                "aws configure get region",
                "kubectl config current-context",
                "kubectl config view --minify",
                "aws eks describe-cluster",
                "jq -e",
                "aws s3api head-bucket",
                f"terraform -chdir={self.eks_access_tf_dir} fmt -check -recursive",
                f"terraform -chdir={self.eks_access_tf_dir} validate",
                f"terraform -chdir={self.eks_access_tf_dir} plan -input=false",
                f"terraform -chdir={self.eks_access_tf_dir} apply -input=false",
            ],
        )
        backend_line = self.single_line_starting_with(lines, "bootstrap-terraform-s3-backend.sh")
        self.assertIn("--key oms/uat/eks-access.tfstate", backend_line)
        self.assertIn(f"--expected-bucket-owner {UAT_ACCOUNT_ID}", backend_line)


class PrincipalInputPathTests(AccessDispatchFixture):
    """Requirement 3: eks-access reads its principal input from exactly
    config/environments/uat.local/workforce-principals.json, checked (and
    named in the error) before any AWS/kubectl/terraform command past the
    dependency checks."""

    def test_principal_input_is_read_from_the_exact_environment_local_path(self):
        # Deliberately do not create the principals file.
        result = self.run_provision(["eks-access", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(self.principals_path), result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "aws sts get-caller-identity --region ap-east-1 --query Account --output text",
                "aws configure get region",
                "kubectl config current-context",
                "kubectl config view --minify -o jsonpath={.contexts[0].context.cluster}",
                "aws eks describe-cluster --name EKS-boomi-runtime-cluster --region ap-east-1 "
                "--query cluster.accessConfig.authenticationMode --output text",
            ],
        )


class LocalArtifactLocationTests(AccessDispatchFixture):
    """Requirement 4: generated tfvars and saved Terraform plans exist only
    beneath .local/uat/ and never inside a Terraform root itself."""

    def test_governance_plan_and_apply_paths_are_beneath_local_uat_only(self):
        before = self.snapshot_tf_dir(self.governance_tf_dir)
        result = self.run_provision(["access-governance", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        plan_line = self.single_line_starting_with(
            lines, f"terraform -chdir={self.governance_tf_dir} plan"
        )
        apply_line = self.single_line_starting_with(
            lines, f"terraform -chdir={self.governance_tf_dir} apply"
        )
        plan_out = self.extract_flag_value(plan_line, "-out=")
        self.assertTrue(plan_out.startswith(str(self.plan_dir) + "/"), plan_out)
        self.assertEqual(apply_line.split()[-1], plan_out)
        self.assertEqual(self.snapshot_tf_dir(self.governance_tf_dir), before)

    def test_eks_access_generated_tfvars_and_plan_paths_are_beneath_local_uat_only(self):
        self.write_valid_principals()
        before = self.snapshot_tf_dir(self.eks_access_tf_dir)
        result = self.run_provision(["eks-access", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        plan_line = self.single_line_starting_with(
            lines, f"terraform -chdir={self.eks_access_tf_dir} plan"
        )
        plan_out = self.extract_flag_value(plan_line, "-out=")
        generated_value = self.extract_flag_value(plan_line, "-var-file=", occurrence=2)
        self.assertTrue(plan_out.startswith(str(self.plan_dir) + "/"), plan_out)
        self.assertTrue(generated_value.startswith(str(self.generated_dir) + "/"), generated_value)
        self.assertEqual(self.snapshot_tf_dir(self.eks_access_tf_dir), before)


class GeneratedTfvarsCleanupTimingTests(AccessDispatchFixture):
    """Requirement 5: the generated principal tfvars file is removed
    immediately after the saved plan captures it, before the apply-approval
    prompt/apply itself. Proven by having the terraform mock check, only at
    its own `apply` invocation, whether any such file still exists."""

    def test_generated_tfvars_are_gone_before_apply_runs(self):
        self.write_valid_principals()
        result = self.run_provision(
            ["eks-access", "--auto-approve"],
            extra_env={"GENERATED_DIR_FOR_CHECK": str(self.generated_dir)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        self.assertFalse(
            any(line.startswith("GENERATED_TFVARS_STILL_EXISTS") for line in lines), lines
        )
        self.assertTrue(
            any(line.startswith(f"terraform -chdir={self.eks_access_tf_dir} apply") for line in lines)
        )


class AppliedPlanInvocationTests(AccessDispatchFixture):
    """Requirement 6: apply is invoked with exactly one, unchanged plan
    path and never with -auto-approve."""

    def test_apply_receives_exactly_one_unchanged_plan_path_and_no_auto_approve_flag(self):
        result = self.run_provision(["access-governance", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_log_lines()
        plan_line = self.single_line_starting_with(
            lines, f"terraform -chdir={self.governance_tf_dir} plan"
        )
        apply_line = self.single_line_starting_with(
            lines, f"terraform -chdir={self.governance_tf_dir} apply"
        )
        plan_out = self.extract_flag_value(plan_line, "-out=")
        apply_args = apply_line.split()[3:]
        self.assertEqual(apply_args, ["-input=false", plan_out])
        self.assertNotIn("-auto-approve", apply_line)


class InteractiveApprovalTests(AccessDispatchFixture):
    """Requirement 7: without --auto-approve, apply only proceeds when the
    operator types the exact literal "yes"; anything else, or EOF, aborts
    before apply."""

    def test_exact_yes_proceeds_to_apply(self):
        result = self.run_provision(["access-governance"], stdin_text="yes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            any(
                line.startswith(f"terraform -chdir={self.governance_tf_dir} apply")
                for line in self.command_log_lines()
            )
        )

    def test_any_other_response_aborts_before_apply(self):
        for response in ("no\n", "Yes\n", "y\n", " yes\n"):
            with self.subTest(response=response):
                self.reset_command_log()
                result = self.run_provision(["access-governance"], stdin_text=response)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("apply aborted for scope: access-governance", result.stderr)
                self.assertFalse(
                    any(
                        line.startswith(f"terraform -chdir={self.governance_tf_dir} apply")
                        for line in self.command_log_lines()
                    )
                )

    def test_eof_aborts_before_apply(self):
        result = self.run_provision(["access-governance"], stdin_text="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("apply aborted for scope: access-governance", result.stderr)
        self.assertFalse(
            any(
                line.startswith(f"terraform -chdir={self.governance_tf_dir} apply")
                for line in self.command_log_lines()
            )
        )


class AutoApproveGuardsTests(AccessDispatchFixture):
    """Requirement 8, positive half: --auto-approve really does skip the
    interactive prompt (reaches apply with no stdin available at all). The
    negative half (guards still apply) is proven by
    FailureModeCleanupIsolationTests, where every scenario also passes
    --auto-approve."""

    def test_auto_approve_reaches_apply_without_any_stdin(self):
        result = self.run_provision(["access-governance", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            any(
                line.startswith(f"terraform -chdir={self.governance_tf_dir} apply")
                for line in self.command_log_lines()
            )
        )


class FailureModeCleanupIsolationTests(AccessDispatchFixture):
    """Requirement 9 (and, since every scenario here passes
    --auto-approve, the negative half of requirement 8): each failure mode
    stops dispatch at the right guard, never reaches steps beyond it, and
    only ever touches UAT temporary artifacts (dev is never created; any
    plan/generated directories that do exist end up empty; Terraform roots
    are never modified)."""

    def test_wrong_account_stops_before_any_further_command(self):
        result = self.run_provision(
            ["access-governance", "--auto-approve"],
            extra_env={"MOCK_AWS_ACCOUNT_ID": "999999999999"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("active AWS account is 999999999999", result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            ["aws sts get-caller-identity --region ap-east-1 --query Account --output text"],
        )
        self.assert_only_uat_artifacts_remain()

    def test_wrong_configured_region_stops_before_any_further_command(self):
        result = self.run_provision(
            ["access-governance", "--auto-approve"],
            extra_env={"MOCK_AWS_CONFIGURED_REGION": "us-west-2"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("aws configure region is us-west-2", result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "aws sts get-caller-identity --region ap-east-1 --query Account --output text",
                "aws configure get region",
            ],
        )
        self.assert_only_uat_artifacts_remain()

    def test_wrong_kubernetes_context_stops_before_backend_access(self):
        self.write_valid_principals()
        result = self.run_provision(
            ["eks-access", "--auto-approve"],
            extra_env={
                "MOCK_KUBECTL_CLUSTER_REF": "arn:aws:eks:ap-east-1:672172129937:cluster/OTHER-CLUSTER",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not target uat", result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "aws sts get-caller-identity --region ap-east-1 --query Account --output text",
                "aws configure get region",
                "kubectl config current-context",
                "kubectl config view --minify -o jsonpath={.contexts[0].context.cluster}",
            ],
        )
        self.assert_only_uat_artifacts_remain()

    def test_wrong_authentication_mode_stops_before_backend_access(self):
        self.write_valid_principals()
        result = self.run_provision(
            ["eks-access", "--auto-approve"],
            extra_env={"MOCK_AWS_EKS_AUTH_MODE": "CONFIG_MAP"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authentication mode is 'CONFIG_MAP'; expected API", result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "aws sts get-caller-identity --region ap-east-1 --query Account --output text",
                "aws configure get region",
                "kubectl config current-context",
                "kubectl config view --minify -o jsonpath={.contexts[0].context.cluster}",
                "aws eks describe-cluster --name EKS-boomi-runtime-cluster --region ap-east-1 "
                "--query cluster.accessConfig.authenticationMode --output text",
            ],
        )
        self.assert_only_uat_artifacts_remain()

    def test_invalid_principals_stop_before_backend_access(self):
        invalid = dict(self.valid_principals)
        invalid["boomi_admin_role_arn"] = self.valid_principals["boomi_admin_role_arn"].replace(
            "UATBoomiAdmin", "UATBoomiReadOnly"
        )
        self.write_principals(invalid)
        result = self.run_provision(["eks-access", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AWSReservedSSO_UATBoomiAdmin", result.stderr)
        lines = self.command_log_lines()
        self.assertFalse(any(line.startswith("aws s3api") for line in lines), lines)
        self.assertFalse(any(line.startswith("terraform") for line in lines), lines)
        self.assert_only_uat_artifacts_remain()

    def test_lock_contention_leaves_the_existing_lock_untouched(self):
        lock_dir = self.root / ".local" / "uat" / "locks" / "orchestration.lock"
        lock_dir.mkdir(parents=True)
        result = self.run_provision(["access-governance", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another orchestration run holds the lock", result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "aws sts get-caller-identity --region ap-east-1 --query Account --output text",
                "aws configure get region",
            ],
        )
        self.assertTrue(lock_dir.exists())
        self.assert_only_uat_artifacts_remain()

    def test_backend_failure_stops_before_any_terraform_command(self):
        result = self.run_provision(
            ["access-governance", "--auto-approve"],
            extra_env={"MOCK_AWS_S3_HEAD_BUCKET_EXIT": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        lines = self.command_log_lines()
        self.assertFalse(any(line.startswith("terraform") for line in lines), lines)
        self.assertTrue(any(line.startswith("aws s3api head-bucket") for line in lines), lines)
        self.assert_only_uat_artifacts_remain()

    def test_plan_failure_stops_before_apply(self):
        result = self.run_provision(
            ["access-governance", "--auto-approve"],
            extra_env={"MOCK_TERRAFORM_PLAN_EXIT": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        lines = self.command_log_lines()
        self.assertTrue(
            any(line.startswith(f"terraform -chdir={self.governance_tf_dir} plan") for line in lines)
        )
        self.assertFalse(
            any(line.startswith(f"terraform -chdir={self.governance_tf_dir} apply") for line in lines)
        )
        self.assert_only_uat_artifacts_remain()

    def test_apply_failure_is_reported_and_cleans_up(self):
        result = self.run_provision(
            ["access-governance", "--auto-approve"],
            extra_env={"MOCK_TERRAFORM_APPLY_EXIT": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        lines = self.command_log_lines()
        self.assertTrue(
            any(line.startswith(f"terraform -chdir={self.governance_tf_dir} apply") for line in lines)
        )
        self.assert_only_uat_artifacts_remain()


class CleanupContractFixture(unittest.TestCase):
    """Minimal fixture exercising only scripts/lib/orchestration-paths.sh,
    the shared cleanup contract every access-scopes.sh function relies on
    for its own registered plan/generated artifacts."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.root.mkdir(parents=True)
        source = REPO_ROOT / "scripts" / "lib" / "orchestration-paths.sh"
        destination = self.root / "scripts" / "lib" / "orchestration-paths.sh"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    def tearDown(self):
        self.temporary.cleanup()

    def run_snippet(self, original_status):
        script = (
            "source scripts/lib/orchestration-paths.sh\n"
            "initialize_orchestration_paths uat\n"
            "acquire_orchestration_lock\n"
            'undeletable="$GENERATED_DIR/undeletable"\n'
            'mkdir "$undeletable"\n'
            'register_orchestration_artifact "$undeletable"\n'
            f"cleanup_orchestration_artifacts {original_status}\n"
            'echo "RESULT:$?"\n'
        )
        return subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )

    @staticmethod
    def _result_code(completed):
        return completed.stdout.strip().splitlines()[-1].split(":", 1)[1]


class OriginalFailureVsCleanupFailureTests(CleanupContractFixture):
    """Requirement 10: a cleanup failure alone turns an otherwise-
    successful run into a failure, but an original failure always wins
    over a simultaneous cleanup failure -- tested directly against the
    exact shared mechanism (register_orchestration_artifact +
    cleanup_orchestration_artifacts) access-scopes.sh relies on."""

    def test_cleanup_failure_alone_turns_success_into_failure(self):
        result = self.run_snippet(0)
        self.assertNotEqual(self._result_code(result), "0", result.stdout)

    def test_original_failure_wins_over_a_simultaneous_cleanup_failure(self):
        result = self.run_snippet(17)
        self.assertEqual(self._result_code(result), "17", result.stdout)


class UnifiedAllPreResolutionTests(AccessDispatchFixture):
    """Requirement 11: `all` fails fast on the still-deferred eks-platform
    scope (work package 3) during whole-order pre-resolution, before any
    access-scope handler -- not even access-governance's, which is itself
    already implemented -- is ever invoked."""

    def test_all_fails_on_deferred_eks_platform_before_any_access_handler_runs(self):
        result = self.run_provision(["all", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eks-platform requires work package 3", result.stderr)
        lines = self.command_log_lines()
        for line in lines:
            self.assertFalse(line.startswith("terraform"), lines)
            self.assertFalse(line.startswith("kubectl"), lines)
            self.assertFalse(line.startswith("jq"), lines)
            self.assertFalse(line.startswith("aws s3api"), lines)
            self.assertFalse(line.startswith("aws eks"), lines)
            self.assertFalse(line.startswith("bootstrap-terraform-s3-backend"), lines)


class NoLegacyOrDevArtifactLeakageTests(AccessDispatchFixture):
    """Requirement 12: explicit UAT access dispatch never invokes any
    scripts/legacy/dev script and never mentions the dev AWS account id."""

    def test_governance_and_eks_access_logs_contain_no_legacy_or_dev_account_trace(self):
        self.write_valid_principals()
        for scope in ("access-governance", "eks-access"):
            with self.subTest(scope=scope):
                self.reset_command_log()
                result = self.run_provision([scope, "--auto-approve"])
                self.assertEqual(result.returncode, 0, result.stderr)
                combined = "\n".join(self.command_log_lines()) + result.stdout + result.stderr
                self.assertNotIn(DEV_ACCOUNT_ID, combined)
                self.assertNotIn("legacy", combined.lower())
        self.assertFalse((self.root / "scripts" / "legacy").exists())


_PROVISION_STUB = (
    "#!/usr/bin/env bash\n"
    "printf 'provision.sh %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
    'exit "${MOCK_PROVISION_EXIT:-0}"\n'
)


class CompatibilityWrapperFixture(unittest.TestCase):
    """Fixture for requirement 13: only the real
    scripts/provision-uat-access.sh is exercised; scripts/provision.sh is
    replaced with a simple logging stub so these tests assert forwarding
    arguments in isolation, without needing the full unified-orchestrator
    mock stack."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)

        source = REPO_ROOT / "scripts" / "provision-uat-access.sh"
        destination = self.root / "scripts" / "provision-uat-access.sh"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        destination.chmod(destination.stat().st_mode | stat.S_IXUSR)

        provision_stub = self.root / "scripts" / "provision.sh"
        provision_stub.write_text(_PROVISION_STUB, encoding="utf-8")
        provision_stub.chmod(provision_stub.stat().st_mode | stat.S_IXUSR)

    def tearDown(self):
        self.temporary.cleanup()

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text(encoding="utf-8").splitlines() if line]

    def run_wrapper(self, args, extra_env=None):
        environment = {"PATH": "/usr/bin:/bin", "MOCK_COMMAND_LOG": str(self.command_log)}
        if extra_env:
            environment.update({key: str(value) for key, value in extra_env.items()})
        return subprocess.run(
            ["bash", "scripts/provision-uat-access.sh", *args],
            cwd=self.root, env=environment, text=True, capture_output=True,
        )


class CompatibilityWrapperForwardingTests(CompatibilityWrapperFixture):
    """Requirement 13: scripts/provision-uat-access.sh forwards to the
    explicit unified commands and never to unified `all`."""

    def test_governance_forwards_to_unified_access_governance(self):
        result = self.run_wrapper(["governance"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command_log_lines(), ["provision.sh --env uat access-governance"])
        self.assertIn("DEPRECATED", result.stderr)

    def test_eks_access_forwards_to_unified_eks_access(self):
        result = self.run_wrapper(["eks-access"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command_log_lines(), ["provision.sh --env uat eks-access"])

    def test_auto_approve_is_preserved_and_appended(self):
        for scope, expected in (
            ("governance", "provision.sh --env uat access-governance --auto-approve"),
            ("eks-access", "provision.sh --env uat eks-access --auto-approve"),
        ):
            with self.subTest(scope=scope):
                self.command_log.write_text("", encoding="utf-8")
                result = self.run_wrapper([scope, "--auto-approve"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.command_log_lines(), [expected])

    def test_all_forwards_sequentially_and_not_to_unified_all(self):
        result = self.run_wrapper(["all"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "provision.sh --env uat access-governance",
                "provision.sh --env uat eks-access",
            ],
        )

    def test_all_with_auto_approve_appends_flag_to_both_forwarded_calls(self):
        result = self.run_wrapper(["all", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "provision.sh --env uat access-governance --auto-approve",
                "provision.sh --env uat eks-access --auto-approve",
            ],
        )

    def test_first_forwarded_command_failure_stops_the_second(self):
        result = self.run_wrapper(["all"], extra_env={"MOCK_PROVISION_EXIT": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), ["provision.sh --env uat access-governance"])

    def test_unknown_scope_fails_before_any_forwarding(self):
        result = self.run_wrapper(["nonsense"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_unknown_trailing_argument_fails_before_any_forwarding(self):
        result = self.run_wrapper(["governance", "--bogus"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])


if __name__ == "__main__":
    unittest.main()
