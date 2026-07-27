"""Task 4 ("Add Explicit Unified Entrypoints Without Changing Legacy Dev
Behavior") tests for the two foundation-only, standard-library-only Python
modules that implement the destroy confirmation/evidence protocol:
`scripts/lib/confirmation-artifact.py` and `scripts/lib/destroy-evidence.py`.

This file covers these 10 areas (see
docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md,
Task 4 Step 5, from line 1072 onward, for the exact schema/safety
requirements each test below maps to):

  1. Canonical JSON bytes (both modules)   -> CanonicalBytesAndDuplicateKeyRejectionTests
  2. Confirmation artifact schema/safety   -> ConfirmationArtifactSchemaAndSafetyTests
  3. Confirmation grammar validation       -> ConfirmationGrammarValidationTests
  4. Guard-failure record schema/safety    -> GuardFailureRecordSchemaAndSafetyTests
  5. All-pass evidence schema/safety       -> AllPassEvidenceSchemaAndSafetyTests
  6. Consumption                           -> ConsumptionTests,
                                               ConsumedPathRejectedAsFreshInputTests
  7. Status lifecycle                      -> StatusLifecycleTests
  8. Retention / cleanup eligibility       -> RetentionAndCleanupEligibilityTests
  9. Five-argument guard callback contract -> GuardCallbackContractTests
  10. Handler confirmation-subset passing  -> HandlerConfirmationSubsetPassingTests

Areas 9 and 10 additionally source scripts/lib/orchestrator.sh (and its 5
declared foundation dependencies) into real bash subprocesses, following the
same from-scratch-clean-environment, no-RepositoryFixture-reuse pattern
established by tests/environment_orchestration/test_guards_and_paths.py's
`GuardsAndPathsFixture` and tests/environment_orchestration/
test_entrypoints.py's `OrchestratorFixture` -- see `_OrchestratorGuardCallbackFixture`
and `_OrchestratorDestroyDispatchFixture` below for the exact technique
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
  * The "rejects non-regular file" case for confirmation-artifact.py uses a
    directory rather than a FIFO/special file: opening a FIFO for reading
    with no writer present blocks indefinitely, which would hang the test
    suite. A directory opens without blocking and still reliably produces
    the `S_ISREG` failure path.
  * The "no-follow open rejects a symlink" assertion checks only that a
    `ConfirmationArtifactError` is raised and that its message contains the
    substring "confirmation artifact" -- both possible failure paths (the
    `os.O_NOFOLLOW`-triggered `OSError` caught at open time, or the
    defense-in-depth `stat.S_ISLNK` check reached if `O_NOFOLLOW` were ever
    unavailable) produce a message containing that substring, so the
    assertion is correct on any POSIX platform the suite might run on.

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
CONFIRMATION_ARTIFACT_PATH = REPO_ROOT / "scripts" / "lib" / "confirmation-artifact.py"
DESTROY_EVIDENCE_PATH = REPO_ROOT / "scripts" / "lib" / "destroy-evidence.py"


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


confirmation_artifact = _load_module("confirmation_artifact_under_test", CONFIRMATION_ARTIFACT_PATH)
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


def _valid_confirmation_kwargs(**overrides):
    kwargs = dict(
        operation_id="a" * 16,
        created_at=confirmation_artifact.format_timestamp(BASE_EPOCH),
        expires_at=confirmation_artifact.format_timestamp(BASE_EPOCH + confirmation_artifact.LIFETIME_SECONDS),
        environment="uat",
        account_id="672172129937",
        requested_scope="eks-platform",
        resolved_scopes=["eks-platform"],
        confirmations=[
            "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster",
        ],
    )
    kwargs.update(overrides)
    return kwargs


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
# Area 1: Canonical JSON bytes (both modules).
# ---------------------------------------------------------------------------


class CanonicalBytesAndDuplicateKeyRejectionTests(_TempDirFixture):
    def test_confirmation_artifact_canonical_bytes_are_sorted_compact_ascii_with_one_trailing_newline(self):
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        data = confirmation_artifact.canonical_bytes(payload)
        text = data.decode("ascii")

        self.assertEqual(text.count("\n"), 1)
        self.assertTrue(text.endswith("\n"))
        body = text[:-1]
        self.assertEqual(body, json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True))
        self.assertNotIn(" ", body)

    def test_destroy_evidence_canonical_bytes_are_sorted_compact_ascii_with_one_trailing_newline(self):
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        data = destroy_evidence.canonical_bytes(payload)
        text = data.decode("ascii")

        self.assertEqual(text.count("\n"), 1)
        self.assertTrue(text.endswith("\n"))
        body = text[:-1]
        self.assertEqual(body, json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True))
        self.assertNotIn(" ", body)

    def test_confirmation_artifact_rejects_duplicate_keys_on_read(self):
        path = self.root / "dup-confirmation.json"
        _write_raw_file(path, '{"a":1,"a":2}\n')

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.read_confirmation_artifact(path)
        self.assertIn("duplicate key", str(ctx.exception))

    def test_destroy_evidence_rejects_duplicate_keys_on_read(self):
        path = self.root / "dup-evidence.json"
        _write_raw_file(path, '{"a":1,"a":2}\n')

        with self.assertRaises(destroy_evidence.DestroyEvidenceError) as ctx:
            destroy_evidence.read_evidence_document(path, kind="all-pass")
        self.assertIn("duplicate key", str(ctx.exception))

    def test_confirmation_artifact_read_reserialize_round_trip_is_byte_identical(self):
        path = self.root / "confirmation.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        written = confirmation_artifact.create_artifact(path, payload)

        read_payload, raw = confirmation_artifact.read_confirmation_artifact(path)

        self.assertEqual(raw, written)
        self.assertEqual(confirmation_artifact.canonical_bytes(read_payload), written)

    def test_destroy_evidence_read_reserialize_round_trip_is_byte_identical(self):
        path = self.root / "evidence.json"
        payload = destroy_evidence.build_all_pass_evidence_payload(**_valid_all_pass_kwargs())
        written = destroy_evidence.write_all_pass_evidence(path, payload)

        read_payload, raw = destroy_evidence.read_evidence_document(path, kind="all-pass")

        self.assertEqual(raw, written)
        self.assertEqual(destroy_evidence.canonical_bytes(read_payload), written)


# ---------------------------------------------------------------------------
# Area 2: Confirmation artifact exact schema/safety.
# ---------------------------------------------------------------------------


class ConfirmationArtifactSchemaAndSafetyTests(_TempDirFixture):
    def test_valid_payload_has_exactly_9_keys(self):
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())

        self.assertEqual(len(confirmation_artifact.REQUIRED_KEYS), 9)
        self.assertEqual(set(payload.keys()), set(confirmation_artifact.REQUIRED_KEYS))

    def test_create_artifact_exclusive_creation_fails_if_path_exists(self):
        path = self.root / "confirmation.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        confirmation_artifact.create_artifact(path, payload)

        with self.assertRaises(FileExistsError):
            confirmation_artifact.create_artifact(path, payload)

    def test_create_artifact_mode_exactly_0600(self):
        path = self.root / "confirmation.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        confirmation_artifact.create_artifact(path, payload)

        mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(mode, 0o600)

    def test_read_rejects_symlink_at_target_path(self):
        real_path = self.root / "real.json"
        _write_raw_file(real_path, "{}\n")
        link_path = self.root / "link.json"
        os.symlink(str(real_path), str(link_path))

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.read_confirmation_artifact(link_path)
        self.assertIn("confirmation artifact", str(ctx.exception))

    def test_read_rejects_non_regular_file(self):
        path = self.root / "not-a-file"
        os.mkdir(path)

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.read_confirmation_artifact(path)
        self.assertIn("must be a regular file", str(ctx.exception))

    def test_read_rejects_wrong_mode(self):
        path = self.root / "wrong-mode.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        data = confirmation_artifact.canonical_bytes(payload)
        _write_raw_file(path, data.decode("ascii"), mode=0o644)

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.read_confirmation_artifact(path)
        self.assertIn("mode 0600", str(ctx.exception))

    def test_validate_schema_rejects_unknown_key(self):
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        payload["unexpected_extra_field"] = "x"

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.validate_schema(payload)
        self.assertIn("key set mismatch", str(ctx.exception))

    def test_validate_schema_rejects_missing_key(self):
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        del payload["confirmations"]

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.validate_schema(payload)
        self.assertIn("key set mismatch", str(ctx.exception))

    def test_validate_schema_rejects_malformed_timestamp(self):
        kwargs = _valid_confirmation_kwargs(created_at="2026-07-23 00:00:00Z")

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.build_payload(**kwargs)
        self.assertIn("created_at", str(ctx.exception))

    def test_validate_schema_rejects_malformed_operation_id(self):
        kwargs = _valid_confirmation_kwargs(operation_id="A" * 16)

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.build_payload(**kwargs)
        self.assertIn("operation_id", str(ctx.exception))

    def test_validate_schema_rejects_wrong_creation_to_expiry_interval(self):
        kwargs = _valid_confirmation_kwargs(
            expires_at=confirmation_artifact.format_timestamp(BASE_EPOCH + 800)
        )

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.build_payload(**kwargs)
        self.assertIn("immutable 15-minute lifetime", str(ctx.exception))

    def test_validate_against_request_rejects_filename_payload_operation_id_mismatch(self):
        kwargs = _valid_confirmation_kwargs()
        payload = confirmation_artifact.build_payload(**kwargs)

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.validate_against_request(
                payload,
                now_epoch=BASE_EPOCH + 100,
                path_operation_id="b" * 16,
                environment=kwargs["environment"],
                account_id=kwargs["account_id"],
                requested_scope=kwargs["requested_scope"],
                resolved_scopes=kwargs["resolved_scopes"],
                confirmations=kwargs["confirmations"],
            )
        self.assertIn("operation_id disagreement", str(ctx.exception))

    def test_validate_against_request_rejects_expiry_at_or_before_now(self):
        kwargs = _valid_confirmation_kwargs()
        payload = confirmation_artifact.build_payload(**kwargs)
        expires_epoch = BASE_EPOCH + confirmation_artifact.LIFETIME_SECONDS

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.validate_against_request(
                payload,
                now_epoch=expires_epoch,
                path_operation_id=kwargs["operation_id"],
                environment=kwargs["environment"],
                account_id=kwargs["account_id"],
                requested_scope=kwargs["requested_scope"],
                resolved_scopes=kwargs["resolved_scopes"],
                confirmations=kwargs["confirmations"],
            )
        self.assertIn("has expired", str(ctx.exception))

    def test_validate_against_request_rejects_future_creation_time(self):
        future_created_epoch = BASE_EPOCH + 1000
        kwargs = _valid_confirmation_kwargs(
            created_at=confirmation_artifact.format_timestamp(future_created_epoch),
            expires_at=confirmation_artifact.format_timestamp(
                future_created_epoch + confirmation_artifact.LIFETIME_SECONDS
            ),
        )
        payload = confirmation_artifact.build_payload(**kwargs)

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.validate_against_request(
                payload,
                now_epoch=BASE_EPOCH + 500,
                path_operation_id=kwargs["operation_id"],
                environment=kwargs["environment"],
                account_id=kwargs["account_id"],
                requested_scope=kwargs["requested_scope"],
                resolved_scopes=kwargs["resolved_scopes"],
                confirmations=kwargs["confirmations"],
            )
        self.assertIn("is in the future", str(ctx.exception))


# ---------------------------------------------------------------------------
# Area 3: Confirmation grammar validation
# (destroy:<env>:<account-id>:<scope>:<resource>:<consequence>).
# ---------------------------------------------------------------------------


class ConfirmationGrammarValidationTests(unittest.TestCase):
    def test_accepts_well_formed_confirmation_value(self):
        confirmation_artifact.validate_confirmation_value(
            "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster"
        )

    def test_rejects_component_containing_colon(self):
        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError):
            confirmation_artifact.validate_confirmation_value(
                "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete:cluster"
            )

    def test_rejects_component_containing_whitespace(self):
        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError):
            confirmation_artifact.validate_confirmation_value(
                "destroy:uat:672172129937:eks-platform:EKS boomi runtime cluster:delete-cluster"
            )

    def test_rejects_empty_component(self):
        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError):
            confirmation_artifact.validate_confirmation_value(
                "destroy:uat::eks-platform:EKS-boomi-runtime-cluster:delete-cluster"
            )

    def test_rejects_component_containing_shell_metacharacter(self):
        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError):
            confirmation_artifact.validate_confirmation_value(
                "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster;rm"
            )


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

    def test_confirmation_artifact_sha256_is_real_sha256_of_artifact_bytes(self):
        artifact_path = self.root / "confirmation.json"
        confirmation_payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        written_bytes = confirmation_artifact.create_artifact(artifact_path, confirmation_payload)
        expected_digest = hashlib.sha256(written_bytes).hexdigest()

        evidence_payload = destroy_evidence.build_all_pass_evidence_payload(
            **_valid_all_pass_kwargs(confirmation_artifact_sha256=expected_digest)
        )

        on_disk_bytes = artifact_path.read_bytes()
        self.assertEqual(written_bytes, on_disk_bytes)
        self.assertEqual(hashlib.sha256(on_disk_bytes).hexdigest(), evidence_payload["confirmation_artifact_sha256"])

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
# Area 6: Consumption (confirmation-artifact.py's atomic "consumed" rename).
# ---------------------------------------------------------------------------


class ConsumptionTests(_TempDirFixture):
    def test_consume_artifact_atomically_renames_to_the_consumed_suffix(self):
        path = self.root / "destroy-confirmation.aaaaaaaaaaaaaaaa.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        written = confirmation_artifact.create_artifact(path, payload)

        consumed_path, raw = confirmation_artifact.consume_artifact(path)

        self.assertEqual(consumed_path, str(path) + ".consumed")
        self.assertFalse(path.exists())
        self.assertTrue(Path(consumed_path).exists())
        self.assertEqual(raw, written)

    def test_consume_artifact_rejects_if_the_consumed_path_already_exists(self):
        path = self.root / "destroy-confirmation.aaaaaaaaaaaaaaaa.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        confirmation_artifact.create_artifact(path, payload)
        _write_raw_file(Path(str(path) + ".consumed"), "{}\n")

        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
            confirmation_artifact.consume_artifact(path)
        self.assertIn("already exists", str(ctx.exception))
        # No rename was attempted (the already-exists check runs first), so
        # the original unconsumed artifact must still be present.
        self.assertTrue(path.exists())

    def test_consume_artifact_aborts_and_never_renames_back_if_post_rename_identity_check_fails(self):
        path = self.root / "destroy-confirmation.aaaaaaaaaaaaaaaa.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        confirmation_artifact.create_artifact(path, payload)
        consumed_path = str(path) + ".consumed"
        real_lstat = os.lstat

        class _TamperedStatResult:
            def __init__(self, real_result):
                self.st_dev = real_result.st_dev + 1
                self.st_ino = real_result.st_ino
                self.st_mode = real_result.st_mode

        def fake_lstat(target, *args, **kwargs):
            result = real_lstat(target, *args, **kwargs)
            if str(target) == consumed_path:
                return _TamperedStatResult(result)
            return result

        # The real post-rename identity check compares (st_dev, st_ino)
        # captured before the rename against a fresh os.lstat() of the
        # consumed name; forcing a mismatch deterministically (rather than
        # relying on an unreproducible OS-level race) requires patching
        # os.lstat for exactly this one call.
        with mock.patch("os.lstat", side_effect=fake_lstat):
            with self.assertRaises(confirmation_artifact.ConfirmationArtifactError) as ctx:
                confirmation_artifact.consume_artifact(path)
        self.assertIn("identity changed across rename", str(ctx.exception))

        # The rename to the consumed name already happened before the
        # identity check runs; the artifact is never renamed back to its
        # original name even though this consumption attempt is a failure.
        self.assertFalse(path.exists())
        self.assertTrue(Path(consumed_path).exists())

    def test_consume_artifact_on_an_already_consumed_original_path_fails(self):
        path = self.root / "destroy-confirmation.aaaaaaaaaaaaaaaa.json"
        payload = confirmation_artifact.build_payload(**_valid_confirmation_kwargs())
        confirmation_artifact.create_artifact(path, payload)

        confirmation_artifact.consume_artifact(path)

        # The original filename no longer exists (it was renamed away), so
        # a second consumption attempt on the same original path is
        # rejected -- a consumed path is never accepted as fresh input
        # again under its original name either.
        with self.assertRaises(confirmation_artifact.ConfirmationArtifactError):
            confirmation_artifact.consume_artifact(path)


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


_DESTROY_DISPATCH_MOCK_AWS_SCRIPT = """#!/usr/bin/env bash
printf 'aws %s\\n' "$*" >> "$MOCK_COMMAND_LOG"
if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
  printf '%s\\n' "${MOCK_AWS_ACCOUNT_ID:-000000000000}"
  exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ]; then
  printf '%s\\n' "${MOCK_AWS_CONFIGURED_REGION:-}"
  exit 0
fi
printf 'unhandled mock aws invocation: %s\\n' "$*" >&2
exit 1
"""


def _guard_override(function_name, scope, resource_identity="RESOURCE-PLACEHOLDER"):
    return (
        function_name + "() { record_pre_destroy_guard_result " + scope + " PASS "
        + resource_identity + " " + DIGEST_ALL_ZEROS + " SCOPE_GUARD_PASSED; }\n"
    )


def _handler_override(function_name):
    return (
        function_name + "() {\n"
        "  printf '%s\\n' \"$#\" > \"$HANDLER_ARGS_FILE\"\n"
        "  if [ \"$#\" -gt 0 ]; then printf '%s\\n' \"$@\" >> \"$HANDLER_ARGS_FILE\"; fi\n"
        "  return 0\n"
        "}\n"
    )


class _OrchestratorDestroyDispatchFixture(unittest.TestCase):
    """Drives the real `run_unified_command destroy --env uat <scope> ...`
    two-pass protocol end to end through scripts/lib/orchestrator.sh, always
    against a single narrow-scope destroy target -- never "all", which
    scope-registry.sh's `resolve_destroy_order` deliberately does not expand
    for an ordinary named scope (confirmed by reading it: "Ordinary destroy
    of a single narrow scope destroys exactly that scope"). The one
    canonical pre-destroy guard function and one canonical destroy handler
    function for the scope under test are redefined, after sourcing, to an
    always-PASS guard and an argument-recording handler respectively --
    the same "override a real registry-mapped function name after
    sourcing" technique `GuardCallbackContractTests` above uses, extended
    here through the complete confirmation-artifact + guard-evidence +
    consumption + dispatch flow.

    `ORCHESTRATOR_TEST_CLOCK_EPOCH`/`ORCHESTRATOR_TEST_OPERATION_ID`
    (orchestrator.sh's own documented test seams) make the confirmation
    artifact's path, every timestamp, and every derived confirmation value
    fully deterministic and computable in Python ahead of time, so no test
    here needs to parse the preparation pass's own stdout.

    Judgment call (flagged in the final chat report): proving a handler
    receives *only* its own subset -- "not the full confirmation set" -- is
    tested here via distinct single-scope runs (each selecting exactly one
    scope, so there is only ever one handler's own value in play) rather
    than one real multi-scope run. `resolve_destroy_order` never cascades
    dependents for an ordinary named scope, and reaching two real
    confirmation-requiring scopes in one dispatch would require selecting
    "all" (dragging in all 13 real destroy scopes and needing 13 guard and
    13 handler overrides) for no added assertion strength, since the
    subset-selection loop inside `_orchestrator_destroy_second_pass` is a
    simple per-step scope-equality filter that is independent of how many
    other scopes exist in the request.
    """

    FIXED_CLOCK_EPOCH = BASE_EPOCH
    FIXED_OPERATION_ID = "a" * 16

    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name).resolve() / "repository"
        self.mock_bin = Path(self._temporary.name) / "bin"
        self.command_log = Path(self._temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)

        aws_path = self.mock_bin / "aws"
        aws_path.write_text(_DESTROY_DISPATCH_MOCK_AWS_SCRIPT, encoding="ascii")
        aws_path.chmod(aws_path.stat().st_mode | stat.S_IXUSR)

        for relative in (
            "scripts/lib/orchestrator.sh",
            "scripts/lib/environment-contracts.sh",
            "scripts/lib/platform-env.sh",
            "scripts/lib/platform-guards.sh",
            "scripts/lib/orchestration-paths.sh",
            "scripts/lib/scope-registry.sh",
            "scripts/lib/confirmation-artifact.py",
            "scripts/lib/destroy-evidence.py",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        ):
            source = REPO_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        python3_path = shutil.which("python3")
        self.assertIsNotNone(python3_path, "python3 must be resolvable on PATH to run these tests")
        # Keep the environment otherwise clean/explicit (following
        # test_entrypoints.py's OrchestratorFixture rather than
        # helpers.py's os.environ.copy()-based RepositoryFixture), but add
        # python3's real directory so orchestrator.sh's `_ORCHESTRATOR_PYTHON`
        # (bare "python3") actually resolves regardless of host layout.
        self._clean_path = f"{self.mock_bin}:{Path(python3_path).parent}:/usr/bin:/bin"

    def artifact_relative_path(self):
        return f".local/uat/generated/destroy-confirmation.{self.FIXED_OPERATION_ID}.json"

    def run_destroy(self, override_script, scope_args, handler_args_file):
        environment = {
            "PATH": self._clean_path,
            "MOCK_COMMAND_LOG": str(self.command_log),
            "MOCK_AWS_ACCOUNT_ID": "672172129937",
            "MOCK_AWS_CONFIGURED_REGION": "ap-east-1",
            "ORCHESTRATOR_TEST_CLOCK_EPOCH": str(self.FIXED_CLOCK_EPOCH),
            "ORCHESTRATOR_TEST_OPERATION_ID": self.FIXED_OPERATION_ID,
            "HANDLER_ARGS_FILE": str(handler_args_file),
        }
        script = (
            "source scripts/lib/orchestrator.sh\n"
            + override_script
            + "\nrun_unified_command \"$@\"\n"
        )
        return subprocess.run(
            ["bash", "-c", script, "bash", "destroy", "--env", "uat", *scope_args],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

    def tearDown(self):
        self._temporary.cleanup()


# ---------------------------------------------------------------------------
# Area 6 (continued): a `.consumed`-suffixed path is never accepted as fresh
# `--confirmation-artifact` input again, enforced by orchestrator.sh's own
# second-pass path grammar (confirmation-artifact.py itself has no
# filename-suffix awareness -- see ConsumptionTests below for its half of
# Area 6).
# ---------------------------------------------------------------------------


class ConsumedPathRejectedAsFreshInputTests(_OrchestratorDestroyDispatchFixture):
    def test_a_dot_consumed_suffixed_path_is_rejected_by_the_real_second_pass_path_grammar(self):
        fake_consumed_path = (
            f".local/uat/generated/destroy-confirmation.{self.FIXED_OPERATION_ID}.json.consumed"
        )
        handler_args_file = Path(self._temporary.name) / "unused-handler-args.txt"

        result = self.run_destroy(
            "", ["eks-access", "--confirmation-artifact", fake_consumed_path, "--auto-approve"], handler_args_file
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("invalid --confirmation-artifact path", result.stderr)


# ---------------------------------------------------------------------------
# Area 10: handler confirmation-subset passing.
# ---------------------------------------------------------------------------


class HandlerConfirmationSubsetPassingTests(_OrchestratorDestroyDispatchFixture):
    def test_handler_for_a_scope_with_a_confirmation_requirement_receives_exactly_its_own_ordered_value(self):
        scope = "eks-platform"
        confirmation_value = "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster"
        override = (
            _guard_override("scope_registry_pre_destroy_guard_eks_platform", "eks-platform")
            + _handler_override("scope_registry_deferred_eks_platform_destroy")
        )
        handler_args_file = Path(self._temporary.name) / "handler-args-eks-platform.txt"

        prep = self.run_destroy(override, [scope], handler_args_file)
        self.assertNotEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        artifact_path = self.artifact_relative_path()
        self.assertTrue((self.root / artifact_path).exists(), prep.stdout + prep.stderr)

        second = self.run_destroy(
            override,
            [scope, "--confirmation-artifact", artifact_path, "--confirm", confirmation_value, "--auto-approve"],
            handler_args_file,
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)

        lines = handler_args_file.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "1")
        self.assertEqual(lines[1:], [confirmation_value])

    def test_handler_for_a_scope_with_no_confirmation_requirement_receives_zero_confirmation_arguments(self):
        scope = "eks-access"
        override = (
            _guard_override("scope_registry_pre_destroy_guard_eks_access", "eks-access")
            + _handler_override("scope_registry_deferred_eks_access_destroy")
        )
        handler_args_file = Path(self._temporary.name) / "handler-args-eks-access.txt"

        prep = self.run_destroy(override, [scope], handler_args_file)
        self.assertNotEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        artifact_path = self.artifact_relative_path()
        self.assertTrue((self.root / artifact_path).exists(), prep.stdout + prep.stderr)

        second = self.run_destroy(
            override, [scope, "--confirmation-artifact", artifact_path, "--auto-approve"], handler_args_file
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)

        lines = handler_args_file.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "0")
        self.assertEqual(lines[1:], [])

    def test_handler_for_a_different_confirmation_requiring_scope_receives_its_own_distinct_value(self):
        scope = "postgresql-brand"
        created_at = destroy_evidence.format_timestamp(self.FIXED_CLOCK_EPOCH)
        snapshot_timestamp = created_at.replace(":", "").replace("-", "")
        confirmation_value = (
            "destroy:uat:672172129937:postgresql-brand:db/oms-uat-brand:"
            f"final-snapshot=oms-uat-brand-final-{snapshot_timestamp}"
        )
        override = (
            _guard_override("scope_registry_pre_destroy_guard_postgresql_brand", "postgresql-brand")
            + _handler_override("scope_registry_deferred_postgresql_brand_destroy")
        )
        handler_args_file = Path(self._temporary.name) / "handler-args-postgresql-brand.txt"

        prep = self.run_destroy(override, [scope], handler_args_file)
        self.assertNotEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        artifact_path = self.artifact_relative_path()
        self.assertTrue((self.root / artifact_path).exists(), prep.stdout + prep.stderr)

        second = self.run_destroy(
            override,
            [scope, "--confirmation-artifact", artifact_path, "--confirm", confirmation_value, "--auto-approve"],
            handler_args_file,
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)

        lines = handler_args_file.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "1")
        self.assertEqual(lines[1:], [confirmation_value])
        self.assertNotEqual(
            confirmation_value, "destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster"
        )


if __name__ == "__main__":
    unittest.main()
