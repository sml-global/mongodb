"""Tests for `scripts/lib/destroy-evidence.py`, the foundation-only,
standard-library-only Python module that implements the durable destroy
evidence record, and for the parts of `scripts/lib/orchestrator.sh` that
drive it.

The former companion module `scripts/lib/confirmation-artifact.py` and the
two-pass copy-paste confirmation-artifact protocol it implemented are gone:
destroy is now a single interactive pass that enumerates the real resources,
runs the read-only pre-destroy guards, writes this evidence record, and then
requires the operator to type `yes` on /dev/tty. Areas 2, 3, 6 and 10 below
tested only that removed protocol and were deleted with it; the evidence
trail (areas 1, 4, 5, 7, 8) and the guard callback contract (area 9) are
unchanged and still covered here. The single-pass gate itself is covered by
tests/environment_orchestration/test_destroy_gate.py.

This file covers these 10 areas (see
docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md,
Task 4 Step 5, from line 1072 onward, for the exact schema/safety
requirements each test below maps to):

  1. Canonical JSON bytes                  -> CanonicalBytesAndDuplicateKeyRejectionTests
  4. Guard-failure record schema/safety    -> GuardFailureRecordSchemaAndSafetyTests
  5. All-pass evidence schema/safety       -> AllPassEvidenceSchemaAndSafetyTests
  7. Status lifecycle                      -> StatusLifecycleTests
  8. Retention / cleanup eligibility       -> RetentionAndCleanupEligibilityTests
  9. Five-argument guard callback contract -> GuardCallbackContractTests

Area 9 additionally sources scripts/lib/orchestrator.sh (and its 5
declared foundation dependencies) into real bash subprocesses, following the
same from-scratch-clean-environment, no-RepositoryFixture-reuse pattern
established by tests/environment_orchestration/test_guards_and_paths.py's
`GuardsAndPathsFixture` and tests/environment_orchestration/
test_entrypoints.py's `OrchestratorFixture` -- see `_OrchestratorGuardCallbackFixture`
below for the exact technique
(sourcing, then redefining one real registry-mapped guard/handler function
name per test, exactly as bash's ordinary function-redefinition semantics
allow).

Judgment calls made while writing this file (also flagged in the final chat
report):

  * Both modules are loaded directly via `importlib.util` from their exact
    hyphenated file paths (they are never imported as packages -- the plan
    describes them as CLI-only files invoked by `orchestrator.sh`) and
    exercised as ordinary Python libraries rather than exclusively through
    their `argparse` CLI. This gives precise, direct assertions on raised
    exception types/messages and on raw bytes/mode/exclusivity, which is not
    practical to obtain reliably through subprocess exit codes and stderr
    text alone. The exact CLI subcommands (`create`, `fields`, `validate`,
    `consume`, `cleanup` for confirmation-artifact.py; `write-evidence`,
    `write-guard-failure`, `write-status`, `cleanup`, `digest` for
    destroy-evidence.py) were read in full from each file's `main()` before
    writing this file, confirming no subprocess-based test here relies on a
    guessed subcommand or flag name.
  * Does not subclass tests/environment_orchestration/helpers.py's
    `RepositoryFixture` -- areas 1-8 only exercise in-process Python function
    calls with no bash subprocess involved, reusing only that fixture's
    established `.resolve()`-on-a-`tempfile.TemporaryDirectory` pattern
    (documented lesson: macOS resolves `/var` -> `/private/var`, and
    unresolved paths can cause spurious mismatches) via a small local
    `_TempDirFixture`. Areas 9 and 10 do drive real bash subprocesses (see
    above), but via two new from-scratch fixtures local to this file rather
    than by importing `RepositoryFixture` or `test_entrypoints.py`'s
    `OrchestratorFixture`.

Nothing in this file was executed while writing it (no python, no
`bash -n`, no git, no test runs) -- only read_file and
replace_string_in_file/create_file were used, per the explicit instruction
that a human will authorize test execution separately.
"""

import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[2]
DESTROY_EVIDENCE_PATH = REPO_ROOT / "scripts" / "lib" / "destroy-evidence.py"


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


destroy_evidence = _load_module("destroy_evidence_under_test", DESTROY_EVIDENCE_PATH)

# Fixed, arbitrary epoch (2027-01-14T17:20:00Z) used for every deterministic
# payload below so tests never depend on wall-clock time.
BASE_EPOCH = 1_800_000_000


def _write_raw_file(path, text, mode=0o600):
    """Write exact raw bytes to path (bypassing every module's own safe
    exclusive-create helpers) so tests can construct malformed/unsafe fixture
    files (wrong mode, duplicate keys, etc.) directly."""
    data = text.encode("ascii")
    fd = os.open(str(path), os.O_CREAT | os.O_WRONLY, mode)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    os.chmod(str(path), mode)


def _valid_guard_result(**overrides):
    result = {
        "scope": "eks-platform",
        "status": "PASS",
        "resource_identity": "EKS-boomi-runtime-cluster",
        "evidence_digest": "sha256:" + ("0" * 64),
        "summary_code": "CLUSTER_ABSENT",
    }
    result.update(overrides)
    return result


def _valid_failure_object(**overrides):
    failure = {
        "code": "GUARD_FAIL",
        "expected_scope": "eks-platform",
        "guard_index": 0,
        "result_index": 0,
        "wrapper_status": 0,
    }
    failure.update(overrides)
    return failure


def _valid_guard_failure_kwargs(**overrides):
    kwargs = dict(
        operation_id="a" * 16,
        environment="uat",
        account_id="672172129937",
        requested_scope="eks-platform",
        resolved_scopes=["eks-platform"],
        received_results=[_valid_guard_result()],
        failure=_valid_failure_object(),
        created_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        confirmation_artifact_sha256="0" * 64,
    )
    kwargs.update(overrides)
    return kwargs


def _valid_all_pass_kwargs(**overrides):
    kwargs = dict(
        operation_id="a" * 16,
        environment="uat",
        account_id="672172129937",
        requested_scope="eks-platform",
        resolved_scopes=["eks-platform"],
        guard_results=[_valid_guard_result()],
        created_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        expires_at=destroy_evidence.format_timestamp(BASE_EPOCH + 900),
        confirmation_artifact_sha256="0" * 64,
    )
    kwargs.update(overrides)
    return kwargs


class _TempDirFixture(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        # Resolve symlinks (e.g. macOS /var -> /private/var) so paths built
        # from self.root match paths this same process/library naturally
        # produces -- see helpers.py's RepositoryFixture for the same
        # established pattern.
        self.root = Path(self._temporary.name).resolve()

    def tearDown(self):
        self._temporary.cleanup()


# ---------------------------------------------------------------------------
# Area 1: Canonical JSON bytes.
# ---------------------------------------------------------------------------


class CanonicalBytesAndDuplicateKeyRejectionTests(_TempDirFixture):
    def test_destroy_evidence_canonical_bytes_are_sorted_compact_ascii_with_one_trailing_newline(self):
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        data = destroy_evidence.canonical_bytes(payload)
        text = data.decode("ascii")

        self.assertEqual(text.count("\n"), 1)
        self.assertTrue(text.endswith("\n"))
        body = text[:-1]
        self.assertEqual(body, json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True))
        self.assertNotIn(" ", body)

    def test_destroy_evidence_rejects_duplicate_keys_on_read(self):
        path = self.root / "dup-evidence.json"
        _write_raw_file(path, '{"a":1,"a":2}\n')

        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.read_evidence_document(path, kind="all-pass")
        self.assertIn("duplicate key", str(ctx.exception))

    def test_destroy_evidence_read_reserialize_round_trip_is_byte_identical(self):
        path = self.root / "evidence.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        written = destroy_evidence.write_all_pass_evidence(path, payload)

        read_payload, raw = destroy_evidence.read_evidence_document(path, kind="all-pass")

        self.assertEqual(raw, written)
        self.assertEqual(destroy_evidence.canonical_bytes(read_payload), written)


# ---------------------------------------------------------------------------
# Area 4: Guard-failure record schema/safety (destroy-evidence.py).
# ---------------------------------------------------------------------------


class GuardFailureRecordSchemaAndSafetyTests(_TempDirFixture):
    def test_guard_failure_payload_has_exact_keys(self):
        payload = destroy_evidence.build_guard_failure_payload(**_valid_guard_failure_kwargs())

        expected_keys = (
            "schema_version",
            "operation_id",
            "environment",
            "account_id",
            "requested_scope",
            "resolved_scopes",
            "received_results",
            "failure",
            "created_at",
            "confirmation_artifact_sha256",
        )
        self.assertEqual(set(destroy_evidence.GUARD_FAILURE_KEYS), set(expected_keys))
        self.assertEqual(set(payload.keys()), set(expected_keys))

    def test_write_guard_failure_mode_exactly_0600(self):
        path = self.root / "destroy-guard-failure.json"
        payload = destroy_evidence.build_guard_failure_payload(**_valid_guard_failure_kwargs())
        destroy_evidence.write_guard_failure(path, payload)

        mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(mode, 0o600)

    def test_write_guard_failure_exclusive_creation_fails_if_exists(self):
        path = self.root / "destroy-guard-failure.json"
        payload = destroy_evidence.build_guard_failure_payload(**_valid_guard_failure_kwargs())
        destroy_evidence.write_guard_failure(path, payload)

        with self.assertRaises(FileExistsError):
            destroy_evidence.write_guard_failure(path, payload)

    def test_validate_guard_failure_schema_rejects_unknown_or_missing_key(self):
        payload = destroy_evidence.build_guard_failure_payload(**_valid_guard_failure_kwargs())

        with_extra = dict(payload)
        with_extra["unexpected_extra_field"] = "x"
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.validate_guard_failure_schema(with_extra)
        self.assertIn("key set mismatch", str(ctx.exception))

        missing_key = dict(payload)
        del missing_key["failure"]
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.validate_guard_failure_schema(missing_key)
        self.assertIn("key set mismatch", str(ctx.exception))


# ---------------------------------------------------------------------------
# Area 5: All-pass evidence schema/safety (destroy-evidence.py).
# ---------------------------------------------------------------------------


class AllPassEvidenceSchemaAndSafetyTests(_TempDirFixture):
    def test_all_pass_evidence_payload_has_exact_keys(self):
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())

        expected_keys = (
            "schema_version",
            "operation_id",
            "environment",
            "account_id",
            "requested_scope",
            "resolved_scopes",
            "guard_results",
            "created_at",
            "expires_at",
            "confirmation_artifact_sha256",
        )
        self.assertEqual(set(destroy_evidence.EVIDENCE_KEYS), set(expected_keys))
        self.assertEqual(set(payload.keys()), set(expected_keys))

    def test_confirmation_artifact_sha256_field_carries_the_gate_context_digest(self):
        """The field keeps its schema name but now holds the digest of the
        exact gate context the operator was shown (environment, account,
        scopes, operation id, created_at, and the rendered resource
        listing) rather than a digest of a separate artifact file, which no
        longer exists. It is still required to be a real 64-hex SHA-256."""
        gate_context = (
            "gate\nenvironment=uat\naccount=672172129937\nrequested_scope=eks-platform\n"
            "operation_id=aaaaaaaaaaaaaaaa\ncreated_at="
            + destroy_evidence.format_timestamp(BASE_EPOCH)
            + "\nresolved_scopes=eks-platform,\n  aws_eks_cluster  module.eks.aws_eks_cluster.this\n"
        )
        expected_digest = hashlib.sha256(gate_context.encode("utf-8")).hexdigest()

        evidence_payload = destroy_evidence.build_all_pass_evidence_payload(
            **_valid_all_pass_kwargs(confirmation_artifact_sha256=expected_digest)
        )

        self.assertEqual(evidence_payload["confirmation_artifact_sha256"], expected_digest)

    def test_all_pass_evidence_rejects_a_non_sha256_gate_digest(self):
        with self.assertRaises(destroy_evidence.DestroyEvidenceError):
            destroy_evidence.build_all_pass_evidence_payload(
                **_valid_all_pass_kwargs(confirmation_artifact_sha256="not-a-digest")
            )

    def test_write_all_pass_evidence_mode_exactly_0600(self):
        path = self.root / "pre-destroy-guards.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        destroy_evidence.write_all_pass_evidence(path, payload)

        mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(mode, 0o600)

    def test_write_all_pass_evidence_exclusive_creation_fails_if_exists(self):
        path = self.root / "pre-destroy-guards.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        destroy_evidence.write_all_pass_evidence(path, payload)

        with self.assertRaises(FileExistsError):
            destroy_evidence.write_all_pass_evidence(path, payload)

    def test_validate_all_pass_evidence_schema_rejects_unknown_or_missing_key(self):
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())

        with_extra = dict(payload)
        with_extra["unexpected_extra_field"] = "x"
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.validate_all_pass_evidence_schema(with_extra)
        self.assertIn("key set mismatch", str(ctx.exception))

        missing_key = dict(payload)
        del missing_key["guard_results"]
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.validate_all_pass_evidence_schema(missing_key)
        self.assertIn("key set mismatch", str(ctx.exception))


# ---------------------------------------------------------------------------
# Area 7: Status lifecycle (append-only consumed/success/failure sidecars).
# ---------------------------------------------------------------------------


class StatusLifecycleTests(_TempDirFixture):
    def _write_evidence(self):
        path = self.root / "pre-destroy-guards.aaaaaaaaaaaaaaaa.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        destroy_evidence.write_all_pass_evidence(path, payload)
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def test_writing_success_after_consumed_never_deletes_or_replaces_the_consumed_sidecar(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)

        consumed_path = destroy_evidence.write_status_sidecar(
            self.root, "a" * 16, "consumed", evidence_sha256=evidence_sha256, recorded_at=recorded_at
        )
        consumed_bytes_before = Path(consumed_path).read_bytes()

        success_recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH + 60)
        destroy_evidence.write_status_sidecar(
            self.root, "a" * 16, "success", evidence_sha256=evidence_sha256, recorded_at=success_recorded_at
        )

        self.assertTrue(Path(consumed_path).exists())
        self.assertEqual(Path(consumed_path).read_bytes(), consumed_bytes_before)
        success_path = destroy_evidence.status_sidecar_path(self.root, "a" * 16, "success")
        self.assertTrue(Path(success_path).exists())

    def test_writing_a_second_status_of_the_same_name_is_rejected_as_an_append_only_violation(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)

        destroy_evidence.write_status_sidecar(
            self.root, "a" * 16, "consumed", evidence_sha256=evidence_sha256, recorded_at=recorded_at
        )
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.write_status_sidecar(
                self.root, "a" * 16, "consumed", evidence_sha256=evidence_sha256, recorded_at=recorded_at
            )
        self.assertIn("append-only violation", str(ctx.exception))

    def test_status_sidecar_binds_evidence_digest_operation_id_status_and_a_timestamp(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)
        payload = destroy_evidence.build_status_payload(
            operation_id="a" * 16, evidence_sha256=evidence_sha256, status_name="success", recorded_at=recorded_at
        )
        self.assertEqual(
            set(payload.keys()), {"schema_version", "operation_id", "evidence_sha256", "status", "recorded_at"}
        )
        self.assertEqual(payload["operation_id"], "a" * 16)
        self.assertEqual(payload["evidence_sha256"], evidence_sha256)
        self.assertEqual(payload["status"], "success")
        self.assertEqual(payload["recorded_at"], recorded_at)

    def test_a_failure_status_carries_exactly_one_closed_foundation_failure_code(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)

        payload = destroy_evidence.build_status_payload(
            operation_id="a" * 16,
            evidence_sha256=evidence_sha256,
            status_name="failure",
            recorded_at=recorded_at,
            failure_code="DESTROY_HANDLER_FAILED",
        )
        self.assertEqual(
            set(payload.keys()),
            {"schema_version", "operation_id", "evidence_sha256", "status", "recorded_at", "failure_code"},
        )
        self.assertEqual(payload["failure_code"], "DESTROY_HANDLER_FAILED")
        self.assertIn(payload["failure_code"], destroy_evidence.CLOSED_FAILURE_CODES)

    def test_a_failure_status_without_a_failure_code_is_rejected(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.build_status_payload(
                operation_id="a" * 16, evidence_sha256=evidence_sha256, status_name="failure", recorded_at=recorded_at
            )
        self.assertIn("closed foundation failure code", str(ctx.exception))

    def test_a_failure_status_rejects_an_unknown_failure_code(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.build_status_payload(
                operation_id="a" * 16,
                evidence_sha256=evidence_sha256,
                status_name="failure",
                recorded_at=recorded_at,
                failure_code="NOT_A_REAL_CODE",
            )
        self.assertIn("closed foundation failure code", str(ctx.exception))

    def test_a_non_failure_status_rejects_carrying_a_failure_code(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)
        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.build_status_payload(
                operation_id="a" * 16,
                evidence_sha256=evidence_sha256,
                status_name="success",
                recorded_at=recorded_at,
                failure_code="DESTROY_HANDLER_FAILED",
            )
        self.assertIn("only a failure status sidecar may carry a failure_code", str(ctx.exception))

    def test_read_status_sidecar_round_trip_and_expected_status_mismatch_rejection(self):
        evidence_sha256 = self._write_evidence()
        recorded_at = destroy_evidence.format_timestamp(BASE_EPOCH)
        path = destroy_evidence.write_status_sidecar(
            self.root, "a" * 16, "success", evidence_sha256=evidence_sha256, recorded_at=recorded_at
        )

        payload, raw = destroy_evidence.read_status_sidecar(path, expected_status="success")
        self.assertEqual(payload["status"], "success")
        self.assertEqual(destroy_evidence.canonical_bytes(payload), raw)

        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.read_status_sidecar(path, expected_status="failure")
        self.assertIn("does not match expected", str(ctx.exception))


# ---------------------------------------------------------------------------
# Area 8: Retention / cleanup eligibility (90-day minimum retention).
# ---------------------------------------------------------------------------


class RetentionAndCleanupEligibilityTests(_TempDirFixture):
    OPERATION_ID = "a" * 16
    DAY_SECONDS = 86400

    def _write_evidence_and_digest(self):
        path = self.root / f"pre-destroy-guards.{self.OPERATION_ID}.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        destroy_evidence.write_all_pass_evidence(path, payload)
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_terminal_sidecar(self, status_name, evidence_sha256, age_days, *, consumed_first=True):
        now = time.time()
        if consumed_first:
            consumed_path = destroy_evidence.write_status_sidecar(
                self.root,
                self.OPERATION_ID,
                "consumed",
                evidence_sha256=evidence_sha256,
                recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH),
            )
            old = now - age_days * self.DAY_SECONDS
            os.utime(consumed_path, (old, old))
        terminal_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            status_name,
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH + 60),
            failure_code="DESTROY_HANDLER_FAILED" if status_name == "failure" else None,
        )
        old = now - age_days * self.DAY_SECONDS
        os.utime(terminal_path, (old, old))
        return terminal_path

    def test_success_more_than_90_days_past_its_own_timestamp_is_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        self._write_terminal_sidecar("success", evidence_sha256, age_days=91)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertTrue(eligible)

    def test_failure_more_than_90_days_past_its_own_timestamp_is_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        self._write_terminal_sidecar("failure", evidence_sha256, age_days=91)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertTrue(eligible)

    def test_success_fewer_than_90_days_past_its_own_timestamp_is_not_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        self._write_terminal_sidecar("success", evidence_sha256, age_days=10)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_consumed_with_no_terminal_status_is_never_eligible_regardless_of_age(self):
        evidence_sha256 = self._write_evidence_and_digest()
        consumed_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            "consumed",
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        )
        very_old = time.time() - 1000 * self.DAY_SECONDS
        os.utime(consumed_path, (very_old, very_old))

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_terminal_status_without_a_consumed_sidecar_is_treated_as_tampered_and_not_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        self._write_terminal_sidecar("success", evidence_sha256, age_days=91, consumed_first=False)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_unconsumed_evidence_is_eligible_only_after_90_days_past_its_own_expiry(self):
        self._write_evidence_and_digest()
        kwargs = _valid_all_pass_kwargs()
        expires_epoch = destroy_evidence._to_epoch(kwargs["expires_at"])

        not_yet_eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=expires_epoch + 10 * self.DAY_SECONDS
        )
        self.assertFalse(not_yet_eligible)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=expires_epoch + 91 * self.DAY_SECONDS
        )
        self.assertTrue(eligible)

    def test_a_sidecar_with_a_tampered_evidence_sha256_binding_marks_the_operation_not_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        wrong_digest = "f" * 64
        self.assertNotEqual(wrong_digest, evidence_sha256)
        self._write_terminal_sidecar("success", wrong_digest, age_days=91)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_a_symlinked_status_sidecar_marks_the_operation_not_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        consumed_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            "consumed",
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        )
        success_path = destroy_evidence.status_sidecar_path(self.root, self.OPERATION_ID, "success")
        real_target = self.root / "real-success-target.json"
        _write_raw_file(real_target, '{"not":"a real status sidecar"}\n')
        os.symlink(str(real_target), success_path)
        old = time.time() - 91 * self.DAY_SECONDS
        os.utime(consumed_path, (old, old))
        os.utime(success_path, (old, old), follow_symlinks=False)

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_a_wrong_mode_status_sidecar_marks_the_operation_not_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        consumed_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            "consumed",
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        )
        success_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            "success",
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH + 60),
        )
        os.chmod(success_path, 0o644)
        old = time.time() - 91 * self.DAY_SECONDS
        os.utime(consumed_path, (old, old))
        os.utime(success_path, (old, old))

        eligible = destroy_evidence.is_operation_retention_eligible(
            self.root, self.OPERATION_ID, now_epoch=int(time.time())
        )
        self.assertFalse(eligible)

    def test_cleanup_expired_operation_removes_evidence_and_status_files_only_when_eligible(self):
        evidence_sha256 = self._write_evidence_and_digest()
        terminal_path = self._write_terminal_sidecar("success", evidence_sha256, age_days=91)
        evidence_path = self.root / f"pre-destroy-guards.{self.OPERATION_ID}.json"
        consumed_path = destroy_evidence.status_sidecar_path(self.root, self.OPERATION_ID, "consumed")

        removed = destroy_evidence.cleanup_expired_operation(self.root, self.OPERATION_ID, now_epoch=int(time.time()))

        self.assertTrue(removed)
        self.assertFalse(evidence_path.exists())
        self.assertFalse(Path(consumed_path).exists())
        self.assertFalse(Path(terminal_path).exists())

    def test_cleanup_expired_operation_retains_and_reports_false_for_an_ineligible_partial_set(self):
        evidence_sha256 = self._write_evidence_and_digest()
        consumed_path = destroy_evidence.write_status_sidecar(
            self.root,
            self.OPERATION_ID,
            "consumed",
            evidence_sha256=evidence_sha256,
            recorded_at=destroy_evidence.format_timestamp(BASE_EPOCH),
        )
        evidence_path = self.root / f"pre-destroy-guards.{self.OPERATION_ID}.json"

        removed = destroy_evidence.cleanup_expired_operation(self.root, self.OPERATION_ID, now_epoch=int(time.time()))

        self.assertFalse(removed)
        self.assertTrue(evidence_path.exists())
        self.assertTrue(Path(consumed_path).exists())


DIGEST_ALL_ZEROS = "sha256:" + ("0" * 64)


class _OrchestratorGuardCallbackFixture(unittest.TestCase):
    """Sources scripts/lib/orchestrator.sh (and its 5 declared foundation
    dependencies) into a bash subprocess and drives the internal guard-
    dispatch machinery directly: `record_pre_destroy_guard_result` (the
    five-argument foundation callback) and `_orchestrator_dispatch_guard`
    (the guard wrapper caller that detects a missing callback invocation).
    No aws/kubectl mocking is needed here -- unlike
    `_OrchestratorDestroyDispatchFixture` below, these tests call the guard
    machinery directly rather than through `run_unified_command`, so no
    external command is ever invoked; plain coreutils under /usr/bin:/bin
    (the same minimal PATH already proven sufficient by
    test_guards_and_paths.py's `GuardsAndPathsFixture`) is enough."""

    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name).resolve() / "repository"
        self.root.mkdir(parents=True)
        for relative in (
            "scripts/lib/orchestrator.sh",
            "scripts/lib/terraform-destroy-scope.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        ):
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def run_guard_script(self, body):
        """Sources orchestrator.sh, runs `body` (a bash snippet that must
        set $LAST_RC to the return code of the one callback/dispatch call
        under test, and may redefine any `scope_registry_pre_destroy_guard_*`
        function by name before calling `_orchestrator_dispatch_guard`),
        then dumps every piece of guard state these tests need as
        `KEY=value` lines on stdout."""
        script = (
            "source scripts/lib/orchestrator.sh\n"
            + body
            + "\n"
            "printf 'RETURN_CODE=%s\\n' \"$LAST_RC\"\n"
            "printf 'ABORTED=%s\\n' \"$_ORCHESTRATOR_GUARD_ABORTED\"\n"
            "printf 'FAILURE_CODE=%s\\n' \"$_ORCHESTRATOR_GUARD_FAILURE_CODE\"\n"
            "printf 'FAILURE_EXPECTED_SCOPE=%s\\n' \"$_ORCHESTRATOR_GUARD_FAILURE_EXPECTED_SCOPE\"\n"
            "printf 'FAILURE_GUARD_INDEX=%s\\n' \"$_ORCHESTRATOR_GUARD_FAILURE_GUARD_INDEX\"\n"
            "printf 'FAILURE_RESULT_INDEX=%s\\n' \"$_ORCHESTRATOR_GUARD_FAILURE_RESULT_INDEX\"\n"
            "printf 'FAILURE_WRAPPER_STATUS=%s\\n' \"$_ORCHESTRATOR_GUARD_FAILURE_WRAPPER_STATUS\"\n"
            "printf 'RESULT_COUNT=%s\\n' \"${#_ORCHESTRATOR_GUARD_RESULT_SCOPES[@]}\"\n"
            "printf 'RESULT_SCOPES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_SCOPES[*]:-}\"\n"
            "printf 'RESULT_STATUSES=%s\\n' \"${_ORCHESTRATOR_GUARD_RESULT_STATUSES[*]:-}\"\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            capture_output=True,
        )
        state = {}
        for line in result.stdout.splitlines():
            if "=" in line:
                key, _, value = line.partition("=")
                state[key] = value
        state["_result"] = result
        return state

    def tearDown(self):
        self._temporary.cleanup()


def _guard_result_call(scope, resource_identity="EKS-boomi-runtime-cluster", summary_code="CLUSTER_ABSENT"):
    return (
        "record_pre_destroy_guard_result " + scope + " PASS " + resource_identity
        + " " + DIGEST_ALL_ZEROS + " " + summary_code
    )


# ---------------------------------------------------------------------------
# Area 9: the five-argument guard callback contract.
# ---------------------------------------------------------------------------


class GuardCallbackContractTests(_OrchestratorGuardCallbackFixture):
    """Area 9: the exact five-argument
    `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity>
    <sha256-digest> <summary-code>` foundation callback (confirmed by
    reading scripts/lib/orchestrator.sh in full to be exactly this name --
    matches the plan's own guess), and `_orchestrator_dispatch_guard`'s
    detection of a guard wrapper that returns without ever calling it.

    Judgment call (flagged in the final chat report): the plan's plain-
    English "out-of-order call (calling for a scope whose phase hasn't
    started yet)" does not match orchestrator.sh's own real logic. Reading
    `record_pre_destroy_guard_result` shows two distinct closed failure
    codes: a scope that is neither the active scope nor already present in
    the arrival-order result list is `GUARD_WRONG_SCOPE`; only a scope that
    already recorded a result *earlier in this same operation* reporting
    again is `GUARD_OUT_OF_ORDER`. The literal "phase hasn't started yet"
    scenario the plan describes is therefore `GUARD_WRONG_SCOPE` in the real
    code, not `GUARD_OUT_OF_ORDER`. Both real code paths are tested below
    against their actual, verified behavior rather than the plan's looser
    prose, per this session's "verify real function/CLI signatures by
    reading before asserting" rule.
    """

    GOOD_DIGEST = DIGEST_ALL_ZEROS

    def test_exactly_five_well_formed_arguments_are_accepted_while_a_phase_is_active(self):
        state = self.run_guard_script(
            "_orchestrator_reset_guard_state\n"
            "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
            + _guard_result_call("eks-platform") + "\n"
            "LAST_RC=$?\n"
        )
        self.assertEqual(state["RETURN_CODE"], "0")
        self.assertEqual(state["ABORTED"], "false")
        self.assertEqual(state["RESULT_COUNT"], "1")
        self.assertEqual(state["RESULT_SCOPES"], "eks-platform")
        self.assertEqual(state["RESULT_STATUSES"], "PASS")

    def test_a_call_missing_the_fifth_argument_is_rejected_as_malformed(self):
        state = self.run_guard_script(
            "_orchestrator_reset_guard_state\n"
            "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
            "record_pre_destroy_guard_result eks-platform PASS EKS-boomi-runtime-cluster "
            + self.GOOD_DIGEST + "\n"
            "LAST_RC=$?\n"
        )
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["ABORTED"], "true")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_MALFORMED_RESULT")

    def test_a_call_outside_an_active_guard_phase_is_rejected(self):
        state = self.run_guard_script(
            "_orchestrator_reset_guard_state\n"
            + _guard_result_call("eks-platform") + "\n"
            "LAST_RC=$?\n"
        )
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["ABORTED"], "true")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_OUT_OF_PHASE")

    def test_a_call_for_a_scope_that_never_had_an_active_or_prior_turn_is_rejected_as_wrong_scope(self):
        state = self.run_guard_script(
            "_orchestrator_reset_guard_state\n"
            "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
            + _guard_result_call("mongodb") + "\n"
            "LAST_RC=$?\n"
        )
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_WRONG_SCOPE")
        self.assertEqual(state["FAILURE_EXPECTED_SCOPE"], "eks-platform")

    def test_a_duplicate_call_for_the_same_already_reported_scope_is_rejected(self):
        state = self.run_guard_script(
            "_orchestrator_reset_guard_state\n"
            "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
            + _guard_result_call("eks-platform") + "\n"
            "FIRST_RC=$?\n"
            "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
            + _guard_result_call("eks-platform") + "\n"
            "LAST_RC=$?\n"
            "printf 'FIRST_RC=%s\\n' \"$FIRST_RC\"\n"
        )
        self.assertEqual(state["FIRST_RC"], "0")
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_DUPLICATE_RESULT")
        self.assertEqual(state["RESULT_COUNT"], "2")

    def test_a_malformed_digest_is_rejected(self):
        for bad_digest in ("not-a-digest", "sha256:" + ("0" * 63), "sha256:" + ("A" * 64)):
            with self.subTest(bad_digest=bad_digest):
                state = self.run_guard_script(
                    "_orchestrator_reset_guard_state\n"
                    "_ORCHESTRATOR_GUARD_ACTIVE_SCOPE=\"eks-platform\"\n"
                    "record_pre_destroy_guard_result eks-platform PASS EKS-boomi-runtime-cluster "
                    + bad_digest + " CLUSTER_ABSENT\n"
                    "LAST_RC=$?\n"
                )
                self.assertEqual(state["RETURN_CODE"], "1")
                self.assertEqual(state["FAILURE_CODE"], "GUARD_MALFORMED_RESULT")

    def test_a_missing_call_is_detected_by_dispatch_as_guard_missing_result(self):
        state = self.run_guard_script(
            "scope_registry_pre_destroy_guard_eks_platform() { return 0; }\n"
            "_orchestrator_reset_guard_state\n"
            "_orchestrator_dispatch_guard \"eks-platform\" \"0\"\n"
            "LAST_RC=$?\n"
        )
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["ABORTED"], "true")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_MISSING_RESULT")
        self.assertEqual(state["FAILURE_EXPECTED_SCOPE"], "eks-platform")
        self.assertEqual(state["FAILURE_GUARD_INDEX"], "0")
        self.assertEqual(state["RESULT_COUNT"], "0")

    def test_an_out_of_order_call_for_a_scope_that_already_completed_its_own_turn_is_rejected(self):
        state = self.run_guard_script(
            "scope_registry_pre_destroy_guard_eks_platform() { " + _guard_result_call("eks-platform") + "; }\n"
            "scope_registry_pre_destroy_guard_mongodb() { " + _guard_result_call("eks-platform") + "; }\n"
            "_orchestrator_reset_guard_state\n"
            "_orchestrator_dispatch_guard \"eks-platform\" \"0\"\n"
            "FIRST_RC=$?\n"
            "_orchestrator_dispatch_guard \"mongodb\" \"1\"\n"
            "LAST_RC=$?\n"
            "printf 'FIRST_RC=%s\\n' \"$FIRST_RC\"\n"
        )
        self.assertEqual(state["FIRST_RC"], "0")
        self.assertEqual(state["RETURN_CODE"], "1")
        self.assertEqual(state["FAILURE_CODE"], "GUARD_OUT_OF_ORDER")
        self.assertEqual(state["FAILURE_EXPECTED_SCOPE"], "mongodb")


if __name__ == "__main__":
    unittest.main()
