#!/usr/bin/env python3
"""Validate the canonical imported-code review matrix."""

import argparse
import posixpath
import re
import sys
from pathlib import Path


COLUMNS = ("ID", "Domain", "Source", "Target", "Disposition", "Evidence", "Status")
DOMAINS = ("FOUNDATION", "EKS", "DATA", "BOOMI", "DOCS")
DISPOSITIONS = ("KEEP", "REWRITE", "REPLACE", "REJECT")
STATUSES = ("PROPOSED", "REVIEWED", "VERIFIED")
ID_PATTERN = re.compile(r"^([A-Z]+)-([0-9]{4})$")
PLACEHOLDER_PATTERN = re.compile(r"<[^>]*>")
PLACEHOLDER_TOKEN_PATTERN = re.compile(r"(^|[^A-Za-z])(UNCLASSIFIED|TBD|TODO)([^A-Za-z]|$)", re.IGNORECASE)


def _cells(line):
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return None
    return [cell.strip() for cell in stripped[1:-1].split("|")]


def _is_separator(cells):
    return (
        cells is not None
        and len(cells) == len(COLUMNS)
        and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)
    )


def parse_matrix(path):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    canonical_tables = []
    malformed_headers = []
    structural_errors = []

    for index, line in enumerate(lines):
        cells = _cells(line)
        if cells is None or "ID" not in cells:
            continue

        if tuple(cells) != COLUMNS:
            malformed_headers.append(index + 1)
            continue

        if index + 1 >= len(lines) or not _is_separator(_cells(lines[index + 1])):
            structural_errors.append(
                f"canonical table at line {index + 1} has an invalid separator"
            )
            continue

        rows = []
        for row_index, row_line in enumerate(lines[index + 2 :], start=index + 3):
            row_cells = _cells(row_line)
            if row_cells is None:
                if "|" in row_line:
                    structural_errors.append(
                        f"canonical table row at line {row_index} is not a complete "
                        "pipe-delimited row"
                    )
                    continue
                break
            if _is_separator(row_cells):
                structural_errors.append(
                    f"canonical table row at line {row_index} is an unexpected separator"
                )
                continue
            if len(row_cells) != len(COLUMNS):
                structural_errors.append(
                    f"canonical table row at line {row_index} has an invalid column count"
                )
                continue
            rows.append(dict(zip(COLUMNS, row_cells)))
        canonical_tables.append(rows)

    errors = []
    if malformed_headers:
        locations = ", ".join(str(line) for line in malformed_headers)
        errors.append(
            f"matrix header does not match the canonical schema at line(s) {locations}"
        )
    if len(canonical_tables) != 1:
        errors.append(
            f"document must contain exactly one canonical table; found {len(canonical_tables)}"
        )
    errors.extend(structural_errors)
    if errors:
        raise ValueError("Imported-code matrix parse failed:\n" + "\n".join(errors))
    return canonical_tables[0]


def _is_concrete(value):
    normalized = value.strip()
    return (
        bool(normalized)
        and PLACEHOLDER_TOKEN_PATTERN.search(normalized) is None
        and PLACEHOLDER_PATTERN.search(normalized) is None
    )


def _is_portable_identifier(value):
    path, separator, fragment = value.partition("#")
    return (
        bool(path)
        and not path.startswith("/")
        and not any(character.isspace() for character in value)
        and "\\" not in value
        and posixpath.normpath(path) == path
        and (not separator or bool(fragment))
    )


def validate_rows(rows):
    errors = []
    seen_ids = set()
    seen_sources = set()
    seen_decisions = set()
    next_number = {domain: 1 for domain in DOMAINS}

    if not rows:
        errors.append("matrix must contain at least one row")

    for row_number, row in enumerate(rows, start=1):
        if set(row) != set(COLUMNS):
            missing = sorted(set(COLUMNS) - set(row))
            unknown = sorted(set(row) - set(COLUMNS))
            errors.append(
                f"row {row_number}: schema mismatch; missing={missing}, unknown={unknown}"
            )

        identifier = row.get("ID", "")
        domain = row.get("Domain", "")
        match = ID_PATTERN.fullmatch(identifier)

        if domain not in DOMAINS:
            errors.append(f"row {row_number}: unknown domain {domain!r}")
        if not match:
            errors.append(f"row {row_number}: invalid ID {identifier!r}")
        elif match.group(1) != domain:
            errors.append(f"row {row_number}: ID {identifier!r} does not match domain {domain!r}")
        elif domain in next_number:
            expected = f"{domain}-{next_number[domain]:04d}"
            if identifier != expected:
                errors.append(f"row {row_number}: expected sequential ID {expected}, found {identifier}")
            next_number[domain] += 1

        if identifier in seen_ids:
            errors.append(f"row {row_number}: ID {identifier!r} must be unique")
        seen_ids.add(identifier)

        disposition = row.get("Disposition", "")
        status = row.get("Status", "")
        if disposition not in DISPOSITIONS:
            errors.append(f"row {row_number}: unknown disposition {disposition!r}")
        if status not in STATUSES:
            errors.append(f"row {row_number}: unknown status {status!r}")

        for field in ("Source", "Target", "Evidence"):
            if not _is_concrete(row.get(field, "")):
                errors.append(f"row {row_number}: {field} must be concrete")

        for field in ("Source", "Target", "Evidence"):
            value = row.get(field, "")
            if _is_concrete(value) and not _is_portable_identifier(value):
                kind = "reference" if field == "Evidence" else "identifier"
                errors.append(
                    f"row {row_number}: {field} must be a portable repository-relative "
                    f"or explicit external {kind}"
                )

        source = row.get("Source", "")
        if source in seen_sources:
            errors.append(f"row {row_number}: duplicate source candidate {source!r}")
        seen_sources.add(source)

        decision = (source, row.get("Target", ""))
        if decision in seen_decisions:
            errors.append(
                f"row {row_number}: duplicate source/target decision "
                f"{decision[0]!r} -> {decision[1]!r}"
            )
        seen_decisions.add(decision)

    if errors:
        raise ValueError("Imported-code matrix validation failed:\n" + "\n".join(errors))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix", type=Path)
    arguments = parser.parse_args(argv)

    try:
        rows = parse_matrix(arguments.matrix)
        validate_rows(rows)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    print(f"Validated {len(rows)} imported-code review row(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())