#!/usr/bin/env python3
"""Foundation-only pre-destroy guard evidence implementation.

"Task 4: Add Explicit Unified Entrypoints Without Changing Legacy Dev
Behavior" in
docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
owns this file. It is a standard-library-only implementation (no third-party
imports) used exclusively by scripts/lib/orchestrator.sh through the small
CLI at the bottom of this file. It is never a public operator entrypoint and
is never sourced/imported by a package fragment.

This module owns exactly two closed, durable, mode-0600, exclusively-created
JSON record shapes:

  - The all-pass guard-evidence artifact
    (`pre-destroy-guards.<operation-id>.json`), written only after every
    selected pre-destroy guard for a destroy operation returned `PASS`
    through the foundation callback.
  - The guard-failure record
    (`destroy-guard-failure.<operation-id>.json`), written instead on the
    first `FAIL`, missing, duplicate, malformed, wrong-scope, out-of-phase,
    out-of-order, or wrapper/status-disagreeing result.

It also owns the append-only lifecycle status sidecars
(`pre-destroy-guards.<operation-id>.status.<consumed|success|failure>.json`)
and the 90-day-minimum retention/cleanup helper. It never receives or writes
a confirmation artifact; `scripts/lib/confirmation-artifact.py` is the sole
owner of that separate schema. The two files intentionally duplicate the
small canonical-byte/duplicate-key-rejection helpers rather than importing
each other, so each remains an independent, self-contained,
standard-library-only foundation module.
"""

import argparse
import json
import os
import re
import stat
import sys
import time
from pathlib import Path

SCHEMA_VERSION = 1
MINIMUM_RETENTION_DAYS = 90

TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
OPERATION_ID_RE = re.compile(r"^[0-9a-f]{16,64}$")
SCOPE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
ACCOUNT_ID_RE = re.compile(r"^[0-9]{12}$")
STATUS_RE = re.compile(r"^(PASS|FAIL)$")
RESOURCE_IDENTITY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@+=:-]{0,255}$")
EVIDENCE_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
SUMMARY_CODE_RE = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")
FAILURE_CODE_RE = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")

GUARD_RESULT_KEYS = ("scope", "status", "resource_identity", "evidence_digest", "summary_code")
FAILURE_KEYS = ("code", "expected_scope", "guard_index", "result_index", "wrapper_status")

EVIDENCE_KEYS = (
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

GUARD_FAILURE_KEYS = (
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

STATUS_SIDECAR_KEYS_COMMON = ("schema_version", "operation_id", "evidence_sha256", "status", "recorded_at")

CLOSED_FAILURE_CODES = (
    "GUARD_FAIL",
    "GUARD_MISSING_RESULT",
    "GUARD_DUPLICATE_RESULT",
    "GUARD_MALFORMED_RESULT",
    "GUARD_WRONG_SCOPE",
    "GUARD_OUT_OF_PHASE",
    "GUARD_OUT_OF_ORDER",
    "GUARD_WRAPPER_STATUS_DISAGREEMENT",
    # Post-consumption failure codes: guards have already all passed by the
    # time these can occur, so they are deliberately distinct from every
    # GUARD_* code above.
    "DESTROY_HANDLER_FAILED",
)


class DestroyEvidenceError(Exception):
    """Raised for every schema, canonical-byte, safety, or lifecycle failure."""


def _error(message):
    raise DestroyEvidenceError(message)


def _duplicate_key_hook(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            _error(f"duplicate key in evidence document: {key}")
        seen[key] = value
    return seen


def canonical_bytes(payload):
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return (text + "\n").encode("ascii")


def _to_epoch(value):
    import calendar

    struct_time = time.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    return calendar.timegm(struct_time)


def format_timestamp(epoch_seconds):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch_seconds))


def _require_timestamp(value, field_name):
    if not isinstance(value, str) or not TIMESTAMP_RE.match(value):
        _error(f"{field_name} must be an ISO-8601 UTC timestamp of the form YYYY-MM-DDTHH:MM:SSZ")
    try:
        return _to_epoch(value)
    except ValueError:
        _error(f"{field_name} is not a valid calendar timestamp: {value}")


def validate_guard_result_object(obj):
    if not isinstance(obj, dict) or set(obj.keys()) != set(GUARD_RESULT_KEYS):
        _error(f"guard result object must contain exactly {GUARD_RESULT_KEYS}: {obj!r}")

    scope = obj["scope"]
    if not isinstance(scope, str) or not SCOPE_RE.match(scope):
        _error(f"malformed guard result scope: {scope!r}")

    status = obj["status"]
    if not isinstance(status, str) or not STATUS_RE.match(status):
        _error(f"malformed guard result status: {status!r}")

    resource_identity = obj["resource_identity"]
    if not isinstance(resource_identity, str) or not RESOURCE_IDENTITY_RE.match(resource_identity):
        _error(f"malformed guard result resource_identity: {resource_identity!r}")

    evidence_digest = obj["evidence_digest"]
    if not isinstance(evidence_digest, str) or not EVIDENCE_DIGEST_RE.match(evidence_digest):
        _error(f"malformed guard result evidence_digest: {evidence_digest!r}")

    summary_code = obj["summary_code"]
    if not isinstance(summary_code, str) or not SUMMARY_CODE_RE.match(summary_code):
        _error(f"malformed guard result summary_code: {summary_code!r}")


def validate_failure_object(obj):
    if not isinstance(obj, dict) or set(obj.keys()) != set(FAILURE_KEYS):
        _error(f"failure object must contain exactly {FAILURE_KEYS}: {obj!r}")

    code = obj["code"]
    if not isinstance(code, str) or code not in CLOSED_FAILURE_CODES:
        _error(f"unknown foundation failure code: {code!r}")

    expected_scope = obj["expected_scope"]
    if not isinstance(expected_scope, str) or not SCOPE_RE.match(expected_scope):
        _error(f"malformed failure expected_scope: {expected_scope!r}")

    guard_index = obj["guard_index"]
    if guard_index is not None and not isinstance(guard_index, int):
        _error(f"failure guard_index must be an integer or null: {guard_index!r}")

    result_index = obj["result_index"]
    if result_index is not None and not isinstance(result_index, int):
        _error(f"failure result_index must be an integer or null: {result_index!r}")

    wrapper_status = obj["wrapper_status"]
    if wrapper_status is not None and not isinstance(wrapper_status, int):
        _error(f"failure wrapper_status must be an integer or null: {wrapper_status!r}")


def _validate_common_operation_fields(payload, *, requested_keys):
    if not isinstance(payload, dict):
        _error("evidence document must be a JSON object")
    actual_keys = set(payload.keys())
    expected_keys = set(requested_keys)
    if actual_keys != expected_keys:
        missing = expected_keys - actual_keys
        unknown = actual_keys - expected_keys
        _error(f"evidence document key set mismatch (missing={sorted(missing)}, unknown={sorted(unknown)})")

    if payload["schema_version"] != SCHEMA_VERSION:
        _error(f"unsupported schema_version: {payload['schema_version']!r}")

    operation_id = payload["operation_id"]
    if not isinstance(operation_id, str) or not OPERATION_ID_RE.match(operation_id):
        _error(f"malformed operation_id: {operation_id!r}")

    environment = payload["environment"]
    if environment not in ("dev", "uat"):
        _error(f"environment must be dev or uat, got: {environment!r}")

    account_id = payload["account_id"]
    if not isinstance(account_id, str) or not ACCOUNT_ID_RE.match(account_id):
        _error(f"malformed account_id: {account_id!r}")

    requested_scope = payload["requested_scope"]
    if not isinstance(requested_scope, str) or not SCOPE_RE.match(requested_scope):
        _error(f"malformed requested_scope: {requested_scope!r}")

    resolved_scopes = payload["resolved_scopes"]
    if not isinstance(resolved_scopes, list) or not resolved_scopes:
        _error("resolved_scopes must be a non-empty JSON array")
    for scope in resolved_scopes:
        if not isinstance(scope, str) or not SCOPE_RE.match(scope):
            _error(f"malformed entry in resolved_scopes: {scope!r}")

    confirmation_artifact_sha256 = payload["confirmation_artifact_sha256"]
    if not isinstance(confirmation_artifact_sha256, str) or not re.match(r"^[0-9a-f]{64}$", confirmation_artifact_sha256):
        _error(f"malformed confirmation_artifact_sha256: {confirmation_artifact_sha256!r}")


def validate_all_pass_evidence_schema(payload):
    _validate_common_operation_fields(payload, requested_keys=EVIDENCE_KEYS)

    guard_results = payload["guard_results"]
    if not isinstance(guard_results, list) or not guard_results:
        _error("guard_results must be a non-empty JSON array")
    for result in guard_results:
        validate_guard_result_object(result)
        if result["status"] != "PASS":
            _error("all-pass evidence must contain only PASS guard results")

    if [result["scope"] for result in guard_results] != list(payload["resolved_scopes"]):
        _error("guard_results scopes must exactly match resolved_scopes in the same order")

    created_epoch = _require_timestamp(payload["created_at"], "created_at")
    expires_epoch = _require_timestamp(payload["expires_at"], "expires_at")
    if expires_epoch <= created_epoch:
        _error("expires_at must be after created_at")


def validate_guard_failure_schema(payload):
    _validate_common_operation_fields(payload, requested_keys=GUARD_FAILURE_KEYS)

    received_results = payload["received_results"]
    if not isinstance(received_results, list):
        _error("received_results must be a JSON array")
    for result in received_results:
        validate_guard_result_object(result)

    validate_failure_object(payload["failure"])
    _require_timestamp(payload["created_at"], "created_at")


def build_all_pass_evidence_payload(
    *,
    operation_id,
    environment,
    account_id,
    requested_scope,
    resolved_scopes,
    guard_results,
    created_at,
    expires_at,
    confirmation_artifact_sha256,
):
    payload = {
        "schema_version": SCHEMA_VERSION,
        "operation_id": operation_id,
        "environment": environment,
        "account_id": account_id,
        "requested_scope": requested_scope,
        "resolved_scopes": list(resolved_scopes),
        "guard_results": list(guard_results),
        "created_at": created_at,
        "expires_at": expires_at,
        "confirmation_artifact_sha256": confirmation_artifact_sha256,
    }
    validate_all_pass_evidence_schema(payload)
    return payload


def build_guard_failure_payload(
    *,
    operation_id,
    environment,
    account_id,
    requested_scope,
    resolved_scopes,
    received_results,
    failure,
    created_at,
    confirmation_artifact_sha256,
):
    payload = {
        "schema_version": SCHEMA_VERSION,
        "operation_id": operation_id,
        "environment": environment,
        "account_id": account_id,
        "requested_scope": requested_scope,
        "resolved_scopes": list(resolved_scopes),
        "received_results": list(received_results),
        "failure": dict(failure),
        "created_at": created_at,
        "confirmation_artifact_sha256": confirmation_artifact_sha256,
    }
    validate_guard_failure_schema(payload)
    return payload


# ---------------------------------------------------------------------------
# Safe, exclusive, mode-0600, no-follow file operations
# ---------------------------------------------------------------------------


def _open_nofollow(path, flags, mode=0):
    open_flags = flags
    if hasattr(os, "O_NOFOLLOW"):
        open_flags |= os.O_NOFOLLOW
    if mode:
        return os.open(path, open_flags, mode)
    return os.open(path, open_flags)


def _read_validated_regular_file(path):
    try:
        fd = _open_nofollow(path, os.O_RDONLY)
    except OSError as exc:
        _error(f"unable to open evidence document {path}: {exc}")
    try:
        file_stat = os.fstat(fd)
        if stat.S_ISLNK(file_stat.st_mode):
            _error(f"evidence document must not be a symlink: {path}")
        if not stat.S_ISREG(file_stat.st_mode):
            _error(f"evidence document must be a regular file: {path}")
        if stat.S_IMODE(file_stat.st_mode) != 0o600:
            _error(
                f"evidence document must have mode 0600, got "
                f"{oct(stat.S_IMODE(file_stat.st_mode))}: {path}"
            )
        raw = b""
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            raw += chunk
        return raw, file_stat
    finally:
        os.close(fd)


def _create_exclusive(path, data):
    path = str(path)
    parent = os.path.dirname(path)
    if parent and os.path.islink(parent):
        _error(f"evidence directory must not be a symlink: {parent}")

    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    fd = _open_nofollow(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, data)
    finally:
        os.close(fd)

    reread, _file_stat = _read_validated_regular_file(path)
    if reread != data:
        _error(f"re-read evidence document did not match written bytes: {path}")
    return data


def write_all_pass_evidence(path, payload):
    validate_all_pass_evidence_schema(payload)
    return _create_exclusive(path, canonical_bytes(payload))


def write_guard_failure(path, payload):
    validate_guard_failure_schema(payload)
    return _create_exclusive(path, canonical_bytes(payload))


def read_evidence_document(path, *, kind):
    raw, _file_stat = _read_validated_regular_file(path)
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        _error(f"evidence document is not ASCII: {exc}")
    if text.count("\n") != 1 or not text.endswith("\n"):
        _error("evidence document must contain exactly one trailing newline")
    try:
        payload = json.loads(text, object_pairs_hook=_duplicate_key_hook)
    except ValueError as exc:
        _error(f"evidence document is not valid JSON: {exc}")

    if kind == "all-pass":
        validate_all_pass_evidence_schema(payload)
    elif kind == "guard-failure":
        validate_guard_failure_schema(payload)
    else:
        _error(f"unknown evidence document kind: {kind}")

    if canonical_bytes(payload) != raw:
        _error("evidence document bytes are not canonical")

    return payload, raw


# ---------------------------------------------------------------------------
# Append-only lifecycle status sidecars
# ---------------------------------------------------------------------------


def status_sidecar_path(evidence_dir, operation_id, status_name):
    return os.path.join(str(evidence_dir), f"pre-destroy-guards.{operation_id}.status.{status_name}.json")


def build_status_payload(*, operation_id, evidence_sha256, status_name, recorded_at, failure_code=None):
    if not isinstance(operation_id, str) or not OPERATION_ID_RE.match(operation_id):
        _error(f"malformed operation_id: {operation_id!r}")
    if not isinstance(evidence_sha256, str) or not re.match(r"^[0-9a-f]{64}$", evidence_sha256):
        _error(f"malformed evidence_sha256: {evidence_sha256!r}")
    _require_timestamp(recorded_at, "recorded_at")

    payload = {
        "schema_version": SCHEMA_VERSION,
        "operation_id": operation_id,
        "evidence_sha256": evidence_sha256,
        "status": status_name,
        "recorded_at": recorded_at,
    }
    if status_name == "failure":
        if not failure_code or failure_code not in CLOSED_FAILURE_CODES:
            _error(f"failure status sidecar requires a closed foundation failure code, got: {failure_code!r}")
        payload["failure_code"] = failure_code
    elif failure_code is not None:
        _error(f"only a failure status sidecar may carry a failure_code, got status: {status_name!r}")
    return payload


def write_status_sidecar(evidence_dir, operation_id, status_name, *, evidence_sha256, recorded_at, failure_code=None):
    """Append-only: never replaces an existing sidecar of the same name.
    Written by same-directory temporary file plus atomic no-replace
    "publish" (hard-link then unlink the temp name), so a partially written
    file is never visible under the final name."""
    if status_name not in ("consumed", "success", "failure"):
        _error(f"unknown status sidecar name: {status_name!r}")

    payload = build_status_payload(
        operation_id=operation_id,
        evidence_sha256=evidence_sha256,
        status_name=status_name,
        recorded_at=recorded_at,
        failure_code=failure_code,
    )
    data = canonical_bytes(payload)
    final_path = status_sidecar_path(evidence_dir, operation_id, status_name)

    if os.path.lexists(final_path):
        _error(f"status sidecar already exists (append-only violation): {final_path}")

    temp_path = f"{final_path}.tmp-{os.getpid()}"
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    fd = _open_nofollow(temp_path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, data)
    finally:
        os.close(fd)

    try:
        os.link(temp_path, final_path)
    except OSError as exc:
        os.remove(temp_path)
        _error(f"unable to publish status sidecar {final_path}: {exc}")
    os.remove(temp_path)

    reread, _file_stat = _read_validated_regular_file(final_path)
    if reread != data:
        _error(f"re-read status sidecar did not match written bytes: {final_path}")
    return final_path


def read_status_sidecar(path, *, expected_status=None):
    """No-follow, mode/regular-validated, duplicate-key-rejecting,
    canonical-byte-verified read of a status sidecar. Validates the closed
    schema (including the conditional `failure_code` key) and, when given,
    that the payload's own `status` field equals `expected_status`. Returns
    (payload, raw_bytes)."""
    raw, _file_stat = _read_validated_regular_file(path)
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        _error(f"status sidecar is not ASCII: {exc}")
    if text.count("\n") != 1 or not text.endswith("\n"):
        _error("status sidecar must contain exactly one trailing newline")
    try:
        payload = json.loads(text, object_pairs_hook=_duplicate_key_hook)
    except ValueError as exc:
        _error(f"status sidecar is not valid JSON: {exc}")

    if not isinstance(payload, dict):
        _error("status sidecar must be a JSON object")

    status_name = payload.get("status")
    expected_keys = set(STATUS_SIDECAR_KEYS_COMMON)
    if status_name == "failure":
        expected_keys = expected_keys | {"failure_code"}
    actual_keys = set(payload.keys())
    if actual_keys != expected_keys:
        missing = expected_keys - actual_keys
        unknown = actual_keys - expected_keys
        _error(f"status sidecar key set mismatch (missing={sorted(missing)}, unknown={sorted(unknown)})")

    if payload["schema_version"] != SCHEMA_VERSION:
        _error(f"unsupported schema_version: {payload['schema_version']!r}")

    operation_id = payload["operation_id"]
    if not isinstance(operation_id, str) or not OPERATION_ID_RE.match(operation_id):
        _error(f"malformed operation_id: {operation_id!r}")

    evidence_sha256 = payload["evidence_sha256"]
    if not isinstance(evidence_sha256, str) or not re.match(r"^[0-9a-f]{64}$", evidence_sha256):
        _error(f"malformed evidence_sha256: {evidence_sha256!r}")

    if status_name not in ("consumed", "success", "failure"):
        _error(f"malformed status: {status_name!r}")
    if expected_status is not None and status_name != expected_status:
        _error(f"status sidecar status {status_name!r} does not match expected {expected_status!r}")

    _require_timestamp(payload["recorded_at"], "recorded_at")

    if status_name == "failure":
        failure_code = payload["failure_code"]
        if not isinstance(failure_code, str) or failure_code not in CLOSED_FAILURE_CODES:
            _error(f"unknown foundation failure code: {failure_code!r}")

    if canonical_bytes(payload) != raw:
        _error("status sidecar bytes are not canonical")

    return payload, raw


# ---------------------------------------------------------------------------
# Retention and cleanup
# ---------------------------------------------------------------------------


def _terminal_status_paths(evidence_dir, operation_id):
    return {
        name: status_sidecar_path(evidence_dir, operation_id, name)
        for name in ("consumed", "success", "failure")
    }


def is_operation_retention_eligible(evidence_dir, operation_id, *, now_epoch, minimum_days=MINIMUM_RETENTION_DAYS):
    """An operation set is eligible for cleanup only once a terminal status
    (success or failure) is at least `minimum_days` old, or, for an
    evidence record that was never even consumed (no status sidecar of any
    kind exists), only once its own expiry is at least `minimum_days` old.

    Every status sidecar considered here is re-validated against its own
    closed schema and cross-bound to this exact operation (`operation_id`)
    and this exact evidence document (`evidence_sha256` must equal a fresh
    digest of the evidence bytes actually on disk) before its timestamp is
    trusted. A `consumed` sidecar with no terminal `success`/`failure`
    sidecar is a partial (in-flight or crashed) operation, not an
    unconsumed one, and is never eligible regardless of age. A terminal
    `success`/`failure` sidecar with no matching `consumed` sidecar is
    likewise treated as a tampered/partial set. Symlinks, unknown files,
    invalid modes, schema violations, digest mismatches, or a missing
    terminal status all fail closed (not eligible) and are retained for
    operator review."""
    evidence_path = os.path.join(str(evidence_dir), f"pre-destroy-guards.{operation_id}.json")
    if not os.path.lexists(evidence_path):
        return False

    try:
        payload, raw = read_evidence_document(evidence_path, kind="all-pass")
    except DestroyEvidenceError:
        return False

    import hashlib

    evidence_digest_hex = hashlib.sha256(raw).hexdigest()

    def _validated_sidecar_epoch(status_name):
        candidate = status_sidecar_path(evidence_dir, operation_id, status_name)
        if not os.path.lexists(candidate):
            return None, False
        try:
            status_payload, _raw = read_status_sidecar(candidate, expected_status=status_name)
        except DestroyEvidenceError:
            return None, True
        if status_payload["operation_id"] != operation_id:
            return None, True
        if status_payload["evidence_sha256"] != evidence_digest_hex:
            return None, True
        file_stat = os.lstat(candidate)
        return file_stat.st_mtime, False

    consumed_epoch, consumed_invalid = _validated_sidecar_epoch("consumed")
    if consumed_invalid:
        return False

    terminal_epoch = None
    for status_name in ("success", "failure"):
        epoch, invalid = _validated_sidecar_epoch(status_name)
        if invalid:
            return False
        if epoch is not None:
            terminal_epoch = epoch
            break

    if terminal_epoch is not None:
        # A terminal status is only ever written after consumption; a
        # terminal sidecar without a validated consumed sidecar is a
        # tampered or otherwise partial set and fails closed.
        if consumed_epoch is None:
            return False
        return (now_epoch - terminal_epoch) >= minimum_days * 86400

    if consumed_epoch is not None:
        # Consumed but never reached a terminal status: a partial
        # (in-flight or crashed) operation, not an unconsumed one. Never
        # eligible for automatic cleanup regardless of age.
        return False

    expires_epoch = _to_epoch(payload["expires_at"])
    if now_epoch - expires_epoch < minimum_days * 86400:
        return False
    return True


def cleanup_expired_operation(evidence_dir, operation_id, *, now_epoch, minimum_days=MINIMUM_RETENTION_DAYS):
    if not is_operation_retention_eligible(
        evidence_dir, operation_id, now_epoch=now_epoch, minimum_days=minimum_days
    ):
        return False

    evidence_path = os.path.join(str(evidence_dir), f"pre-destroy-guards.{operation_id}.json")
    removed_any = False
    if os.path.lexists(evidence_path):
        os.remove(evidence_path)
        removed_any = True
    for status_path in _terminal_status_paths(evidence_dir, operation_id).values():
        if os.path.lexists(status_path):
            os.remove(status_path)
            removed_any = True
    return removed_any


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _cli_write_evidence(args):
    payload = build_all_pass_evidence_payload(
        operation_id=args.operation_id,
        environment=args.environment,
        account_id=args.account_id,
        requested_scope=args.requested_scope,
        resolved_scopes=args.resolved_scope,
        guard_results=json.loads(args.guard_results_json),
        created_at=args.created_at,
        expires_at=args.expires_at,
        confirmation_artifact_sha256=args.confirmation_artifact_sha256,
    )
    write_all_pass_evidence(args.path, payload)
    return 0


def _cli_write_guard_failure(args):
    payload = build_guard_failure_payload(
        operation_id=args.operation_id,
        environment=args.environment,
        account_id=args.account_id,
        requested_scope=args.requested_scope,
        resolved_scopes=args.resolved_scope,
        received_results=json.loads(args.received_results_json),
        failure=json.loads(args.failure_json),
        created_at=args.created_at,
        confirmation_artifact_sha256=args.confirmation_artifact_sha256,
    )
    write_guard_failure(args.path, payload)
    return 0


def _cli_write_status(args):
    path = write_status_sidecar(
        args.evidence_dir,
        args.operation_id,
        args.status,
        evidence_sha256=args.evidence_sha256,
        recorded_at=args.recorded_at,
        failure_code=args.failure_code,
    )
    sys.stdout.write(path + "\n")
    return 0


def _cli_cleanup(args):
    removed = cleanup_expired_operation(
        args.evidence_dir, args.operation_id, now_epoch=_to_epoch(args.now)
    )
    sys.stdout.write(("removed\n" if removed else "retained\n"))
    return 0


def _cli_digest(args):
    raw, _file_stat = _read_validated_regular_file(args.path)
    import hashlib

    sys.stdout.write(f"sha256:{hashlib.sha256(raw).hexdigest()}\n")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    write_evidence_parser = subparsers.add_parser("write-evidence")
    write_evidence_parser.add_argument("--path", required=True)
    write_evidence_parser.add_argument("--operation-id", required=True)
    write_evidence_parser.add_argument("--environment", required=True)
    write_evidence_parser.add_argument("--account-id", required=True)
    write_evidence_parser.add_argument("--requested-scope", required=True)
    write_evidence_parser.add_argument("--resolved-scope", action="append", default=[])
    write_evidence_parser.add_argument("--guard-results-json", required=True)
    write_evidence_parser.add_argument("--created-at", required=True)
    write_evidence_parser.add_argument("--expires-at", required=True)
    write_evidence_parser.add_argument("--confirmation-artifact-sha256", required=True)
    write_evidence_parser.set_defaults(func=_cli_write_evidence)

    write_failure_parser = subparsers.add_parser("write-guard-failure")
    write_failure_parser.add_argument("--path", required=True)
    write_failure_parser.add_argument("--operation-id", required=True)
    write_failure_parser.add_argument("--environment", required=True)
    write_failure_parser.add_argument("--account-id", required=True)
    write_failure_parser.add_argument("--requested-scope", required=True)
    write_failure_parser.add_argument("--resolved-scope", action="append", default=[])
    write_failure_parser.add_argument("--received-results-json", required=True)
    write_failure_parser.add_argument("--failure-json", required=True)
    write_failure_parser.add_argument("--created-at", required=True)
    write_failure_parser.add_argument("--confirmation-artifact-sha256", required=True)
    write_failure_parser.set_defaults(func=_cli_write_guard_failure)

    write_status_parser = subparsers.add_parser("write-status")
    write_status_parser.add_argument("--evidence-dir", required=True)
    write_status_parser.add_argument("--operation-id", required=True)
    write_status_parser.add_argument("--status", required=True, choices=("consumed", "success", "failure"))
    write_status_parser.add_argument("--evidence-sha256", required=True)
    write_status_parser.add_argument("--recorded-at", required=True)
    write_status_parser.add_argument("--failure-code", default=None)
    write_status_parser.set_defaults(func=_cli_write_status)

    cleanup_parser = subparsers.add_parser("cleanup")
    cleanup_parser.add_argument("--evidence-dir", required=True)
    cleanup_parser.add_argument("--operation-id", required=True)
    cleanup_parser.add_argument("--now", required=True)
    cleanup_parser.set_defaults(func=_cli_cleanup)

    digest_parser = subparsers.add_parser("digest")
    digest_parser.add_argument("--path", required=True)
    digest_parser.set_defaults(func=_cli_digest)

    parsed = parser.parse_args(argv)
    try:
        return parsed.func(parsed)
    except DestroyEvidenceError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
