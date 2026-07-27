#!/usr/bin/env python3
"""Foundation-only destroy confirmation-artifact implementation.

"Task 4: Add Explicit Unified Entrypoints Without Changing Legacy Dev
Behavior" in
docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md
owns this file. It is a standard-library-only implementation (no third-party
imports) used exclusively by scripts/lib/orchestrator.sh through the small
CLI at the bottom of this file. It is never a public operator entrypoint and
is never sourced/imported by a package fragment.

Responsibilities:
  - Canonical-byte serialization of the closed confirmation-artifact schema.
  - Exclusive (O_CREAT | O_EXCL), mode-0600, non-symlink creation.
  - No-follow descriptor reads so a path swap between check and use cannot
    change the object being validated.
  - Duplicate-key rejection on read (`object_pairs_hook`).
  - Full schema/type/value validation, including the immutable 15-minute
    artifact lifetime and the colon-delimited confirmation-value grammar.
  - Binding the artifact to the current request (environment, account,
    requested scope, resolved scope order, confirmation set) before the
    orchestrator may proceed.
  - Atomic, identity-revalidated "consumed" rename with no path-swap window.

Canonical bytes are produced by
`json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)`
plus exactly one trailing `\n`, encoded as ASCII (the schema never requires
non-ASCII content).
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
LIFETIME_SECONDS = 15 * 60

REQUIRED_KEYS = (
    "schema_version",
    "operation_id",
    "created_at",
    "expires_at",
    "environment",
    "account_id",
    "requested_scope",
    "resolved_scopes",
    "confirmations",
)

TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
OPERATION_ID_RE = re.compile(r"^[0-9a-f]{16,64}$")
SCOPE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
ACCOUNT_ID_RE = re.compile(r"^[0-9]{12}$")
CONFIRMATION_COMPONENT_RE = re.compile(r"^[A-Za-z0-9._/=+-]+$")


class ConfirmationArtifactError(Exception):
    """Raised for every schema, canonical-byte, safety, or binding failure."""


def _error(message):
    raise ConfirmationArtifactError(message)


def _duplicate_key_hook(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            _error(f"duplicate key in confirmation artifact: {key}")
        seen[key] = value
    return seen


def canonical_bytes(payload):
    """Exact canonical-byte algorithm this schema uses everywhere."""
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return (text + "\n").encode("ascii")


def _to_epoch(value):
    import calendar

    struct_time = time.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    return calendar.timegm(struct_time)


def format_timestamp(epoch_seconds):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch_seconds))


def validate_confirmation_value(value):
    if not isinstance(value, str):
        _error("confirmation value must be a string")
    parts = value.split(":")
    if len(parts) != 6 or parts[0] != "destroy":
        _error(f"malformed confirmation value: {value}")
    for component in parts[1:]:
        if not component or not CONFIRMATION_COMPONENT_RE.match(component):
            _error(f"malformed confirmation value component in: {value}")


def validate_schema(payload):
    if not isinstance(payload, dict):
        _error("confirmation artifact must be a JSON object")

    actual_keys = set(payload.keys())
    expected_keys = set(REQUIRED_KEYS)
    if actual_keys != expected_keys:
        missing = expected_keys - actual_keys
        unknown = actual_keys - expected_keys
        _error(f"confirmation artifact key set mismatch (missing={sorted(missing)}, unknown={sorted(unknown)})")

    if payload["schema_version"] != SCHEMA_VERSION:
        _error(f"unsupported schema_version: {payload['schema_version']!r}")

    operation_id = payload["operation_id"]
    if not isinstance(operation_id, str) or not OPERATION_ID_RE.match(operation_id):
        _error(f"malformed operation_id: {operation_id!r}")

    created_epoch = _parse_timestamp_field(payload["created_at"], "created_at")
    expires_epoch = _parse_timestamp_field(payload["expires_at"], "expires_at")
    if expires_epoch - created_epoch != LIFETIME_SECONDS:
        _error(
            "expires_at must be exactly the immutable 15-minute lifetime "
            f"after created_at (got {expires_epoch - created_epoch}s)"
        )

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

    confirmations = payload["confirmations"]
    if not isinstance(confirmations, list):
        _error("confirmations must be a JSON array")
    for value in confirmations:
        validate_confirmation_value(value)


def _parse_timestamp_field(value, field_name):
    if not isinstance(value, str) or not TIMESTAMP_RE.match(value):
        _error(f"{field_name} must be an ISO-8601 UTC timestamp of the form YYYY-MM-DDTHH:MM:SSZ")
    try:
        return _to_epoch(value)
    except ValueError:
        _error(f"{field_name} is not a valid calendar timestamp: {value}")


def build_payload(
    *,
    operation_id,
    created_at,
    expires_at,
    environment,
    account_id,
    requested_scope,
    resolved_scopes,
    confirmations,
):
    payload = {
        "schema_version": SCHEMA_VERSION,
        "operation_id": operation_id,
        "created_at": created_at,
        "expires_at": expires_at,
        "environment": environment,
        "account_id": account_id,
        "requested_scope": requested_scope,
        "resolved_scopes": list(resolved_scopes),
        "confirmations": list(confirmations),
    }
    validate_schema(payload)
    return payload


def _open_nofollow(path, flags, mode=0):
    open_flags = flags
    if hasattr(os, "O_NOFOLLOW"):
        open_flags |= os.O_NOFOLLOW
    if mode:
        return os.open(path, open_flags, mode)
    return os.open(path, open_flags)


def _read_validated_regular_file(path):
    """Open path with O_NOFOLLOW, require a foundation-owned regular file
    with mode exactly 0600, and return (raw_bytes, stat_result)."""
    try:
        fd = _open_nofollow(path, os.O_RDONLY)
    except OSError as exc:
        _error(f"unable to open confirmation artifact {path}: {exc}")
    try:
        file_stat = os.fstat(fd)
        if stat.S_ISLNK(file_stat.st_mode):
            _error(f"confirmation artifact must not be a symlink: {path}")
        if not stat.S_ISREG(file_stat.st_mode):
            _error(f"confirmation artifact must be a regular file: {path}")
        if stat.S_IMODE(file_stat.st_mode) != 0o600:
            _error(
                f"confirmation artifact must have mode 0600, got "
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


def read_confirmation_artifact(path):
    """No-follow, mode/regular-validated, duplicate-key-rejecting,
    canonical-byte-verified read. Returns (payload, raw_bytes)."""
    raw, _file_stat = _read_validated_regular_file(path)

    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        _error(f"confirmation artifact is not ASCII: {exc}")

    if text.count("\n") != 1 or not text.endswith("\n"):
        _error("confirmation artifact must contain exactly one trailing newline")

    try:
        payload = json.loads(text, object_pairs_hook=_duplicate_key_hook)
    except ValueError as exc:
        _error(f"confirmation artifact is not valid JSON: {exc}")

    validate_schema(payload)

    if canonical_bytes(payload) != raw:
        _error("confirmation artifact bytes are not canonical")

    return payload, raw


def create_artifact(path, payload):
    """Exclusively create the artifact (never replaces a file, directory,
    or symlink), mode exactly 0600, then re-open and byte-for-byte verify."""
    validate_schema(payload)
    data = canonical_bytes(payload)

    path = str(path)
    parent = os.path.dirname(path)
    if parent and os.path.islink(parent):
        _error(f"confirmation artifact parent directory must not be a symlink: {parent}")

    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    fd = _open_nofollow(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, data)
    finally:
        os.close(fd)

    reread, _file_stat = _read_validated_regular_file(path)
    if reread != data:
        _error(f"re-read confirmation artifact did not match written bytes: {path}")
    return data


def sha256_hex_of_bytes(raw_bytes):
    import hashlib

    return hashlib.sha256(raw_bytes).hexdigest()


def sha256_digest_of_bytes(raw_bytes):
    return f"sha256:{sha256_hex_of_bytes(raw_bytes)}"


def validate_against_request(
    payload,
    *,
    now_epoch,
    path_operation_id,
    environment,
    account_id,
    requested_scope,
    resolved_scopes,
    confirmations,
):
    """Bind an already schema-valid payload to the current request. Rejects
    stale, expired, replayed, cross-environment, cross-account, cross-scope,
    cross-operation, missing, extra, duplicate, reordered, or mismatched
    values before any handler runs."""
    if payload["operation_id"] != path_operation_id:
        _error(
            "confirmation artifact filename/operation_id disagreement: "
            f"filename={path_operation_id!r} payload={payload['operation_id']!r}"
        )

    created_epoch = _to_epoch(payload["created_at"])
    expires_epoch = _to_epoch(payload["expires_at"])

    if created_epoch > now_epoch:
        _error("confirmation artifact created_at is in the future")
    if now_epoch >= expires_epoch:
        _error("confirmation artifact has expired")

    if payload["environment"] != environment:
        _error(
            f"confirmation artifact environment {payload['environment']!r} "
            f"does not match the current request {environment!r}"
        )
    if payload["account_id"] != account_id:
        _error(
            f"confirmation artifact account_id {payload['account_id']!r} "
            f"does not match the current request {account_id!r}"
        )
    if payload["requested_scope"] != requested_scope:
        _error(
            f"confirmation artifact requested_scope {payload['requested_scope']!r} "
            f"does not match the current request {requested_scope!r}"
        )
    if list(payload["resolved_scopes"]) != list(resolved_scopes):
        _error("confirmation artifact resolved_scopes do not match the current resolved destroy order")
    if list(payload["confirmations"]) != list(confirmations):
        _error("confirmation artifact confirmations do not match the current required/CLI confirmation set")


def consume_artifact(path):
    """Atomically rename the still-open, revalidated artifact to
    '<path>.consumed' in the same directory. Verifies the consumed name
    still identifies the same file after rename; a mismatch is a consumed
    failure and never dispatches. Never renames a consumed path back."""
    path = str(path)
    raw, before_stat = _read_validated_regular_file(path)
    consumed_path = f"{path}.consumed"

    if os.path.lexists(consumed_path):
        _error(f"consumed confirmation artifact path already exists: {consumed_path}")

    try:
        os.rename(path, consumed_path)
    except OSError as exc:
        _error(f"unable to atomically consume confirmation artifact: {exc}")

    after_stat = os.lstat(consumed_path)
    if (after_stat.st_dev, after_stat.st_ino) != (before_stat.st_dev, before_stat.st_ino):
        _error("consumed confirmation artifact identity changed across rename")
    if not stat.S_ISREG(after_stat.st_mode) or stat.S_IMODE(after_stat.st_mode) != 0o600:
        _error("consumed confirmation artifact lost its regular-file/mode-0600 identity")

    return consumed_path, raw


def cleanup_expired_artifact(path, *, now_epoch):
    """Remove path (unconsumed) or '<path>.consumed' only if it is a
    foundation-owned, mode-0600, non-symlink regular file whose expiry has
    passed. Returns True if something was removed."""
    removed = False
    for candidate in (str(path), f"{path}.consumed"):
        if not os.path.lexists(candidate):
            continue
        try:
            raw, _file_stat = _read_validated_regular_file(candidate)
            payload = json.loads(raw.decode("ascii"), object_pairs_hook=_duplicate_key_hook)
            validate_schema(payload)
            expires_epoch = _to_epoch(payload["expires_at"])
        except ConfirmationArtifactError:
            continue
        if now_epoch <= expires_epoch:
            continue
        os.remove(candidate)
        removed = True
    return removed


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _cli_create(args):
    payload = build_payload(
        operation_id=args.operation_id,
        created_at=args.created_at,
        expires_at=args.expires_at,
        environment=args.environment,
        account_id=args.account_id,
        requested_scope=args.requested_scope,
        resolved_scopes=args.resolved_scope,
        confirmations=args.confirmation,
    )
    create_artifact(args.path, payload)
    return 0


def _cli_fields(args):
    payload, _raw = read_confirmation_artifact(args.path)
    sys.stdout.write(f"operation_id={payload['operation_id']}\n")
    sys.stdout.write(f"created_at={payload['created_at']}\n")
    sys.stdout.write(f"expires_at={payload['expires_at']}\n")
    sys.stdout.write(f"environment={payload['environment']}\n")
    sys.stdout.write(f"account_id={payload['account_id']}\n")
    sys.stdout.write(f"requested_scope={payload['requested_scope']}\n")
    sys.stdout.write(f"resolved_scopes={','.join(payload['resolved_scopes'])}\n")
    sys.stdout.write(f"confirmations={','.join(payload['confirmations'])}\n")
    return 0


def _cli_validate(args):
    payload, raw = read_confirmation_artifact(args.path)
    validate_against_request(
        payload,
        now_epoch=_to_epoch(args.now),
        path_operation_id=args.operation_id,
        environment=args.environment,
        account_id=args.account_id,
        requested_scope=args.requested_scope,
        resolved_scopes=args.resolved_scope,
        confirmations=args.confirmation,
    )
    sys.stdout.write(sha256_digest_of_bytes(raw) + "\n")
    return 0


def _cli_consume(args):
    consumed_path, _raw = consume_artifact(args.path)
    sys.stdout.write(consumed_path + "\n")
    return 0


def _cli_cleanup(args):
    removed = cleanup_expired_artifact(args.path, now_epoch=_to_epoch(args.now))
    sys.stdout.write(("removed\n" if removed else "retained\n"))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create")
    create_parser.add_argument("--path", required=True)
    create_parser.add_argument("--operation-id", required=True)
    create_parser.add_argument("--created-at", required=True)
    create_parser.add_argument("--expires-at", required=True)
    create_parser.add_argument("--environment", required=True)
    create_parser.add_argument("--account-id", required=True)
    create_parser.add_argument("--requested-scope", required=True)
    create_parser.add_argument("--resolved-scope", action="append", default=[])
    create_parser.add_argument("--confirmation", action="append", default=[])
    create_parser.set_defaults(func=_cli_create)

    fields_parser = subparsers.add_parser("fields")
    fields_parser.add_argument("--path", required=True)
    fields_parser.set_defaults(func=_cli_fields)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--path", required=True)
    validate_parser.add_argument("--now", required=True)
    validate_parser.add_argument("--operation-id", required=True)
    validate_parser.add_argument("--environment", required=True)
    validate_parser.add_argument("--account-id", required=True)
    validate_parser.add_argument("--requested-scope", required=True)
    validate_parser.add_argument("--resolved-scope", action="append", default=[])
    validate_parser.add_argument("--confirmation", action="append", default=[])
    validate_parser.set_defaults(func=_cli_validate)

    consume_parser = subparsers.add_parser("consume")
    consume_parser.add_argument("--path", required=True)
    consume_parser.set_defaults(func=_cli_consume)

    cleanup_parser = subparsers.add_parser("cleanup")
    cleanup_parser.add_argument("--path", required=True)
    cleanup_parser.add_argument("--now", required=True)
    cleanup_parser.set_defaults(func=_cli_cleanup)

    parsed = parser.parse_args(argv)
    try:
        return parsed.func(parsed)
    except ConfirmationArtifactError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
