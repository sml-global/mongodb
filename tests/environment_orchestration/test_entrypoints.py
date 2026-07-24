"""Task 4 ("Add Explicit Unified Entrypoints Without Changing Legacy Dev
Behavior") tests for the three public wrapper scripts (scripts/provision.sh,
scripts/destroy.sh, scripts/verify-platform-health.sh), the legacy dev
scripts they still route to by default (scripts/legacy/dev/*.sh), and the
unified orchestrator they route to under an explicit `--env dev|uat`
(scripts/lib/orchestrator.sh). This file does not modify or re-implement any
of those scripts; it only exercises the already-implemented behavior.

Six required coverage areas, and the test classes that cover them:
  1. Legacy behavioral regression       -> LegacyProvisionRegressionTests,
                                            LegacyDestroyRegressionTests,
                                            LegacyVerifyRegressionTests
  2. Sentinel-never-fires               -> SentinelNeverFiresTests
  3. Explicit parser rejection          -> ExplicitParserRejectionTests
  4. Dev mutation always blocked        -> DevMutationAlwaysBlockedTests
  5. Unified verification mode accept.  -> VerificationModeAcceptanceTests
  6. Destroy option grammar             -> DestroyOptionGrammarTests

Judgment calls made while writing this file (also called out at their exact
point of use below, and in the final chat report):

  * Fixture style: scripts/lib/orchestrator.sh's `run_unified_command`
    begins by calling `reject_execution_environment_overrides`, which fails
    the command if any of ~20 specific variable names (AWS_PROFILE,
    KUBECONFIG, TF_*, ...) are present in its environment. The shared
    RepositoryFixture in helpers.py builds its child-process environment
    from a full `os.environ.copy()`, which would make these tests depend on
    whatever the host process happens to have set -- a real correctness
    risk, not just a style preference. tests/environment_orchestration/
    test_guards_and_paths.py already hit this same problem for the guard
    functions themselves and established a local precedent: a *standalone*
    fixture (GuardsAndPathsFixture) that does not subclass RepositoryFixture
    and instead builds a clean, explicit environment dict. The fixtures
    below follow that same precedent (reusing only the REPO_ROOT constant
    from helpers.py) rather than subclassing RepositoryFixture directly.

  * scripts/legacy/dev/verify-platform-health.sh, when every external tool
    is mocked to fail, hits a `tf_version="$(terraform version -json | sed
    ...)"` assignment under `set -euo pipefail` before it ever reaches the
    AWS-identity fail_fatal check. Whether that specific command-
    substitution-in-an-assignment aborts the script at that exact line is a
    bash `-e` corner case this file deliberately does not try to pin down
    (doing so with certainty would require actually running the script,
    which this task forbids). The no-args/--preflight/--smoke-test legacy
    verify cases are therefore asserted loosely (nonzero, non-98, no
    crash-shaped output) while --help/--unknown -- which do not depend on
    this ambiguity at all -- are asserted precisely.

  * INVALID_EXPLICIT_FORMS form 7, `("--env", "uat", "unknown")`, is a
    syntactically well-formed single-scope invocation. Reading
    orchestrator.sh shows `verify_aws_identity_and_region` runs before
    `resolve_provision_order`/`resolve_destroy_order`, so this one form
    genuinely reaches (and fails at) a real mocked `aws` invocation before
    the unknown-scope error would ever be produced. Every other form fails
    before any command runs; this one is intentionally exempted from the
    "zero command invocations" assertion, with the reasoning left in place
    at its point of use.

Nothing in this file was executed while writing it (no python, no
`bash -n`, no git, no test runs) -- only read_file, list_dir, grep_search,
and this create_file call were used, per the explicit instruction that a
human will authorize test execution separately.
"""

import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from .helpers import REPO_ROOT

# ---------------------------------------------------------------------------
# Task 4 Step 1: representative legacy argument vectors (verbatim from the
# plan, docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-
# foundation.md, Task 4 section).
# ---------------------------------------------------------------------------

LEGACY_PROVISION_CASES = (
    ("all",),
    ("mongodb",),
    ("mongo",),
    ("pg", "--auto-approve"),
    ("signoz",),
    ("signoz-observability", "--auto-approve"),
    ("mongodb", "--bootstrap-platform-controllers"),
    ("unknown",),
)

LEGACY_DESTROY_CASES = (
    ("all",),
    ("mongodb",),
    ("mongo",),
    ("pg",),
    ("signoz",),
    ("signoz-observability",),
    ("unknown",),
)

LEGACY_VERIFY_CASES = (
    (),
    ("--preflight",),
    ("--smoke-test",),
    ("--help",),
    ("--unknown",),
)

# Task 4 Step 2: malformed leading-form vectors (verbatim from the plan).
INVALID_EXPLICIT_FORMS = (
    ("--env",),
    ("--env", "prod", "backend"),
    ("--env=uat", "backend"),
    ("backend", "--env", "uat"),
    ("--env", "uat"),
    ("--env", "uat", "--env", "dev", "backend"),
    ("--env", "uat", "unknown"),
)

_LOGGING_STUB_TEMPLATE = (
    "#!/usr/bin/env bash\n"
    "printf '{name} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
    "exit 0\n"
)

_SENTINEL_SCRIPT = (
    "#!/usr/bin/env bash\n"
    ": > \"$SENTINEL_MARKER\"\n"
    "exit 98\n"
)


# ---------------------------------------------------------------------------
# Shared fixture base.
#
# Deliberately does not subclass tests/environment_orchestration/helpers.py's
# RepositoryFixture -- see the module docstring's first judgment call for
# why. Mirrors test_guards_and_paths.py's GuardsAndPathsFixture: a from-
# scratch temp repository, generic (always-exit-97, log-only) aws/kubectl/
# terraform/kustomize mocks, and a clean, explicit child-process environment.
# ---------------------------------------------------------------------------

_MOCK_COMMAND_TEMPLATE = (
    "#!/usr/bin/env bash\n"
    "printf '{name} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
    "exit 97\n"
)


class _BaseFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # Resolve symlinks (e.g. macOS /var -> /private/var) so self.root
        # matches the real, canonical path any `cd ... && pwd` computation
        # inside a bash script under test will naturally produce.
        self.root = Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = Path(self.temporary.name) / "bin"
        self.command_log = Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)
        for command in ("aws", "kubectl", "terraform", "kustomize"):
            self._write_executable(
                self.mock_bin / command,
                _MOCK_COMMAND_TEMPLATE.format(name=command),
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

    def run_clean(self, argv, extra_env=None):
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        if extra_env:
            environment.update({key: str(value) for key, value in extra_env.items()})
        return subprocess.run(
            argv, cwd=self.root, env=environment, text=True, capture_output=True,
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [
            line for line in self.command_log.read_text(encoding="utf-8").splitlines() if line
        ]

    def reset_command_log(self):
        self.command_log.write_text("", encoding="utf-8")

    def local_dir_exists(self):
        return (self.root / ".local").exists()

    def tearDown(self):
        self.temporary.cleanup()


# ---------------------------------------------------------------------------
# Fixtures for requirement 1 (legacy behavioral regression).
# ---------------------------------------------------------------------------


class LegacyProvisionFixture(_BaseFixture):
    def setUp(self):
        super().setUp()
        self._copy("scripts/legacy/dev/provision.sh")
        for helper in (
            "provision-platform-prereq.sh",
            "provision-k8s-components.sh",
            "provision-signoz-observability.sh",
        ):
            self._write_executable(
                self.root / "scripts" / helper,
                _LOGGING_STUB_TEMPLATE.format(name=helper),
            )

    def run_provision(self, args):
        return self.run_clean(["bash", "scripts/legacy/dev/provision.sh", *args])


class LegacyDestroyFixture(_BaseFixture):
    def setUp(self):
        super().setUp()
        self._copy("scripts/legacy/dev/destroy.sh")
        self._write_executable(
            self.root / "scripts" / "bootstrap-terraform-s3-backend.sh",
            _LOGGING_STUB_TEMPLATE.format(name="bootstrap-terraform-s3-backend.sh"),
        )
        for tf_subdir in ("mongodb", "postgresql"):
            tfvars = self.root / "platform-prerequisites" / "terraform" / tf_subdir / "terraform.tfvars"
            tfvars.parent.mkdir(parents=True, exist_ok=True)
            tfvars.write_text("", encoding="utf-8")

    def run_destroy(self, args):
        return self.run_clean(["bash", "scripts/legacy/dev/destroy.sh", *args])


class LegacyVerifyFixture(_BaseFixture):
    def setUp(self):
        super().setUp()
        self._copy("scripts/legacy/dev/verify-platform-health.sh")

    def run_verify(self, args):
        return self.run_clean(["bash", "scripts/legacy/dev/verify-platform-health.sh", *args])


# ---------------------------------------------------------------------------
# Fixture for requirements 3-6 (everything that goes through the unified
# orchestrator via an explicit `--env dev|uat`).
# ---------------------------------------------------------------------------


class OrchestratorFixture(_BaseFixture):
    def setUp(self):
        super().setUp()
        self._copy(
            "scripts/lib/orchestrator.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )

    def run_unified(self, operation, args, extra_env=None):
        return self.run_clean(
            [
                "bash", "-c",
                "source scripts/lib/orchestrator.sh && run_unified_command \"$@\"",
                "bash", operation, *args,
            ],
            extra_env=extra_env,
        )


# ---------------------------------------------------------------------------
# Fixture for requirement 2 (sentinel-never-fires). Adds the three real
# public wrapper scripts on top of OrchestratorFixture, then overwrites
# scripts/legacy/dev/*.sh with sentinel scripts that record firing and exit
# 98 -- a code impossible to confuse with any real exit status used
# elsewhere in these scripts.
# ---------------------------------------------------------------------------


class WrapperFixture(OrchestratorFixture):
    def setUp(self):
        super().setUp()
        self._copy(
            "scripts/provision.sh",
            "scripts/destroy.sh",
            "scripts/verify-platform-health.sh",
        )
        self.sentinel_marker = Path(self.temporary.name) / "sentinel-fired"
        for name in ("provision.sh", "destroy.sh", "verify-platform-health.sh"):
            self._write_executable(
                self.root / "scripts" / "legacy" / "dev" / name, _SENTINEL_SCRIPT
            )

    def run_wrapper(self, wrapper, args):
        return self.run_clean(
            ["bash", f"scripts/{wrapper}", *args],
            extra_env={"SENTINEL_MARKER": str(self.sentinel_marker)},
        )


# ---------------------------------------------------------------------------
# Requirement 1: legacy behavioral regression.
# ---------------------------------------------------------------------------


class LegacyProvisionRegressionTests(LegacyProvisionFixture):
    """scripts/legacy/dev/provision.sh, run directly, with its three
    downstream helper scripts replaced by logging stubs."""

    def test_all_runs_mongodb_then_pg_prereqs_then_mongodb_k8s(self):
        result = self.run_provision(["all"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "provision-platform-prereq.sh mongodb",
                "provision-platform-prereq.sh pg",
                "provision-k8s-components.sh mongodb",
            ],
        )
        self.assertIn("Completed provisioning scope: all", result.stdout)

    def test_mongodb_and_mongo_alias_run_the_same_two_steps(self):
        for scope in ("mongodb", "mongo"):
            with self.subTest(scope=scope):
                self.reset_command_log()
                result = self.run_provision([scope])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    self.command_log_lines(),
                    [
                        "provision-platform-prereq.sh mongodb",
                        "provision-k8s-components.sh mongodb",
                    ],
                )

    def test_pg_with_auto_approve_forwards_the_flag(self):
        result = self.run_provision(["pg", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(), ["provision-platform-prereq.sh pg --auto-approve"]
        )

    def test_signoz_runs_only_the_k8s_component_step(self):
        result = self.run_provision(["signoz"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command_log_lines(), ["provision-k8s-components.sh signoz"])

    def test_signoz_observability_with_auto_approve_calls_the_dedicated_script(self):
        result = self.run_provision(["signoz-observability", "--auto-approve"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            ["provision-signoz-observability.sh --auto-approve"],
        )

    def test_mongodb_with_bootstrap_platform_controllers_forwards_flag_to_k8s_step_only(self):
        result = self.run_provision(["mongodb", "--bootstrap-platform-controllers"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.command_log_lines(),
            [
                "provision-platform-prereq.sh mongodb",
                "provision-k8s-components.sh mongodb --bootstrap-platform-controllers",
            ],
        )

    def test_unknown_scope_fails_with_usage_and_no_child_invocation(self):
        result = self.run_provision(["unknown"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown scope 'unknown'", result.stderr)
        # usage() writes to stdout (a plain `cat <<'EOF' ... EOF` with no
        # redirect); only the "Error: ..." line is explicitly sent to
        # stderr via `>&2`.
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(self.command_log_lines(), [])

    def test_all_representative_vectors_run_without_crashing(self):
        # Traceability to the plan's exact LEGACY_PROVISION_CASES list, on
        # top of the precise per-case assertions above.
        for args in LEGACY_PROVISION_CASES:
            with self.subTest(args=args):
                self.reset_command_log()
                result = self.run_provision(list(args))
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("unbound variable", result.stderr)
                self.assertIn(result.returncode, (0, 1))


class LegacyDestroyRegressionTests(LegacyDestroyFixture):
    """scripts/legacy/dev/destroy.sh, run directly, with real (mocked)
    aws/kubectl/terraform binaries. Terraform is mocked to always fail
    (exit 97); under `set -euo pipefail` this aborts the script at the
    `terraform ... destroy` statement itself -- before "Completed destroy
    scope" ever prints. That is the script's own logic (never claim
    completion when the destroy command failed), reflected in the
    assertions below, not a test-harness limitation."""

    def test_mongodb_and_mongo_alias_reach_terraform_destroy_and_stop_there(self):
        for scope in ("mongodb", "mongo"):
            with self.subTest(scope=scope):
                self.reset_command_log()
                result = self.run_destroy([scope])
                self.assertEqual(result.returncode, 97, result.stderr)
                log = self.command_log_lines()
                self.assertTrue(
                    any(
                        "bootstrap-terraform-s3-backend.sh" in line and "mongo.tfstate" in line
                        for line in log
                    ),
                    log,
                )
                self.assertTrue(
                    any(line.startswith("terraform ") and "mongodb" in line for line in log),
                    log,
                )

    def test_pg_reaches_terraform_destroy_and_stops_there(self):
        result = self.run_destroy(["pg"])
        self.assertEqual(result.returncode, 97, result.stderr)
        log = self.command_log_lines()
        self.assertTrue(
            any(
                "bootstrap-terraform-s3-backend.sh" in line and "pg.tfstate" in line
                for line in log
            ),
            log,
        )

    def test_signoz_completes_cleanly_when_namespace_already_absent(self):
        result = self.run_destroy(["signoz"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Completed destroy scope: signoz", result.stdout)

    def test_signoz_observability_completes_cleanly_when_secret_already_absent(self):
        result = self.run_destroy(["signoz-observability"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Completed destroy scope: signoz-observability", result.stdout)

    def test_all_completes_signoz_steps_then_stops_at_first_terraform_failure(self):
        result = self.run_destroy(["all"])
        self.assertEqual(result.returncode, 97, result.stderr)
        log = self.command_log_lines()
        self.assertTrue(any("mongo.tfstate" in line for line in log), log)
        self.assertFalse(any("pg.tfstate" in line for line in log), log)

    def test_unknown_scope_fails_with_usage_and_no_terraform_invocation(self):
        result = self.run_destroy(["unknown"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown scope 'unknown'", result.stderr)
        log = self.command_log_lines()
        self.assertFalse(any(line.startswith("terraform ") for line in log), log)

    def test_all_representative_vectors_run_without_crashing(self):
        for args in LEGACY_DESTROY_CASES:
            with self.subTest(args=args):
                self.reset_command_log()
                result = self.run_destroy(list(args))
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("unbound variable", result.stderr)


class LegacyVerifyRegressionTests(LegacyVerifyFixture):
    """scripts/legacy/dev/verify-platform-health.sh, run directly. --help
    and --unknown are asserted precisely; the three cases that reach the
    mocked-tool-dependent checks are asserted loosely -- see this file's
    module docstring for why."""

    def test_help_prints_usage_and_exits_zero(self):
        result = self.run_verify(["--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage: verify-platform-health.sh", result.stdout)

    def test_unknown_flag_fails_with_a_usage_error(self):
        result = self.run_verify(["--unknown"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown arg", result.stderr)

    def test_tool_dependent_cases_fail_deterministically_without_crashing(self):
        for args in ((), ("--preflight",), ("--smoke-test",)):
            with self.subTest(args=args):
                result = self.run_verify(list(args))
                self.assertNotEqual(result.returncode, 0)
                self.assertNotEqual(result.returncode, 98)
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("unbound variable", result.stderr)
                self.assertNotIn("bad substitution", result.stderr)

    def test_all_representative_vectors_run_without_crashing(self):
        for args in LEGACY_VERIFY_CASES:
            with self.subTest(args=args):
                result = self.run_verify(list(args))
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("unbound variable", result.stderr)


# ---------------------------------------------------------------------------
# Requirement 2: sentinel-never-fires.
# ---------------------------------------------------------------------------


class SentinelNeverFiresTests(WrapperFixture):
    """Every explicit `--env uat ...` command below fails for an unrelated
    reason (mocked-failing AWS identity check, or an unknown/deferred
    scope) -- exactly the point: an explicit invocation must never fall
    through to scripts/legacy/dev/*.sh, even when it ultimately fails."""

    SENTINEL_COMMANDS = (
        ("provision.sh", ["--env", "uat", "mongodb"]),
        ("provision.sh", ["--env", "uat", "backend"]),
        ("provision.sh", ["--env", "uat", "unknown"]),
        ("destroy.sh", ["--env", "uat", "mongodb"]),
        ("destroy.sh", ["--env", "uat", "unknown"]),
        ("verify-platform-health.sh", ["--env", "uat"]),
        ("verify-platform-health.sh", ["--env", "uat", "--preflight"]),
        ("verify-platform-health.sh", ["--env", "uat", "--smoke-test"]),
    )

    def test_sentinel_marker_is_never_created_and_exit_code_never_98(self):
        for wrapper, args in self.SENTINEL_COMMANDS:
            with self.subTest(wrapper=wrapper, args=args):
                result = self.run_wrapper(wrapper, args)
                self.assertFalse(
                    self.sentinel_marker.exists(),
                    f"sentinel fired for {wrapper} {args}: "
                    f"stdout={result.stdout!r} stderr={result.stderr!r}",
                )
                self.assertNotEqual(result.returncode, 98)
                if self.sentinel_marker.exists():
                    self.sentinel_marker.unlink()

    def test_fixture_self_check_non_env_routing_still_reaches_the_sentinel(self):
        # Proves this sentinel technique is capable of catching a real
        # routing leak (i.e. it is not silently inert): the same wrapper's
        # *non*-`--env` branch genuinely execs scripts/legacy/dev/*.sh.
        result = self.run_wrapper("provision.sh", ["mongodb"])
        self.assertTrue(self.sentinel_marker.exists())
        self.assertEqual(result.returncode, 98)


# ---------------------------------------------------------------------------
# Requirement 3: explicit parser rejection.
# ---------------------------------------------------------------------------


class ExplicitParserRejectionTests(OrchestratorFixture):
    """INVALID_EXPLICIT_FORMS (Task 4 Step 2, verbatim) against provision
    and destroy. verify is intentionally excluded: form 5, `("--env",
    "uat")`, is "no scope" for provision/destroy, but verify takes no scope
    argument at all, so it is not a meaningful rejection case for verify
    (it is simply a valid, mode-defaulting verify invocation)."""

    def test_invalid_forms_fail_and_never_create_the_local_state_directory(self):
        for operation in ("provision", "destroy"):
            for form in INVALID_EXPLICIT_FORMS:
                with self.subTest(operation=operation, form=form):
                    self.reset_command_log()
                    result = self.run_unified(operation, list(form))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(self.local_dir_exists())

    def test_invalid_forms_invoke_no_child_command_except_the_documented_uat_scope_case(self):
        # ("--env", "uat", "unknown") is exempted here: orchestrator.sh runs
        # `verify_aws_identity_and_region` before `resolve_provision_order`/
        # `resolve_destroy_order`, so this syntactically well-formed single-
        # scope invocation genuinely reaches a real (mocked) `aws` call
        # before the unknown-scope error would be produced. See this file's
        # module docstring for the full reasoning.
        exempt_form = ("--env", "uat", "unknown")
        for operation in ("provision", "destroy"):
            for form in INVALID_EXPLICIT_FORMS:
                if form == exempt_form:
                    continue
                with self.subTest(operation=operation, form=form):
                    self.reset_command_log()
                    result = self.run_unified(operation, list(form))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.command_log_lines(), [])

    def test_the_exempted_uat_scope_case_still_fails_and_creates_no_local_dir(self):
        for operation in ("provision", "destroy"):
            with self.subTest(operation=operation):
                self.reset_command_log()
                result = self.run_unified(operation, ["--env", "uat", "unknown"])
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.local_dir_exists())


# ---------------------------------------------------------------------------
# Requirement 4: dev mutation always blocked.
# ---------------------------------------------------------------------------


class DevMutationAlwaysBlockedTests(OrchestratorFixture):
    """config/environments/dev.env sets PROMOTION_MODE=modeled, which
    unconditionally blocks unified dev mutation regardless of scope or
    options."""

    SCOPES = ("mongodb", "postgresql-core", "eks-platform", "backend", "all")
    BLOCK_MESSAGE = "ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled"

    def test_provision_dev_is_always_blocked(self):
        for scope in self.SCOPES:
            with self.subTest(scope=scope):
                self.reset_command_log()
                result = self.run_unified("provision", ["--env", "dev", scope])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(self.BLOCK_MESSAGE, result.stderr)
                self.assertEqual(self.command_log_lines(), [])
                self.assertFalse(self.local_dir_exists())

    def test_destroy_dev_is_always_blocked(self):
        for scope in self.SCOPES:
            with self.subTest(scope=scope):
                self.reset_command_log()
                result = self.run_unified("destroy", ["--env", "dev", scope])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(self.BLOCK_MESSAGE, result.stderr)
                self.assertEqual(self.command_log_lines(), [])
                self.assertFalse(self.local_dir_exists())

    def test_provision_dev_with_auto_approve_is_still_blocked(self):
        result = self.run_unified("provision", ["--env", "dev", "mongodb", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(self.BLOCK_MESSAGE, result.stderr)
        self.assertEqual(self.command_log_lines(), [])

    def test_destroy_dev_with_auto_approve_is_still_blocked(self):
        result = self.run_unified("destroy", ["--env", "dev", "mongodb", "--auto-approve"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(self.BLOCK_MESSAGE, result.stderr)
        self.assertEqual(self.command_log_lines(), [])


# ---------------------------------------------------------------------------
# Requirement 5: unified verification mode acceptance.
# ---------------------------------------------------------------------------


class VerificationModeAcceptanceTests(OrchestratorFixture):
    """`--preflight`, `--full`, no flag (defaults to full), and
    `--smoke-test` are the only four accepted forms; every other flag is
    rejected before any verifier slot runs."""

    def test_the_four_accepted_forms_all_reach_the_foundation_contract_slot(self):
        # "PASS: foundation-contract (environment loaded and validated)" is
        # printed unconditionally as the first slot of every mode, with no
        # external command involved -- a reliable signal that the command
        # was accepted and actually started executing verification slots,
        # independent of whatever the mocked aws/kubectl calls later do.
        for mode_args in ([], ["--preflight"], ["--full"], ["--smoke-test"]):
            with self.subTest(mode_args=mode_args):
                result = self.run_unified("verify", ["--env", "uat"] + mode_args)
                self.assertIn("PASS: foundation-contract", result.stdout)
                self.assertNotIn("unknown unified verification argument", result.stderr)
                self.assertNotIn("unified verification accepts only one mode flag", result.stderr)
                self.assertNotIn(
                    "unified verification does not accept legacy-only option", result.stderr
                )

    def test_legacy_only_flags_are_rejected(self):
        for flag in ("--bootstrap-platform-controllers", "--keep-signoz-namespace"):
            with self.subTest(flag=flag):
                self.reset_command_log()
                result = self.run_unified("verify", ["--env", "uat", flag])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    f"unified verification does not accept legacy-only option: {flag}",
                    result.stderr,
                )
                self.assertNotIn("PASS: foundation-contract", result.stdout)
                self.assertEqual(self.command_log_lines(), [])

    def test_unknown_flag_is_rejected(self):
        result = self.run_unified("verify", ["--env", "uat", "--bogus"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown unified verification argument: --bogus", result.stderr)
        self.assertNotIn("PASS: foundation-contract", result.stdout)

    def test_repeated_mode_flag_is_rejected(self):
        result = self.run_unified("verify", ["--env", "uat", "--preflight", "--full"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unified verification accepts only one mode flag", result.stderr)
        self.assertNotIn("PASS: foundation-contract", result.stdout)


# ---------------------------------------------------------------------------
# Requirement 6: destroy option grammar.
# ---------------------------------------------------------------------------


class DestroyOptionGrammarTests(OrchestratorFixture):
    """Uses `--env dev` throughout. Reading orchestrator.sh shows the
    option-parsing loop runs before `require_environment_mutation_
    authorized`, so a rejected option always fails with its own specific
    message and zero side effects regardless of environment; a
    *syntactically accepted* option combination reaches (and is stopped by)
    the dev-mutation gate before any command, artifact, or dispatch --
    which is exactly the "before any external command, artifact creation,
    or dispatch" property this requirement asks for, without needing any
    AWS/backend mocking."""

    BLOCK_MESSAGE = "unified dev mutation is blocked"

    def _assert_no_side_effects(self):
        self.assertEqual(self.command_log_lines(), [])
        self.assertFalse(self.local_dir_exists())

    # --- accepted grammar -------------------------------------------------

    def test_auto_approve_alone_is_accepted(self):
        result = self.run_unified("destroy", ["--env", "dev", "mongodb", "--auto-approve"])
        self.assertIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_single_confirmation_artifact_is_accepted(self):
        result = self.run_unified(
            "destroy",
            [
                "--env", "dev", "mongodb", "--confirmation-artifact",
                ".local/dev/generated/destroy-confirmation.abc123.json",
            ],
        )
        self.assertIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_repeated_confirm_with_distinct_values_is_accepted(self):
        result = self.run_unified(
            "destroy",
            [
                "--env", "dev", "mongodb",
                "--confirm", "destroy:dev:815402439714:mongodb:psmdb/mongodb/oms:value-a",
                "--confirm", "destroy:dev:815402439714:mongodb:psmdb/mongodb/oms:value-b",
            ],
        )
        self.assertIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    # --- rejected grammar ---------------------------------------------------

    def test_missing_confirmation_artifact_value_is_rejected(self):
        result = self.run_unified(
            "destroy", ["--env", "dev", "mongodb", "--confirmation-artifact"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--confirmation-artifact requires a value", result.stderr)
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_duplicate_confirmation_artifact_option_is_rejected(self):
        result = self.run_unified(
            "destroy",
            [
                "--env", "dev", "mongodb",
                "--confirmation-artifact", "a.json",
                "--confirmation-artifact", "b.json",
            ],
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--confirmation-artifact may be given at most once", result.stderr)
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_confirmation_artifact_equals_form_is_rejected(self):
        result = self.run_unified(
            "destroy", ["--env", "dev", "mongodb", "--confirmation-artifact=a.json"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "--confirmation-artifact must be given as two separate arguments, "
            "not --confirmation-artifact=<path>",
            result.stderr,
        )
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_artifact_options_are_rejected_on_provision(self):
        result = self.run_unified(
            "provision", ["--env", "dev", "mongodb", "--confirmation-artifact", "a.json"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "unknown unified provision argument: --confirmation-artifact", result.stderr
        )
        self._assert_no_side_effects()

    def test_confirm_option_is_rejected_on_provision(self):
        result = self.run_unified("provision", ["--env", "dev", "mongodb", "--confirm", "x"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown unified provision argument: --confirm", result.stderr)
        self._assert_no_side_effects()

    def test_artifact_options_are_rejected_on_verify(self):
        result = self.run_unified(
            "verify", ["--env", "dev", "--confirmation-artifact", "a.json"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "unknown unified verification argument: --confirmation-artifact", result.stderr
        )
        self._assert_no_side_effects()

    def test_confirm_option_is_rejected_on_verify(self):
        result = self.run_unified("verify", ["--env", "dev", "--confirm", "x"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown unified verification argument: --confirm", result.stderr)
        self._assert_no_side_effects()

    def test_duplicate_confirmation_values_are_rejected(self):
        value = "destroy:dev:815402439714:mongodb:psmdb/mongodb/oms:delete-cluster-and-pvcs"
        result = self.run_unified(
            "destroy",
            ["--env", "dev", "mongodb", "--confirm", value, "--confirm", value],
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"duplicate --confirm value: {value}", result.stderr)
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_confirm_missing_value_is_rejected(self):
        result = self.run_unified("destroy", ["--env", "dev", "mongodb", "--confirm"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--confirm requires a value", result.stderr)
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()

    def test_unknown_destroy_option_is_rejected(self):
        result = self.run_unified("destroy", ["--env", "dev", "mongodb", "--bogus"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown unified destroy argument: --bogus", result.stderr)
        self.assertNotIn(self.BLOCK_MESSAGE, result.stderr)
        self._assert_no_side_effects()


if __name__ == "__main__":
    unittest.main()
