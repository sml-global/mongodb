# Teardown Safety & Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone on-demand database export tool, a hard confirmation gate + opt-in `--export-first` flag to the legacy destroy script, and the two missing recovery guides (Dev/SIT CNPG restore, orphaned EBS volume recovery) — all reviewable scripts/docs, no live infrastructure execution.

**Architecture:** One new standalone script (`scripts/export-database-snapshot.sh`) wraps each database's native on-demand backup mechanism (PBM `--wait`, CNPG `Backup` CR + poll). `scripts/legacy/dev/destroy.sh` gets a typed-confirmation gate and an opt-in flag that calls the new script before teardown. Two doc sections close the recovery-documentation gap.

**Tech Stack:** bash (`scripts/export-database-snapshot.sh`, `scripts/legacy/dev/destroy.sh`), `pbm` CLI (MongoDB), CNPG `Backup` custom resource (PostgreSQL), Python `unittest` (structural tests only, mocked `kubectl`/`terraform`/`aws` binaries — no live execution), Markdown docs.

## Global Constraints

- No `kubectl`, `terraform`, `pbm`, or `aws` command may be executed against a real cluster/account anywhere in this plan's verification steps — every test uses the existing mocked-binary pattern from `tests/environment_orchestration/test_entrypoints.py` (`_BaseFixture`, `_write_executable`, `run_clean`).
- The typed confirmation phrase is the literal, case-sensitive word `DESTROY`. Any other stdin input (including empty) must abort with a non-zero exit code and zero destructive calls logged.
- `--auto-approve` bypasses the confirmation prompt (preserving existing automation call sites); it does not imply `--export-first`.
- `--export-first` is opt-in only; omitting it preserves today's destroy behavior (apart from the new confirmation prompt).
- A failed export must abort the destroy run entirely — never proceed to teardown after a failed safety snapshot.

---

### Task 1: Standalone export tool — `scripts/export-database-snapshot.sh`

**Files:**
- Create: `scripts/export-database-snapshot.sh`
- Test: `tests/environment_orchestration/test_export_database_snapshot.py`

**Interfaces:**
- Produces: `scripts/export-database-snapshot.sh <mongodb|postgresql> [--wait-timeout-seconds N]`, exit 0 on a completed backup, non-zero on failure/timeout/unknown scope. Consumed by Task 2's `--export-first` wiring.

- [ ] **Step 1: Write the failing test**

```python
"""Structural tests for scripts/export-database-snapshot.sh: argument
parsing, per-database command sequencing, and exit-code behavior, using
mocked kubectl (no live cluster)."""
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

_KUBECTL_STUB_TEMPLATE = "#!/usr/bin/env bash\n{body}\n"


class ExportDatabaseSnapshotFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = pathlib.Path(self.temporary.name) / "bin"
        self.command_log = pathlib.Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)
        (self.root / "scripts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            REPO_ROOT / "scripts" / "export-database-snapshot.sh",
            self.root / "scripts" / "export-database-snapshot.sh",
        )
        (self.root / "scripts" / "export-database-snapshot.sh").chmod(0o755)

    def tearDown(self):
        self.temporary.cleanup()

    def _write_kubectl_stub(self, body):
        path = self.mock_bin / "kubectl"
        path.write_text(_KUBECTL_STUB_TEMPLATE.format(body=body), encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_export(self, args, kubectl_body):
        self._write_kubectl_stub(kubectl_body)
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        return subprocess.run(
            ["bash", "scripts/export-database-snapshot.sh", *args],
            cwd=self.root, env=environment, text=True, capture_output=True,
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text().splitlines() if line]


class UnknownScopeTests(ExportDatabaseSnapshotFixture):
    def test_unknown_scope_fails_with_usage(self):
        result = self.run_export(["unknown"], 'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"; exit 0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout + result.stderr)


class MongodbExportTests(ExportDatabaseSnapshotFixture):
    def test_mongodb_scope_execs_pbm_backup_with_wait(self):
        # Fake kubectl: log every invocation; for `exec ... -- pbm backup ...`
        # calls, exit 0 to simulate the (mocked) pbm CLI completing.
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ "$1" == "exec" ]]; then exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["mongodb"], body)
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertIn("exec", logged)
        self.assertIn("pbm backup", logged)
        self.assertIn("--wait", logged)


class PostgresqlExportTests(ExportDatabaseSnapshotFixture):
    def test_postgresql_scope_applies_backup_cr_and_polls_phase(self):
        # Fake kubectl: `apply -f -` (creating the Backup CR) logs and
        # succeeds; `get backup ... -o jsonpath={.status.phase}` reports
        # "completed" immediately so the poll loop exits right away.
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ "$1" == "get" && "$2" == "backup" ]]; then echo -n completed; exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["postgresql"], body)
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertIn("apply", logged)
        self.assertIn("kind: Backup", (self.root / "scripts" / "export-database-snapshot.sh").read_text())
        self.assertIn("jsonpath", logged)

    def test_postgresql_scope_fails_when_backup_phase_is_failed(self):
        body = (
            'printf "kubectl %s\\n" "$*" >> "$MOCK_COMMAND_LOG"\n'
            'if [[ "$1" == "get" && "$2" == "backup" ]]; then echo -n failed; exit 0; fi\n'
            'exit 0\n'
        )
        result = self.run_export(["postgresql"], body)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/environment_orchestration/test_export_database_snapshot.py -v`
Expected: FAIL — `scripts/export-database-snapshot.sh` doesn't exist yet.

- [ ] **Step 3: Implement `scripts/export-database-snapshot.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  export-database-snapshot.sh <mongodb|postgresql> [--wait-timeout-seconds N]

Triggers an on-demand, native backup for the given database into its
existing, already-configured S3 destination:
  mongodb     Runs `pbm backup --wait` inside the PBM agent container.
  postgresql  Applies a CNPG on-demand `Backup` custom resource and polls
              its status until it reaches `completed` or `failed`.

Options:
  --wait-timeout-seconds N  Timeout for waiting on completion (default: 900).
  -h, --help                Show this help.

Examples:
  scripts/export-database-snapshot.sh mongodb
  scripts/export-database-snapshot.sh postgresql --wait-timeout-seconds 1800
EOF
}

SCOPE="${1:-}"
WAIT_TIMEOUT_SECONDS="900"

if [[ "$SCOPE" == "-h" || "$SCOPE" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$SCOPE" ]]; then
  usage
  exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait-timeout-seconds)
      WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

export_mongodb() {
  local namespace="${MONGODB_NAMESPACE:-mongodb}"
  local pbm_pod
  pbm_pod="$(kubectl -n "$namespace" get pods -l app.kubernetes.io/name=percona-server-mongodb -o jsonpath='{.items[0].metadata.name}')"
  echo "Triggering on-demand PBM backup on pod $pbm_pod (namespace $namespace) ..."
  kubectl -n "$namespace" exec "$pbm_pod" -- pbm backup --wait --wait-time "${WAIT_TIMEOUT_SECONDS}s"
}

export_postgresql() {
  local namespace="${POSTGRESQL_NAMESPACE:-postgresql}"
  local cluster_name="${POSTGRESQL_CLUSTER_NAME:-oms-postgresql}"
  local backup_name="on-demand-$(date -u +%Y%m%dt%H%M%Sz)"

  echo "Requesting on-demand CNPG backup '$backup_name' for cluster '$cluster_name' ..."
  cat <<EOF | kubectl -n "$namespace" apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $namespace
spec:
  method: barmanObjectStore
  cluster:
    name: $cluster_name
EOF

  echo "Waiting for backup '$backup_name' to complete (timeout: ${WAIT_TIMEOUT_SECONDS}s) ..."
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
  while true; do
    local phase
    phase="$(kubectl -n "$namespace" get backup "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      completed)
        echo "Backup '$backup_name' completed."
        return 0
        ;;
      failed)
        echo "ERROR: backup '$backup_name' failed." >&2
        return 1
        ;;
    esac
    if (( SECONDS >= deadline )); then
      echo "ERROR: timed out waiting for backup '$backup_name' to complete (last phase: ${phase:-unknown})." >&2
      return 1
    fi
    sleep 5
  done
}

case "$SCOPE" in
  mongodb|mongo)
    export_mongodb
    ;;
  postgresql|pg)
    export_postgresql
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, postgresql" >&2
    usage
    exit 1
    ;;
esac

echo "Completed on-demand export for scope: $SCOPE"
```

Make it executable: `chmod +x scripts/export-database-snapshot.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/environment_orchestration/test_export_database_snapshot.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/export-database-snapshot.sh tests/environment_orchestration/test_export_database_snapshot.py
git commit -m "feat(ops): add standalone on-demand database export tool"
```

---

### Task 2: Destroy-script confirmation gate + `--export-first`

**Files:**
- Modify: `scripts/legacy/dev/destroy.sh`
- Test: `tests/environment_orchestration/test_destroy_safety_gate.py`

**Interfaces:**
- Consumes: `scripts/export-database-snapshot.sh` from Task 1.

- [ ] **Step 1: Write the failing test**

```python
"""Structural tests for the new confirmation gate and --export-first flag
in scripts/legacy/dev/destroy.sh. Mocks kubectl/terraform/aws; no live
execution. Confirmation input is supplied via stdin."""
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

_LOGGING_STUB_TEMPLATE = (
    "#!/usr/bin/env bash\n"
    "printf '{name} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
    "exit 0\n"
)


class DestroySafetyGateFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name).resolve() / "repository"
        self.mock_bin = pathlib.Path(self.temporary.name) / "bin"
        self.command_log = pathlib.Path(self.temporary.name) / "commands.log"
        self.root.mkdir(parents=True)
        self.mock_bin.mkdir(parents=True)
        for command in ("aws", "kubectl", "terraform"):
            self._write_executable(
                self.mock_bin / command, _LOGGING_STUB_TEMPLATE.format(name=command),
            )
        (self.root / "scripts").mkdir(parents=True, exist_ok=True)
        for name in ("legacy/dev/destroy.sh", "export-database-snapshot.sh",
                     "bootstrap-terraform-s3-backend.sh"):
            source = REPO_ROOT / "scripts" / name
            destination = self.root / "scripts" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.exists():
                shutil.copy2(source, destination)
                destination.chmod(0o755)
        # Stub the backend bootstrap script (Terraform-scope helper, not
        # under test here) with a logging no-op.
        (self.root / "scripts" / "bootstrap-terraform-s3-backend.sh").write_text(
            _LOGGING_STUB_TEMPLATE.format(name="bootstrap-terraform-s3-backend.sh"),
            encoding="utf-8",
        )
        (self.root / "scripts" / "bootstrap-terraform-s3-backend.sh").chmod(0o755)
        for tf_subdir in ("mongodb", "postgresql"):
            tfvars = self.root / "platform-prerequisites" / "terraform" / tf_subdir / "terraform.tfvars"
            tfvars.parent.mkdir(parents=True, exist_ok=True)
            tfvars.write_text("", encoding="utf-8")

    def tearDown(self):
        self.temporary.cleanup()

    def _write_executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_destroy(self, args, stdin_text=None):
        environment = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "MOCK_COMMAND_LOG": str(self.command_log),
        }
        return subprocess.run(
            ["bash", "scripts/legacy/dev/destroy.sh", *args],
            cwd=self.root, env=environment, text=True, capture_output=True,
            input=stdin_text,
        )

    def command_log_lines(self):
        if not self.command_log.exists():
            return []
        return [line for line in self.command_log.read_text().splitlines() if line]


class ConfirmationGateTests(DestroySafetyGateFixture):
    def test_wrong_confirmation_aborts_with_no_destructive_calls(self):
        result = self.run_destroy(["mongodb"], stdin_text="not-destroy\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_empty_confirmation_aborts_with_no_destructive_calls(self):
        result = self.run_destroy(["mongodb"], stdin_text="\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log_lines(), [])

    def test_correct_confirmation_proceeds(self):
        result = self.run_destroy(["mongodb"], stdin_text="DESTROY\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(len(self.command_log_lines()) > 0)

    def test_auto_approve_skips_prompt_entirely(self):
        result = self.run_destroy(["mongodb", "--auto-approve"], stdin_text="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(len(self.command_log_lines()) > 0)


class ExportFirstFlagTests(DestroySafetyGateFixture):
    def test_export_first_calls_export_script_before_any_destructive_command(self):
        result = self.run_destroy(
            ["mongodb", "--auto-approve", "--export-first"], stdin_text="",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = self.command_log_lines()
        # First logged kubectl/terraform call must come from the export
        # tool's own kubectl invocations (it runs before destroy_mongodb_k8s).
        self.assertTrue(any("get pods" in line or "exec" in line for line in logged[:2]))

    def test_without_export_first_flag_export_script_never_invoked(self):
        result = self.run_destroy(["mongodb", "--auto-approve"], stdin_text="")
        self.assertEqual(result.returncode, 0, result.stderr)
        logged = "\n".join(self.command_log_lines())
        self.assertNotIn("pbm backup", logged)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/environment_orchestration/test_destroy_safety_gate.py -v`
Expected: FAIL — no confirmation gate or `--export-first` flag exist yet.

- [ ] **Step 3: Add the confirmation gate and `--export-first` flag**

Modify `scripts/legacy/dev/destroy.sh`'s argument parsing and add a gate
function, called from `main()` before the scope `case` dispatch:

```bash
# (in the option-parsing while loop, alongside --auto-approve/--keep-signoz-namespace)
    --export-first)
      EXPORT_FIRST="true"
      shift
      ;;
```

Add near the top-level variable declarations:

```bash
EXPORT_FIRST="false"
```

Add a new function, called at the start of `main()` before any destroy work:

```bash
confirm_destruction() {
  local scope="$1"

  if [[ "$AUTO_APPROVE" == "true" ]]; then
    return 0
  fi

  echo "About to destroy scope '$scope'. This removes Kubernetes workloads and/or"
  echo "Terraform-managed AWS resources for this scope and cannot be undone from"
  echo "here (see docs/references/recovery-procedures.md for recovery options)."
  echo "Type DESTROY (all caps) to proceed, or anything else to abort:"
  local reply
  IFS= read -r reply || reply=""
  if [[ "$reply" != "DESTROY" ]]; then
    echo "Aborted: confirmation not received." >&2
    exit 1
  fi
}

export_scope_if_requested() {
  local scope="$1"

  if [[ "$EXPORT_FIRST" != "true" ]]; then
    return 0
  fi

  case "$scope" in
    mongodb|mongo)
      "$ROOT_DIR/scripts/export-database-snapshot.sh" mongodb
      ;;
    pg)
      "$ROOT_DIR/scripts/export-database-snapshot.sh" postgresql
      ;;
    all)
      "$ROOT_DIR/scripts/export-database-snapshot.sh" mongodb
      "$ROOT_DIR/scripts/export-database-snapshot.sh" postgresql
      ;;
  esac
}
```

Modify `main()` to call both before the existing `case "$SCOPE" in` dispatch:

```bash
main() {
  require_cmd kubectl
  require_cmd terraform
  require_cmd aws

  if [[ ! -x "$BOOTSTRAP_BACKEND_SCRIPT" ]]; then
    echo "Error: backend bootstrap script is not executable: $BOOTSTRAP_BACKEND_SCRIPT" >&2
    exit 1
  fi

  confirm_destruction "$SCOPE"
  export_scope_if_requested "$SCOPE"

  case "$SCOPE" in
```

Update the `usage()` heredoc to document `--export-first`:

```
Options:
  --auto-approve          Skip Terraform approval prompts and the DESTROY confirmation.
  --export-first          Run scripts/export-database-snapshot.sh for each database
                           scope before any teardown step; aborts if the export fails.
  --keep-signoz-namespace Keep signoz namespace object (delete app resources only).
  -h, --help              Show this help.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/environment_orchestration/test_destroy_safety_gate.py -v`
Expected: PASS

- [ ] **Step 5: Run the pre-existing entrypoints suite to confirm no regression**

Run: `python -m pytest tests/environment_orchestration/test_entrypoints.py -v`
Expected: PASS — the existing `LegacyDestroyFixture`-based tests must still
pass; if any test invokes `destroy.sh` without supplying stdin input,
check whether it now hangs waiting on the new prompt and pass
`--auto-approve` or stdin input as needed. If any pre-existing test needs a
stdin/flag update because it now hits the new confirmation prompt, that is
an expected, necessary update — not a plan-scope violation — since the
prompt is the entire point of this task.

- [ ] **Step 6: Commit**

```bash
git add scripts/legacy/dev/destroy.sh tests/environment_orchestration/test_destroy_safety_gate.py
git commit -m "feat(ops): add DESTROY confirmation gate and --export-first flag to legacy destroy.sh"
```

---

### Task 3: Dev/SIT CNPG Restore Guide

**Files:**
- Modify: `docs/references/recovery-procedures.md`
- Modify: `docs/references/postgresql-platform-contract.md` (cross-link only)
- Test: `tests/postgresql/test_documentation.py` (add to the existing
  `TestPostgreSQLDocumentationOrchestrationFixes` class — do not replace the
  file; see the postgresql-orchestration plan's I5 finding for why this
  matters)

- [ ] **Step 1: Write the failing test**

```python
    def test_recovery_procedures_documents_devsit_cnpg_restore(self):
        """recovery-procedures.md must cover Dev/SIT CNPG restore, not just Aurora"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "recovery-procedures.md").read_text()
        self.assertIn("Dev/SIT PostgreSQL Recovery (CNPG)", content)
        self.assertIn("s3://oms-postgresql-backup", content)
        self.assertIn("recoveryTarget", content)

    def test_platform_contract_links_to_devsit_recovery_section(self):
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "postgresql-platform-contract.md").read_text()
        self.assertIn("recovery-procedures.md", content)
```

(Add these two methods to the existing `TestPostgreSQLDocumentationOrchestrationFixes` class in `tests/postgresql/test_documentation.py`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_documentation.py -k devsit_cnpg -v`
Expected: FAIL — section doesn't exist yet.

- [ ] **Step 3: Add the section to `docs/references/recovery-procedures.md`**

Insert a new `## Dev/SIT PostgreSQL Recovery (CNPG)` section directly above
the existing `## PostgreSQL Recovery` (Aurora) section:

```markdown
## Dev/SIT PostgreSQL Recovery (CNPG)

Dev/SIT PostgreSQL runs as a self-managed CloudNativePG (CNPG) cluster (see
[PostgreSQL Platform Contract](postgresql-platform-contract.md)), not Aurora —
use this section for Dev/SIT; see "PostgreSQL Recovery" below for UAT/Prod.

### Restoring into a new cluster from the WAL archive

CNPG restores by bootstrapping a **new** `Cluster` resource that recovers from
an existing backup archive — it does not restore in place onto the original
cluster.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: oms-postgresql-restored
  namespace: postgresql
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  storage:
    storageClass: gp3-postgresql
    size: 50Gi
  bootstrap:
    recovery:
      source: oms-postgresql-backup-source
  externalClusters:
    - name: oms-postgresql-backup-source
      barmanObjectStore:
        destinationPath: s3://oms-postgresql-backup
        s3Credentials:
          inheritFromIAMRole: true
```

### Point-in-time recovery

Add `recoveryTarget.targetTime` under `bootstrap.recovery` to recover to a
specific point in time instead of the latest available WAL:

```yaml
  bootstrap:
    recovery:
      source: oms-postgresql-backup-source
      recoveryTarget:
        targetTime: "2026-08-01T09:00:00Z"
```

### Restoring from an on-demand export

If an on-demand backup was taken via
`scripts/export-database-snapshot.sh postgresql` (see the script's own
`--help` for usage), it is stored in the same `s3://oms-postgresql-backup`
destination and is restored the same way — CNPG does not distinguish
scheduled/continuous backups from on-demand ones at restore time.

**Verify the restore:**
```bash
kubectl -n postgresql get cluster oms-postgresql-restored
# Expect: status=Ready once recovery completes
```
```

- [ ] **Step 4: Cross-link from `postgresql-platform-contract.md`**

Add a line under the existing "Related Docs" bullet list:

```markdown
  - [Recovery Procedures](recovery-procedures.md) — Dev/SIT CNPG restore and PITR
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_documentation.py -v`
Expected: PASS (full file, not just the new tests — confirms nothing else broke)

- [ ] **Step 6: Commit**

```bash
git add docs/references/recovery-procedures.md docs/references/postgresql-platform-contract.md tests/postgresql/test_documentation.py
git commit -m "docs(postgresql): author missing Dev/SIT CNPG restore guide"
```

---

### Task 4: Orphaned EBS Volume Recovery Runbook

**Files:**
- Modify: `docs/references/recovery-procedures.md`
- Test: `tests/postgresql/test_documentation.py` (same class as Task 3)

- [ ] **Step 1: Write the failing test**

```python
    def test_recovery_procedures_documents_orphaned_ebs_volume_recovery(self):
        """recovery-procedures.md must explain recovering a Released EBS-backed PV"""
        content = (Path(__file__).parent.parent.parent / "docs" / "references" / "recovery-procedures.md").read_text()
        self.assertIn("Orphaned EBS Volume Recovery", content)
        self.assertIn("claimRef", content)
        self.assertIn("Released", content)
```

(Add to the same `TestPostgreSQLDocumentationOrchestrationFixes` class.)

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_documentation.py -k orphaned_ebs -v`
Expected: FAIL — section doesn't exist yet.

- [ ] **Step 3: Add the section to `docs/references/recovery-procedures.md`**

Insert a new `## Orphaned EBS Volume Recovery` section (e.g. after "EBS CSI
Driver Recovery"):

```markdown
## Orphaned EBS Volume Recovery

Both `gp3-mongodb` and `gp3-postgresql` StorageClasses use
`reclaimPolicy: Retain`. Deleting a PVC (directly, or as a side effect of
`scripts/destroy.sh`) does **not** delete the underlying AWS EBS volume — the
`PersistentVolume` moves to `Released`, and the data survives, but it will
not automatically bind to a new PVC until an operator clears its claim.

This is a Kubernetes-side operation on the `PersistentVolume` object's
`spec.claimRef` field — not an AWS-console action; the EBS volume itself is
untouched throughout.

### Step 1: Identify the released volume

```bash
kubectl get pv | grep Released
# NAME       CAPACITY   ...   RECLAIM POLICY   STATUS     CLAIM
# pvc-abc123 50Gi       ...   Retain           Released   postgresql/oms-postgresql-1
```

### Step 2: Clear the stale claim reference

```bash
kubectl patch pv pvc-abc123 --type=json \
  -p='[{"op": "remove", "path": "/spec/claimRef"}]'
# PV moves from Released -> Available
```

### Step 3: Bind it to a new PVC

Create a PVC with a matching `storageClassName`, `accessModes`, and a
`volumeName` pinning it to the specific released volume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recovered-data
  namespace: postgresql
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: gp3-postgresql
  volumeName: pvc-abc123
  resources:
    requests:
      storage: 50Gi
```

### Step 4: Mount and read the data

Attach the PVC to a temporary debug pod to inspect/copy its contents (for
PostgreSQL, this is the raw `PGDATA` directory — do not start a new
PostgreSQL instance directly against it without restoring through CNPG's
normal bootstrap process; treat it as a forensic copy source, not a
drop-in replacement volume).
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_documentation.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/references/recovery-procedures.md tests/postgresql/test_documentation.py
git commit -m "docs(recovery): author orphaned EBS volume recovery runbook"
```

---

### Task 5: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full repo test suite**

Run: `env -u TF_DATA_DIR python -m pytest tests/ -q`
Expected: all tests pass, including every pre-existing suite untouched by
this plan (in particular `tests/environment_orchestration/test_entrypoints.py`'s
`LegacyDestroyFixture`-based tests, which now exercise the new confirmation
gate).

- [ ] **Step 2: Commit any stragglers**

```bash
git status --short
git add -A
git commit -m "chore(teardown-safety): finalize" --allow-empty
```
