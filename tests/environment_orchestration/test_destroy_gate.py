"""Tests for the single-pass interactive typed-yes destroy gate in
`scripts/lib/orchestrator.sh` (`_orchestrator_destroy_single_pass` and
`_orchestrator_prompt_typed_yes`), which replaced the two-pass copy-paste
confirmation-artifact protocol.

Four properties are load-bearing and each has its own class here:

  1. DRAIN. Input already buffered on the terminal when the prompt is
     reached is discarded, so a pasted multi-line block

         scripts/destroy.sh --env prod eks-platform
         yes

     cannot answer a prompt the human never saw. This is THE reason the
     gate exists in this shape, so it is tested against a real pty with
     the answer written before the destroy has finished drawing its
     resource list (DrainBeforeReadTests).

  2. NO TTY -> FAIL CLOSED. Under CI / nohup / a pipeline the gate cannot
     be shown, so the destroy refuses with an explicit message. It never
     hangs on a read and never proceeds unconfirmed
     (NoTtyFailsClosedTests).

  3. Only the exact word `yes` proceeds; anything else aborts before
     dispatch (TypedAnswerTests).

  4. --auto-approve does NOT skip the gate, in any environment
     (AutoApproveDoesNotSkipTheGateTests).

The pty-driven tests drive `_orchestrator_prompt_typed_yes` directly rather
than a full `run_unified_command destroy`: the function is the entire
drain-and-read seam, and isolating it lets the test control exactly when
the "pasted" bytes arrive relative to the prompt, which is the whole point.
The full-command tests (2 and 4) go through `run_unified_command`.
"""

import os
import pty
import select
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from .helpers import REPO_ROOT

FOUNDATION_FILES = (
    "scripts/lib/orchestrator.sh",
    "scripts/lib/terraform-destroy-scope.sh",
    "scripts/lib/environment-contracts.sh",
    "scripts/lib/platform-env.sh",
    "scripts/lib/platform-guards.sh",
    "scripts/lib/orchestration-paths.sh",
    "scripts/lib/scope-registry.sh",
    "scripts/lib/enumerate-destroy-resources.sh",
    "scripts/lib/destroy-evidence.py",
    "config/environment-schema/base.manifest",
    "config/environments/dev.env",
    "config/environments/uat.env",
)

MOCK_AWS = """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
  printf '%s\\n' "${MOCK_AWS_ACCOUNT_ID:-672172129937}"
  exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ]; then
  printf '%s\\n' "${MOCK_AWS_CONFIGURED_REGION:-ap-east-1}"
  exit 0
fi
printf 'unhandled mock aws invocation: %s\\n' "$*" >&2
exit 1
"""


class _GateFixture(unittest.TestCase):
    """A clean repository copy with just the foundation files, plus a mock
    `aws`. Follows the standalone-fixture precedent in this package (see
    test_guards_and_paths.py) rather than reusing RepositoryFixture, because
    orchestrator.sh rejects a long list of inherited environment variables."""

    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name).resolve() / "repository"
        self.mock_bin = Path(self._temporary.name) / "bin"
        self.command_log = Path(self._temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)

        aws_path = self.mock_bin / "aws"
        aws_path.write_text(MOCK_AWS, encoding="ascii")
        aws_path.chmod(aws_path.stat().st_mode | stat.S_IXUSR)

        for relative in FOUNDATION_FILES:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO_ROOT / relative, destination)

        python3_path = shutil.which("python3")
        self.assertIsNotNone(python3_path)
        self.clean_path = f"{self.mock_bin}:{Path(python3_path).parent}:/usr/bin:/bin"

    def tearDown(self):
        self._temporary.cleanup()

    def environment(self, **extra):
        env = {
            "PATH": self.clean_path,
            "MOCK_COMMAND_LOG": str(self.command_log),
            "MOCK_AWS_ACCOUNT_ID": "672172129937",
            "MOCK_AWS_CONFIGURED_REGION": "ap-east-1",
            "ORCHESTRATOR_TEST_CLOCK_EPOCH": "1800000000",
            "ORCHESTRATOR_TEST_OPERATION_ID": "a" * 16,
        }
        env.update(extra)
        return env

    def run_script(self, script, env_extra=None, **kwargs):
        return subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env=self.environment(**(env_extra or {})),
            text=True,
            capture_output=True,
            **kwargs,
        )

    def run_on_pty(self, script, writes, timeout=25.0):
        """Runs `script` under a real controlling terminal and performs
        `writes` -- a sequence of (delay_seconds, bytes) pairs -- against
        the master side. Returns the accumulated terminal output."""
        pid, fd = pty.fork()
        if pid == 0:  # pragma: no cover - child process
            os.chdir(str(self.root))
            os.environ.clear()
            os.environ.update(self.environment())
            os.execv("/bin/bash", ["/bin/bash", "-c", script])

        pending = list(writes)
        started = time.time()
        output = b""
        try:
            while time.time() - started < timeout:
                now = time.time() - started
                while pending and pending[0][0] <= now:
                    os.write(fd, pending.pop(0)[1])
                readable, _, _ = select.select([fd], [], [], 0.1)
                if readable:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                if b"__SCRIPT_DONE__" in output:
                    break
            return output.decode("utf-8", errors="replace")
        finally:
            os.close(fd)
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass


# ---------------------------------------------------------------------------
# Property 1: the drain.
# ---------------------------------------------------------------------------


class DrainBeforeReadTests(_GateFixture):
    # The prompt is preceded by a deliberate delay standing in for the time
    # the real gate spends enumerating resources and running guards. The
    # "pasted" answer is written immediately, i.e. long before the prompt
    # appears -- exactly the multi-line-paste scenario.
    PASTE_SCRIPT = (
        "source scripts/lib/orchestrator.sh\n"
        "sleep 2\n"
        "if _orchestrator_prompt_typed_yes 'PROMPT: '; then\n"
        "  printf 'GATE=accepted\\n'\n"
        "else\n"
        "  printf 'GATE=rejected\\n'\n"
        "fi\n"
        "printf '__SCRIPT_DONE__\\n'\n"
    )

    def test_a_yes_pasted_before_the_prompt_is_discarded_and_does_not_answer_it(self):
        output = self.run_on_pty(
            self.PASTE_SCRIPT,
            writes=[(0.0, b"yes\n")],
            timeout=20.0,
        )

        self.assertIn("PROMPT:", output)
        # The buffered "yes" was drained, so nothing answered the prompt and
        # the read is still waiting when the test's timeout expires. The
        # gate must NOT have reported acceptance.
        self.assertNotIn("GATE=accepted", output)

    def test_a_yes_pasted_without_a_trailing_newline_is_discarded(self):
        """The regression that defeated the first implementation (#159).

        `read` consumes COMPLETED LINES ONLY. A pasted block whose last line
        has no trailing newline leaves that partial line in the terminal
        line-discipline buffer, where a line-based drain cannot see or
        discard it -- `read -t` simply times out. It is then prepended to
        the next read, so the operator merely pressing Enter submits the
        pre-pasted `yes` and approves a destroy whose resource list they
        never saw.

        Reproduced against the real function on bash 3.2.57 before the fix:

            paste b"cmd\nyes"   (no trailing newline)
            press Enter
            -> GATE=accepted

        Every other drain test here ends its payload with "\n", which is
        exactly why this shape went unnoticed. The fix flushes the terminal
        input queue (termios.TCIFLUSH) in the same process that performs the
        read, immediately before reading.
        """
        # Timing matters: the partial line must be buffered BEFORE the
        # drain runs, and the Enter that completes it must arrive AFTER the
        # prompt is drawn. PASTE_SCRIPT sleeps 2s before prompting, so the
        # paste lands at t=0 (pre-drain) and Enter at t=4 (post-prompt).
        # Writing Enter too early would let it be consumed by the drain
        # itself and the test would pass for the wrong reason.
        output = self.run_on_pty(
            self.PASTE_SCRIPT,
            writes=[(0.0, b"scripts/destroy.sh --env prod eks-platform\nyes"),
                    (4.0, b"\n")],
            timeout=25.0,
        )

        self.assertIn("PROMPT:", output)
        self.assertNotIn("GATE=accepted", output)

    def test_a_yes_typed_after_the_prompt_is_accepted(self):
        output = self.run_on_pty(
            self.PASTE_SCRIPT,
            writes=[(4.0, b"yes\n")],
            timeout=20.0,
        )

        self.assertIn("PROMPT:", output)
        self.assertIn("GATE=accepted", output)

    def test_a_multi_line_paste_is_fully_drained_not_merely_one_line(self):
        output = self.run_on_pty(
            self.PASTE_SCRIPT,
            writes=[(0.0, b"yes\nyes\nyes\n")],
            timeout=20.0,
        )

        self.assertIn("PROMPT:", output)
        self.assertNotIn("GATE=accepted", output)

    def test_a_no_typed_after_the_prompt_is_rejected(self):
        output = self.run_on_pty(
            self.PASTE_SCRIPT,
            writes=[(4.0, b"no\n")],
            timeout=20.0,
        )

        self.assertIn("GATE=rejected", output)


# ---------------------------------------------------------------------------
# Property 3: exact-word matching.
# ---------------------------------------------------------------------------


class TypedAnswerTests(_GateFixture):
    SCRIPT = (
        "source scripts/lib/orchestrator.sh\n"
        "sleep 1\n"
        "if _orchestrator_prompt_typed_yes 'PROMPT: '; then\n"
        "  printf 'GATE=accepted\\n'\n"
        "else\n"
        "  printf 'GATE=rejected\\n'\n"
        "fi\n"
        "printf '__SCRIPT_DONE__\\n'\n"
    )

    def _answer(self, text):
        return self.run_on_pty(self.SCRIPT, writes=[(3.0, text)], timeout=18.0)

    def test_only_the_exact_word_yes_is_accepted(self):
        self.assertIn("GATE=accepted", self._answer(b"yes\n"))

    def test_uppercase_yes_is_rejected(self):
        self.assertIn("GATE=rejected", self._answer(b"YES\n"))

    def test_y_is_rejected(self):
        self.assertIn("GATE=rejected", self._answer(b"y\n"))

    def test_an_empty_answer_is_rejected(self):
        self.assertIn("GATE=rejected", self._answer(b"\n"))


# ---------------------------------------------------------------------------
# Property 2: no controlling terminal -> fail closed, never hang.
# ---------------------------------------------------------------------------


class NoTtyFailsClosedTests(_GateFixture):
    def test_the_prompt_helper_fails_closed_without_a_controlling_terminal(self):
        result = self.run_script(
            "source scripts/lib/orchestrator.sh\n"
            "setsid_missing=0\n"
            "if _orchestrator_prompt_typed_yes 'PROMPT: '; then\n"
            "  printf 'GATE=accepted\\n'\n"
            "else\n"
            "  printf 'GATE=rejected\\n'\n"
            "fi\n",
            stdin=subprocess.DEVNULL,
            timeout=30,
        )

        # subprocess.run with capture_output and no pty gives the child no
        # controlling terminal it can open for reading in this harness.
        self.assertIn("GATE=rejected", result.stdout)
        self.assertNotIn("GATE=accepted", result.stdout)

    def test_a_full_destroy_without_a_terminal_refuses_rather_than_hanging(self):
        result = self.run_script(
            "source scripts/lib/orchestrator.sh\n"
            "scope_registry_pre_destroy_guard_eks_platform() {\n"
            "  record_pre_destroy_guard_result eks-platform PASS RESOURCE "
            "sha256:" + ("0" * 64) + " SCOPE_GUARD_PASSED\n"
            "}\n"
            "scope_registry_deferred_eks_platform_destroy() {\n"
            "  printf 'HANDLER_RAN\\n'\n"
            "}\n"
            "run_unified_command destroy --env uat eks-platform\n",
            stdin=subprocess.DEVNULL,
            timeout=60,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("HANDLER_RAN", result.stdout)
        combined = result.stdout + result.stderr
        self.assertTrue(
            "typed-yes destroy gate" in combined
            or "destroy approval was not given" in combined
            or "enumerate the resources" in combined,
            combined,
        )


# ---------------------------------------------------------------------------
# Property 4: --auto-approve does not skip the gate.
# ---------------------------------------------------------------------------


class AutoApproveDoesNotSkipTheGateTests(_GateFixture):
    """`--auto-approve` retains only its downstream meaning
    (UNIFIED_AUTO_APPROVE: do not prompt again inside handlers/Terraform).
    It must not bypass the typed-yes gate in ANY environment -- the reason
    the gate exists (a human sees the real resource list) is identical in
    dev, uat and prod, and a per-environment exemption would make one code
    path behave differently per environment."""

    def _run_auto_approve_destroy_without_a_terminal(self, environment_name):
        return self.run_script(
            "source scripts/lib/orchestrator.sh\n"
            "scope_registry_pre_destroy_guard_eks_platform() {\n"
            "  record_pre_destroy_guard_result eks-platform PASS RESOURCE "
            "sha256:" + ("0" * 64) + " SCOPE_GUARD_PASSED\n"
            "}\n"
            "scope_registry_deferred_eks_platform_destroy() {\n"
            "  printf 'HANDLER_RAN\\n'\n"
            "}\n"
            f"run_unified_command destroy --env {environment_name} eks-platform --auto-approve\n",
            stdin=subprocess.DEVNULL,
            timeout=60,
        )

    def test_auto_approve_does_not_dispatch_handlers_without_a_typed_yes_in_uat(self):
        result = self._run_auto_approve_destroy_without_a_terminal("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("HANDLER_RAN", result.stdout)

    def test_the_orchestrator_source_never_skips_the_gate_on_auto_approve(self):
        """A structural assertion, because the behavioural one above can
        only be observed where a terminal is absent: the gate call site
        must not be guarded by an auto_approve condition at all."""
        source = (REPO_ROOT / "scripts/lib/orchestrator.sh").read_text(encoding="utf-8")
        gate_call = source.index("_orchestrator_prompt_typed_yes \\")
        preceding = source[max(0, gate_call - 600):gate_call]
        self.assertNotIn("auto_approve", preceding)


# ---------------------------------------------------------------------------
# End to end: the whole single pass over a real terminal.
# ---------------------------------------------------------------------------


class EndToEndSinglePassTests(_GateFixture):
    GUARD_AND_HANDLER = (
        "scope_registry_pre_destroy_guard_eks_platform() {\n"
        "  record_pre_destroy_guard_result eks-platform PASS RES sha256:"
        + ("0" * 64)
        + " SCOPE_GUARD_PASSED\n"
        "}\n"
        "scope_registry_deferred_eks_platform_destroy() { printf 'HANDLER_RAN\\n'; }\n"
    )

    def _destroy_script(self, extra_args=""):
        return (
            "source scripts/lib/orchestrator.sh\n"
            + self.GUARD_AND_HANDLER
            + f"run_unified_command destroy --env uat eks-platform {extra_args}\n"
            "printf 'RC=%s\\n' \"$?\"\n"
            "printf '__SCRIPT_DONE__\\n'\n"
        )

    def test_typing_yes_prints_the_list_dispatches_and_records_the_full_evidence_trail(self):
        output = self.run_on_pty(
            self._destroy_script(), writes=[(6.0, b"yes\n")], timeout=40.0
        )

        self.assertIn("DESTROY PREVIEW: eks-platform", output)
        self.assertIn("Type the exact word yes to destroy eks-platform in uat", output)
        self.assertIn("HANDLER_RAN", output)
        self.assertIn("RC=0", output)

        evidence_dir = self.root / ".local" / "uat" / "evidence"
        names = sorted(path.name for path in evidence_dir.iterdir())
        operation_id = "a" * 16
        self.assertIn(f"pre-destroy-guards.{operation_id}.json", names)
        self.assertIn(f"pre-destroy-guards.{operation_id}.status.consumed.json", names)
        self.assertIn(f"pre-destroy-guards.{operation_id}.status.success.json", names)

    def test_the_resource_list_is_printed_before_the_prompt_not_after(self):
        output = self.run_on_pty(
            self._destroy_script(), writes=[(6.0, b"yes\n")], timeout=40.0
        )

        self.assertLess(
            output.index("DESTROY PREVIEW"),
            output.index("Type the exact word yes"),
        )

    def test_answering_no_aborts_before_dispatch_and_records_no_terminal_status(self):
        output = self.run_on_pty(
            self._destroy_script(), writes=[(6.0, b"no\n")], timeout=40.0
        )

        self.assertIn("destroy approval was not given", output)
        self.assertNotIn("HANDLER_RAN", output)
        self.assertNotIn("RC=0", output)

        evidence_dir = self.root / ".local" / "uat" / "evidence"
        names = sorted(path.name for path in evidence_dir.iterdir())
        operation_id = "a" * 16
        # The all-pass guard record still exists (the guards did run and
        # pass, and that observation is part of the audit trail), but
        # nothing was consumed and no terminal status was written.
        self.assertIn(f"pre-destroy-guards.{operation_id}.json", names)
        self.assertNotIn(f"pre-destroy-guards.{operation_id}.status.consumed.json", names)
        self.assertNotIn(f"pre-destroy-guards.{operation_id}.status.success.json", names)


class EnumerationFailsClosedTests(_GateFixture):
    def test_a_failing_enumerator_aborts_before_the_prompt_with_no_fallback_list(self):
        """Enumeration failure must never degrade to a static or
        "plausible" list -- showing a confident fiction at the moment a
        human decides whether to destroy production is the failure #163
        removed. It must abort before any prompt or dispatch."""
        result = self.run_script(
            "source scripts/lib/orchestrator.sh\n"
            "scope_registry_pre_destroy_guard_eks_platform() {\n"
            "  record_pre_destroy_guard_result eks-platform PASS RES sha256:"
            + ("0" * 64)
            + " SCOPE_GUARD_PASSED\n"
            "}\n"
            "scope_registry_deferred_eks_platform_destroy() { printf 'HANDLER_RAN\\n'; }\n"
            "enumerate_destroy_resources_for_scope() { return 1; }\n"
            "_orchestrator_render_destroy_enumeration() {\n"
            "  _orchestrator_error 'resource enumeration failed for scope: eks-platform'\n"
            "  return 1\n"
            "}\n"
            "run_unified_command destroy --env uat eks-platform\n",
            stdin=subprocess.DEVNULL,
            timeout=60,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("HANDLER_RAN", result.stdout)
        self.assertIn("unable to enumerate the resources", result.stderr)
        self.assertNotIn("Type the exact word yes", result.stdout)


if __name__ == "__main__":
    unittest.main()
