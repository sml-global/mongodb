#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Deprecated: PostgreSQL now runs from unified root platform-prerequisites/terraform/dev."
echo "Running scripts/run-platform-prereq.sh so MongoDB prerequisites and PostgreSQL are planned together."

exec "$ROOT_DIR/scripts/run-platform-prereq.sh"