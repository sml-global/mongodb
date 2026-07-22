# Phase 2 Data And Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement environment-aware MongoDB, independent core and brand Aurora PostgreSQL, database-native access, collectors, SigNoz observability, and lifecycle integration while leaving live dev resources and state unchanged.

**Architecture:** Shared environment, registry, path, guard, and orchestration libraries from the Phase 2 foundation remain the only environment-selection and lifecycle authority. MongoDB uses one guarded Terraform root plus dev/UAT Kustomize overlays; core and brand PostgreSQL use separate runnable roots and state objects backed by one reusable Aurora module. Data does not own the generic `workload-identity` root; it adds one PostgreSQL collector entry to each existing dev/UAT EKS-owned `identities` map. Data lifecycle mutations, component verifiers, pre-destroy guards, and retention checks live in separate files beneath `scripts/lib/packages/30-data-telemetry/internal/` and have distinct `data_internal_*` names that never equal canonical registry symbols. `internal/lifecycle.sh` alone owns package lifecycle mutation; `internal/retention.sh` remains read-only and owns no lifecycle mutation; `internal/verifiers.sh` owns component verification only; and `internal/pre-destroy-guards.sh` owns the eight fixed-scope, read-only, artifact-free guards. `scripts/lib/scope-handlers.d/30-data-telemetry.sh` and `scripts/lib/scope-verifiers.d/30-data-telemetry.sh` alone define the exact canonical wrapper symbols pre-mapped by the foundation registry and delegate directly to those internal functions, with no registration or graph mutation. The numbered verifier fragment sources the validated verifier and pre-destroy-guard files, plus their read-only retention dependency, through `source_package_internal_library`; it alone defines every canonical component-verifier and pre-destroy-guard wrapper. The foundation invokes every selected scope's read-only pre-destroy guard in reverse destroy order after opening and validating the operation artifact and before approval, artifact consumption, or destroy dispatch. PostgreSQL roots consume the exact nested `eks-platform` `platform_contract`; SigNoz resources carry both `environment` and `cluster_role`; and dev PostgreSQL remains modeled only through read-only mapping and adoption artifacts.

For architecture purposes, "artifact-free package" means no data/telemetry package code creates, reads, writes, updates, consumes, renames, registers, or deletes an evidence artifact. It does not prohibit the required value-only in-memory `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` callback. The callback digest is exactly `sha256:<64 lowercase hex characters>`; raw hex is invalid. Every active data guard invokes that callback exactly once after all live checks, including on failure; the foundation alone validates and persists any durable evidence artifact, schema, and path.

**Tech Stack:** Bash 3.2+, Python 3 `unittest`, Terraform >= 1.10 with native S3 lockfiles, AWS provider >= 5, SigNoz provider 0.0.14, Kubernetes, Kustomize, Percona Server for MongoDB, OpenTelemetry Collector, Prometheus CloudWatch Exporter, PostgreSQL `psql`, MongoDB `mongosh`, AWS Secrets Manager, EKS Pod Identity.

---

## Authorization Boundary

This is an implementation plan only. Every command block in this plan is an `AUTHORIZED-ONLY` instruction for a future implementation session after the user separately authorizes that class of execution. This review authorizes no tests, Terraform, scripts, AWS/Kubernetes/database access, provisioning, destruction, or commits.

The following commands are always outside the default implementation boundary and require explicit current-conversation authorization: `terraform plan`, `terraform apply`, `terraform destroy`, `terraform import`, `terraform state mv`, `kubectl apply`, `kubectl delete`, `aws rds modify-*`, database grant/revoke commands against a live endpoint, secret creation or rotation, provision scripts, destroy scripts, smoke tests, and any dev account or dev cluster mutation.

No task in this plan mutates or adopts live dev PostgreSQL. Task 12 creates read-only inventory and mapping artifacts only.

## Required Upstream Interfaces

This work package starts after the Phase 2 environment-schema and unified-orchestration packages provide these interfaces:

```bash
# scripts/lib/platform-env.sh and scripts/lib/platform-guards.sh
load_platform_env <dev|uat>
verify_aws_identity_and_region
verify_kubernetes_context
require_environment_mutation_authorized
environment_config_value <KEY>

# scripts/lib/orchestration-paths.sh
initialize_orchestration_paths
register_generated_artifact <path>
register_plan_artifact <path>

# scripts/lib/orchestrator.sh
# Owns parse, graph pre-resolution, PROMOTION_MODE checks, one environment
# lock, guard ordering, handler dispatch, and registered-artifact cleanup.

# foundation pre-destroy evidence API
record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>
# Validates one in-memory result per active scope and alone writes the canonical
# durable guard-result artifact using the foundation-owned schema and path.

# scripts/lib/scope-registry.sh
state_key_variable_for_scope <scope>
provision_handler_for_scope <scope>
destroy_handler_for_scope <scope>
verification_handler_for_slot <slot>
dispatch_scope_handler <provision|destroy|verify> <scope-or-slot> [handler-args...]
```

The callback resource identity is a canonical, non-secret string assembled only from loaded environment values, validated rendered configuration, selected Terraform outputs, and matching read-only live state. It is never inferred from a confirmation string, evidence artifact, sibling scope, display title, or unvalidated endpoint. The exact identities are:

```text
mongodb -> psmdb/<MONGODB_NAMESPACE>/<validated PSMDB metadata.name>
postgresql-core -> rds/<AWS_REGION>/<EXPECTED_AWS_ACCOUNT_ID>/<POSTGRESQL_CORE_CLUSTER_IDENTIFIER>
postgresql-brand -> rds/<AWS_REGION>/<EXPECTED_AWS_ACCOUNT_ID>/<POSTGRESQL_BRAND_CLUSTER_IDENTIFIER>
mongodb-access -> mongodb-access/<MONGODB_NAMESPACE>/<validated PSMDB replica-set service name>
database-access-core -> database-access/core/<POSTGRESQL_CORE_CLUSTER_IDENTIFIER>/<selected root postgresql_endpoint>/<selected root master_user_secret_arn>
database-access-brand -> database-access/brand/<POSTGRESQL_BRAND_CLUSTER_IDENTIFIER>/<selected root postgresql_endpoint>/<selected root master_user_secret_arn>
signoz -> helm/<SIGNOZ_NAMESPACE>/<validated environment-qualified SigNoz release name>
signoz-observability -> signoz-observability/<ENVIRONMENT>/dashboards=aws-rds-postgresql-<ENVIRONMENT>-core,aws-rds-postgresql-<ENVIRONMENT>-brand;alerts=<sorted validated environment-qualified Terraform alert resource names>
```

The PostgreSQL endpoint and secret ARN components are exact selected-root outputs already verified against the selected live cluster; they are identities, not secret values. Core and brand identities, summaries, digests, statuses, summary codes, callback invocations, and tests remain separate even when both scopes are selected. The SigNoz observability alert-name list is bytewise sorted before joining, so provider or Terraform iteration order cannot change the identity.

The environment schema must expose these exact keys before this plan begins:

```text
ENVIRONMENT EXPECTED_AWS_ACCOUNT_ID AWS_REGION EKS_CLUSTER_NAME
MONGODB_NAMESPACE SIGNOZ_NAMESPACE
TF_STATE_BUCKET TF_STATE_REGION MONGODB_STATE_KEY
POSTGRESQL_CORE_STATE_KEY POSTGRESQL_BRAND_STATE_KEY
WORKLOAD_IDENTITY_STATE_KEY SIGNOZ_OBSERVABILITY_STATE_KEY
MONGODB_NAME_PREFIX MONGODB_PBM_BUCKET_NAME MONGODB_PBM_ROLE_NAME
MONGODB_STORAGE_CLASS MONGODB_STORAGE_SIZE MONGODB_REPLICA_COUNT
POSTGRESQL_CORE_NAME_PREFIX POSTGRESQL_CORE_CLUSTER_IDENTIFIER
POSTGRESQL_CORE_WRITER_IDENTIFIER POSTGRESQL_CORE_DATABASE_NAME
POSTGRESQL_CORE_ENGINE_VERSION POSTGRESQL_CORE_INSTANCE_CLASS
POSTGRESQL_CORE_WRITER_AZ POSTGRESQL_CORE_BACKUP_RETENTION_DAYS
POSTGRESQL_CORE_DELETION_PROTECTION POSTGRESQL_CORE_SKIP_FINAL_SNAPSHOT
POSTGRESQL_CORE_FINAL_SNAPSHOT_PREFIX POSTGRESQL_CORE_LOG_EXPORTS
POSTGRESQL_BRAND_NAME_PREFIX POSTGRESQL_BRAND_CLUSTER_IDENTIFIER
POSTGRESQL_BRAND_WRITER_IDENTIFIER POSTGRESQL_BRAND_DATABASE_NAME
POSTGRESQL_BRAND_ENGINE_VERSION POSTGRESQL_BRAND_INSTANCE_CLASS
POSTGRESQL_BRAND_WRITER_AZ POSTGRESQL_BRAND_BACKUP_RETENTION_DAYS
POSTGRESQL_BRAND_DELETION_PROTECTION POSTGRESQL_BRAND_SKIP_FINAL_SNAPSHOT
POSTGRESQL_BRAND_FINAL_SNAPSHOT_PREFIX POSTGRESQL_BRAND_LOG_EXPORTS
EKS_PLATFORM_STATE_KEY POSTGRESQL_CORE_ALLOWED_SECURITY_GROUP_IDS
POSTGRESQL_BRAND_ALLOWED_SECURITY_GROUP_IDS POSTGRESQL_CORE_ALLOWED_CIDRS
POSTGRESQL_BRAND_ALLOWED_CIDRS POSTGRESQL_MONITOR_NAMESPACE
POSTGRESQL_MONITOR_SERVICE_ACCOUNT
PROMOTION_MODE
```

The data-specific keys above are declared only in `config/environment-schema/fragments/30-data-telemetry.manifest`, using the foundation manifest grammar, and receive matching values in both environment files. This package never edits `scripts/lib/platform-env.sh` or any parser. Exact promotion values are `PROMOTION_MODE=modeled` for dev and `PROMOTION_MODE=uat-build` for UAT. Promotion is foundation-owned and absent from the data schema fragment. Do not add a second parser, graph, lock, promotion gate, identity/Region verifier, or path API; do not infer environment from AWS profile, kube context, root directory, or legacy tfvars. Every mutating data handler relies on the orchestrator's single environment lock and calls `require_environment_mutation_authorized` immediately before its first mutation. No component-specific mutation switch exists.

## File And Ownership Map

| Path | Responsibility |
|---|---|
| `tests/phase2_data_telemetry/test_terraform_contract.py` | Static state, provider, module, ownership, and dual-cluster isolation contracts. |
| `tests/phase2_data_telemetry/test_kustomize_contract.py` | Dev/UAT render isolation, labels, collector dimensions, and secret-reference contracts. |
| `tests/phase2_data_telemetry/test_access_contract.py` | Canonical imported-matrix data rows and explicit MongoDB/PostgreSQL core-denial contracts. |
| `tests/phase2_data_telemetry/test_lifecycle_contract.py` | Mocked narrow provision/verify/destroy dispatch and independent-state lifecycle tests. |
| `tests/phase2_data_telemetry/test_observability_contract.py` | SigNoz environment and `cluster_role` dashboard/alert filters. |
| `tests/phase2_data_telemetry/test_dev_adoption_contract.py` | Read-only legacy PostgreSQL mapping and no-mutation guarantees. |
| `config/environment-schema/fragments/30-data-telemetry.manifest` | Only data/telemetry schema extension; declarative keys and validators, with no parser edits. |
| `platform-prerequisites/terraform/modules/mongodb-prerequisites/*` | Reusable PBM bucket, IAM role, namespace, service account, and Pod Identity resources. |
| `platform-prerequisites/terraform/mongodb/*` | Environment-guarded MongoDB runnable root and outputs. |
| `platform-prerequisites/terraform/modules/postgresql-cluster/*` | One reusable Aurora module owning subnet/security/parameter groups, cluster, writer, logs, backup, and lifecycle. |
| `platform-prerequisites/terraform/postgresql-core/*` | Thin core root, provider account guard, state boundary, inputs, outputs, and moved blocks. |
| `platform-prerequisites/terraform/postgresql-brand/*` | Thin brand root, provider account guard, state boundary, inputs, and outputs. |
| `platform-prerequisites/terraform/environments/{dev,uat}/workload-identity.tfvars` | Extend the EKS-owned generic `identities` map with the PostgreSQL collector exactly once per environment. |
| `.local/<env>/generated/*.auto.tfvars.json` | Scope-specific generated non-secret Terraform inputs derived from the environment contract and `eks-platform` remote state; registered for cleanup. |
| `config/environments/<env>.local/*.json.example` | Canonical operator-local input examples; no local input values are committed. |
| `k8s/base/*` | Environment-neutral MongoDB and collector manifests. |
| `k8s/overlays/dev/*` | Dev names, labels, storage, endpoints, and collector dimensions. |
| `k8s/overlays/uat/*` | UAT names, labels, storage, endpoints, and collector dimensions. |
| `gitops/signoz/overlays/dev/*`, `gitops/signoz/overlays/uat/*` | Environment-specific SigNoz namespace and telemetry resource attributes. |
| `scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh` | Private MongoDB secret bootstrap and escrow functions named `data_internal_*`; no canonical wrappers or top-level execution. |
| `scripts/lib/packages/30-data-telemetry/internal/access.sh` | Private MongoDB/PostgreSQL access reconciliation and verification functions named `data_internal_*`; no canonical wrappers or top-level execution. |
| `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh` | Private data-domain provision and destroy functions named `data_internal_*`; sole package owner of lifecycle mutation, with no verifier/guard implementation, canonical wrappers, or top-level execution. |
| `scripts/lib/packages/30-data-telemetry/internal/verifiers.sh` | Package-owned mode-safe internal component verification functions named `data_internal_*`; no pre-destroy guards, canonical wrappers, public mode parsing, artifact handling, mutation, or top-level execution. |
| `scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh` | Eight scope-fixed `data_internal_guard_destroy_*` functions; performs live checks read-only, computes status, canonical resource identity, foundation-canonical summary SHA-256 digest, and closed summary code in memory, and invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once per active fixed scope; no verifier implementation, canonical wrappers, mutation, evidence/generated-input/plan writes, evidence artifact reads, artifact path/value access, registration, dispatch, or top-level execution. |
| `scripts/lib/packages/30-data-telemetry/internal/retention.sh` | Package-private read-only retention, recoverability, export, dependency, audit-evidence, exact prepared-identity, digest-input normalization, and immediate post-consumption protection-recheck helpers used by guards and destroy handlers; lifecycle mutation remains in `lifecycle.sh`, and this file has no callback invocation, artifact parsing/consumption, canonical wrappers, registration, dispatch, writes, or top-level execution. |
| `scripts/lib/scope-handlers.d/30-data-telemetry.sh` | Use only `source_package_internal_library` for package-owned mode-safe internal lifecycle dependencies, then define exact foundation-pre-mapped canonical provision/destroy wrapper symbols and delegate; no registration, graph data, direct source command, or other top-level execution. |
| `scripts/lib/scope-verifiers.d/30-data-telemetry.sh` | Use only `source_package_internal_library` to source the validated `verifiers.sh` and `pre-destroy-guards.sh` files plus read-only `retention.sh`, then alone define the exact foundation-pre-mapped canonical component-verifier and eight pre-destroy-guard wrapper symbols and delegate; no mode/guard registration, parsing, artifact consumption, graph data, direct source command, or other top-level execution. |
| `scripts/lib/database-access.sh` | Shared fail-closed runtime Secrets Manager resolution, endpoint verification, in-memory result construction, and secret-material cleanup guards; creates, reads, and writes no evidence artifact. |
| `platform-prerequisites/terraform/signoz-observability/*` | Environment-qualified dashboards and alerts. |
| `docs/operations/imported-code-review-matrix.md` | Foundation-owned canonical seven-column matrix; this package appends `DATA-0001` onward and uses the foundation validator. |
| `docs/operations/dev-postgresql-legacy-inventory.json` | Read-only legacy state/resource inventory result. |
| `docs/operations/dev-postgresql-adoption-map.json` | Explicit mapping of the one legacy cluster to exactly one future root. |
| Shared documentation | Deferred to the documentation/acceptance/adoption package; this package creates no separate data contract document. |

### Task 1: Lock The Phase 2 Data Contracts With Failing Tests

**Files:**
- Create: `tests/phase2_data_telemetry/__init__.py`
- Create: `tests/phase2_data_telemetry/test_terraform_contract.py`
- Create: `tests/phase2_data_telemetry/test_kustomize_contract.py`
- Create: `tests/phase2_data_telemetry/test_lifecycle_contract.py`
- Create: `config/environment-schema/fragments/30-data-telemetry.manifest`
- Modify: `config/environments/dev.env`
- Modify: `config/environments/uat.env`

- [ ] **Step 1: Create the package marker**

Create an empty `tests/phase2_data_telemetry/__init__.py`.

- [ ] **Step 2: Define the data-only schema fragment and environment values**

Create only `config/environment-schema/fragments/30-data-telemetry.manifest` for data/telemetry declarations, using the foundation's exact `KEY|required|validator|immutable-key-or--` grammar and built-in validators. Add matching closed-schema values to both environment files. Do not edit `base.manifest`, `platform-env.sh`, `environment-contracts.sh`, or parser tests to special-case data keys. Keep the foundation-owned namespace and promotion values unchanged: dev `mongodb|signoz|boomi` with `PROMOTION_MODE=modeled`; UAT `mongodb-uat|signoz-uat|boomi-uat` with `PROMOTION_MODE=uat-build`. Promotion remains foundation-owned and must not be declared in `30-data-telemetry.manifest`. Set `POSTGRESQL_MONITOR_NAMESPACE` to `mongodb` for dev and `mongodb-uat` for UAT. Do not declare a PostgreSQL monitor role name; the EKS-owned workload-identity root derives it.

Add contract assertions that the composed foundation schema accepts the fragment, rejects duplicate or unknown data keys through the unchanged parser, and contains no component mutation flag.

- [ ] **Step 3: Write the failing Terraform ownership and isolation tests**

Create `tests/phase2_data_telemetry/test_terraform_contract.py`:

```python
import json
import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TF_ROOT = REPO_ROOT / "platform-prerequisites" / "terraform"


def root_text(name):
    root = TF_ROOT / name
    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(root.glob("*.tf"))
    )


class TerraformContractTests(unittest.TestCase):
    def test_dual_postgresql_roots_use_one_module_and_distinct_state_keys(self):
        for role in ("core", "brand"):
            text = root_text(f"postgresql-{role}")
            self.assertIn('source = "../modules/postgresql-cluster"', text)
            self.assertIn("allowed_account_ids = [var.expected_account_id]", text)
            self.assertNotIn("resource \"aws_rds_cluster\"", text)

        uat = (REPO_ROOT / "config/environments/uat.env").read_text()
        self.assertIn("POSTGRESQL_CORE_STATE_KEY=oms/uat/postgresql-core.tfstate", uat)
        self.assertIn("POSTGRESQL_BRAND_STATE_KEY=oms/uat/postgresql-brand.tfstate", uat)
        for text in (root_text("postgresql-core"), root_text("postgresql-brand")):
          self.assertIn('data "terraform_remote_state" "eks_platform"', text)
          self.assertIn("var.eks_platform_state_key", text)
          self.assertNotIn('variable "vpc_id"', text)
          self.assertNotIn('variable "private_subnet_ids"', text)

    def test_postgresql_module_owns_complete_cluster_lifecycle(self):
        text = root_text("modules/postgresql-cluster")
        for token in (
            'resource "aws_db_subnet_group" "this"',
            'resource "aws_security_group" "this"',
            'resource "aws_rds_cluster_parameter_group" "this"',
            'resource "aws_db_parameter_group" "this"',
            'resource "aws_rds_cluster" "this"',
            'resource "aws_rds_cluster_instance" "writer"',
            "backup_retention_period",
            "enabled_cloudwatch_logs_exports",
            "deletion_protection",
            "skip_final_snapshot",
            "final_snapshot_identifier",
        ):
            self.assertIn(token, text)

    def test_cloudwatch_collector_identity_has_one_owner(self):
        workload = root_text("workload-identity")
        self.assertEqual(workload.count('resource "aws_iam_role" "identity"'), 1)
        self.assertEqual(workload.count('resource "aws_eks_pod_identity_association" "identity"'), 1)
        for environment in ("dev", "uat"):
          tfvars = (TF_ROOT / "environments" / environment / "workload-identity.tfvars").read_text()
          self.assertEqual(tfvars.count("postgres_cloudwatch_monitor"), 1)
        for root in ("postgresql-core", "postgresql-brand"):
            self.assertNotIn("postgres_cloudwatch_monitor", root_text(root))

    def test_mongodb_root_is_environment_guarded_and_module_backed(self):
        text = root_text("mongodb")
        self.assertIn('source = "../modules/mongodb-prerequisites"', text)
        self.assertIn("allowed_account_ids = [var.expected_account_id]", text)
        self.assertIn("environment = var.environment", text)
        self.assertNotIn('Environment = "dev"', text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Write the failing Kustomize isolation tests**

Create `tests/phase2_data_telemetry/test_kustomize_contract.py`:

```python
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def render(path):
    return subprocess.run(
        ["kubectl", "kustomize", str(REPO_ROOT / path)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=True,
    ).stdout


class KustomizeContractTests(unittest.TestCase):
    def test_mongodb_overlays_are_environment_isolated(self):
        dev = render("k8s/overlays/dev")
        uat = render("k8s/overlays/uat")
        self.assertIn("environment: dev", dev)
        self.assertIn("environment: uat", uat)
        self.assertNotIn("environment: uat", dev)
        self.assertNotIn("environment: dev", uat)
        self.assertIn("namespace: mongodb", dev)
        self.assertIn("namespace: mongodb-uat", uat)

    def test_collectors_emit_environment_and_cluster_role(self):
        for environment in ("dev", "uat"):
            rendered = render(f"k8s/overlays/{environment}")
            self.assertIn(f'value: "{environment}"', rendered)
            self.assertIn('key: "deployment.environment"', rendered)
            self.assertIn('key: "cluster_role"', rendered)
            self.assertIn('value: "core"', rendered)
            self.assertIn('value: "brand"', rendered)

    def test_signoz_overlays_are_environment_isolated(self):
        dev = render("gitops/signoz/overlays/dev")
        uat = render("gitops/signoz/overlays/uat")
        self.assertIn("environment: dev", dev)
        self.assertIn("namespace: signoz", dev)
        self.assertIn("environment: uat", uat)
        self.assertIn("namespace: signoz-uat", uat)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 5: Write the failing independent lifecycle tests**

Create `tests/phase2_data_telemetry/test_lifecycle_contract.py` using temporary mock external executables and foundation guard responses. Exercise only the public `scripts/provision.sh`, `scripts/destroy.sh`, and `scripts/verify-platform-health.sh` contracts; never invoke a component/private provisioning script. The harness must not set a production dry-run, live-preflight skip, or other execution-bypass environment variable. It must assert exact command logs:

```python
import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


class LifecycleContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
      self.repo = Path(self.temp.name) / "repo"
      shutil.copytree(
        REPO_ROOT,
        self.repo,
        ignore=shutil.ignore_patterns(".git", ".local", ".terraform"),
      )
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.log = Path(self.temp.name) / "commands.log"
        for name in ("aws", "kubectl", "terraform", "kustomize", "psql", "mongosh"):
            path = self.bin / name
            path.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '{name} %s\\n' \"$*\" >> \"$MOCK_COMMAND_LOG\"\n"
                "exit 0\n"
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, script, *args):
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.bin}:{env['PATH']}",
            "MOCK_COMMAND_LOG": str(self.log),
        })
        return subprocess.run(
          ["bash", str(self.repo / script), *args],
          cwd=self.repo,
            env=env,
            text=True,
            capture_output=True,
        )

    def command_log(self):
        return self.log.read_text() if self.log.exists() else ""

    def prepared_confirmation(self, scope):
        preparation = self.run_script("scripts/destroy.sh", "--env", "uat", scope)
        self.assertNotEqual(preparation.returncode, 0)
      preparation_log = self.command_log()
      self.assertIn("aws sts get-caller-identity", preparation_log)
      self.assertIn("aws configure get region", preparation_log)
      for forbidden in ("terraform ", "kubectl ", "kustomize ", "psql ", "mongosh ", "data_internal_"):
        self.assertNotIn(forbidden, preparation_log)
        marker = "Confirmation artifact: "
        artifact_lines = [line for line in preparation.stdout.splitlines() if line.startswith(marker)]
        self.assertEqual(len(artifact_lines), 1)
        relative_artifact = Path(artifact_lines[0][len(marker):])
        self.assertFalse(relative_artifact.is_absolute())
        self.assertEqual(relative_artifact.parts[:3], (".local", "uat", "generated"))
        artifact = self.repo / relative_artifact
        generated_root = (self.repo / ".local" / "uat" / "generated").resolve(strict=True)
        self.assertFalse(artifact.is_symlink())
        resolved_artifact = artifact.resolve(strict=True)
        self.assertTrue(resolved_artifact.is_file())
        self.assertTrue(resolved_artifact.is_relative_to(generated_root))
        self.assertEqual(resolved_artifact.stat().st_mode & 0o077, 0)
        payload = json.loads(resolved_artifact.read_text(encoding="utf-8"))
        confirmations = payload["confirmations"]
        self.assertIsInstance(confirmations, list)
        prefix = f"destroy:uat:672172129937:{scope}:"
        matches = [value for value in confirmations if value.startswith(prefix)]
        self.assertEqual(len(matches), 1)
        return relative_artifact, matches[0]

    def test_core_provision_does_not_initialize_brand(self):
        result = self.run_script(
        "scripts/provision.sh",
        "--env", "uat", "postgresql-core",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.command_log()
        self.assertIn("postgresql-core", log)
        self.assertIn("oms/uat/postgresql-core.tfstate", log)
        self.assertNotIn("postgresql-brand", log)

    def test_brand_destroy_does_not_touch_core_or_mongodb(self):
        relative_artifact, confirmation = self.prepared_confirmation("postgresql-brand")
        result = self.run_script(
            "scripts/destroy.sh", "--env", "uat", "postgresql-brand",
            "--confirmation-artifact", str(relative_artifact),
            "--confirm", confirmation,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.command_log()
        self.assertIn("postgresql-brand", log)
        self.assertNotIn("postgresql-core", log)
        self.assertNotIn("mongodb", log)

    def test_access_scopes_do_not_connect_to_sibling_database(self):
        for scope, forbidden in (
            ("mongodb-access", ("postgresql-core", "postgresql-brand")),
            ("database-access-core", ("mongodb-access", "postgresql-brand")),
            ("database-access-brand", ("mongodb-access", "postgresql-core")),
        ):
            self.log.unlink(missing_ok=True)
            result = self.run_script("scripts/provision.sh", "--env", "uat", scope)
            self.assertEqual(result.returncode, 0, result.stderr)
            log = self.command_log()
            for token in forbidden:
                self.assertNotIn(token, log)

    def test_dev_mutation_fails_before_external_commands(self):
        result = self.run_script(
            "scripts/provision.sh", "--env", "dev", "postgresql-core",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR: unified dev mutation is blocked while PROMOTION_MODE=modeled", result.stderr)
        self.assertEqual(self.command_log(), "")

    def test_public_verification_forms_are_exact(self):
        for mode in ("--preflight", "--full", None, "--smoke-test"):
            args = ["--env", "uat"]
            if mode is not None:
                args.append(mode)
            result = self.run_script("scripts/verify-platform-health.sh", *args)
            self.assertEqual(result.returncode, 0, result.stderr)

        full = self.run_script("scripts/verify-platform-health.sh", "--env", "uat", "--full")
        default_full = self.run_script("scripts/verify-platform-health.sh", "--env", "uat")
        self.assertEqual(full.stdout, default_full.stdout)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 6: Run only the new local tests and verify the expected failures**

`AUTHORIZED-ONLY` command:

```bash
python3 -m unittest discover -s tests/phase2_data_telemetry -p 'test_*.py' -v
```

Expected: FAIL because the PostgreSQL roots, collector identity map entries, UAT overlays, and canonical data wrapper symbols do not exist yet. No AWS, Kubernetes, Terraform plan/apply, or database connection is permitted.

- [ ] **Step 7: Commit the red tests and schema fragment**

```bash
git add tests/phase2_data_telemetry config/environment-schema/fragments/30-data-telemetry.manifest config/environments/dev.env config/environments/uat.env
git commit -m "test: define data telemetry isolation contracts"
```

### Task 2: Extract Environment-Aware MongoDB Prerequisites

**Files:**
- Create: `platform-prerequisites/terraform/modules/mongodb-prerequisites/main.tf`
- Create: `platform-prerequisites/terraform/modules/mongodb-prerequisites/variables.tf`
- Create: `platform-prerequisites/terraform/modules/mongodb-prerequisites/outputs.tf`
- Modify: `platform-prerequisites/terraform/mongodb/main.tf`
- Modify: `platform-prerequisites/terraform/mongodb/variables.tf`
- Modify: `platform-prerequisites/terraform/mongodb/outputs.tf`
- Create: `platform-prerequisites/terraform/mongodb/versions.tf`
- Delete: `platform-prerequisites/terraform/reusable/main.tf`
- Delete: `platform-prerequisites/terraform/reusable/variables.tf`
- Delete: `platform-prerequisites/terraform/reusable/outputs.tf`
- Delete: `platform-prerequisites/terraform/reusable/terraform.tfvars.example`

- [ ] **Step 1: Move the existing reusable resources into the named module**

Move the namespace, PBM S3 bucket controls, PBM role/policy, service account, and Pod Identity association from `platform-prerequisites/terraform/reusable/` into `modules/mongodb-prerequisites/`. Keep the existing policy actions, replace every hard-coded or implicit environment value with variables, and set these tags on every AWS resource:

```hcl
tags = merge(var.tags, {
  Environment = var.environment
  ManagedBy   = "terraform"
  Component   = "mongodb"
})
```

The module inputs must be exactly:

```hcl
variable "environment" { type = string }
variable "cluster_name" { type = string }
variable "mongodb_namespace" { type = string }
variable "mongodb_workload_service_account_name" { type = string }
variable "pbm_bucket_name" { type = string }
variable "iam_role_name" { type = string }
variable "kms_key_arn" { type = string; default = "" }
variable "tags" { type = map(string); default = {} }
```

Remove IRSA inputs and branches. Phase 2 supports EKS Pod Identity only; the trust actions remain `sts:AssumeRole` and `sts:TagSession`.

- [ ] **Step 2: Make the runnable root account guarded**

Create `platform-prerequisites/terraform/mongodb/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.10.0"
  backend "s3" { use_lockfile = true }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.26" }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
  default_tags { tags = var.tags }
}
```

Update `main.tf` to call only the named module:

```hcl
module "mongodb_prerequisites" {
  source = "../modules/mongodb-prerequisites"

  environment                           = var.environment
  cluster_name                          = var.cluster_name
  mongodb_namespace                     = var.mongodb_namespace
  mongodb_workload_service_account_name = var.mongodb_workload_service_account_name
  pbm_bucket_name                       = var.pbm_bucket_name
  iam_role_name                         = var.iam_role_name
  kms_key_arn                           = var.kms_key_arn
  tags                                  = var.tags
}
```

Add validation limiting `environment` to `dev|uat`, validate a 12-digit `expected_account_id`, and remove defaults for names, account, namespace, cluster, bucket, and role. Outputs must expose `mongodb_namespace`, `pbm_bucket_arn`, `pbm_role_arn`, and `mongodb_service_account_name`.

- [ ] **Step 3: Prove the extraction preserves Terraform addresses**

Because the caller remains `module.mongodb_prerequisites` and every resource name remains unchanged, the extraction must preserve addresses without `moved` blocks. Add a static test asserting the complete address inventory remains:

```python
expected = {
  "kubernetes_namespace_v1.mongodb",
  "aws_s3_bucket.pbm",
  "aws_s3_bucket_versioning.pbm",
  "aws_s3_bucket_server_side_encryption_configuration.pbm",
  "aws_s3_bucket_public_access_block.pbm",
  "aws_iam_role.mongodb_pbm",
  "aws_iam_role_policy.mongodb_pbm",
  "kubernetes_service_account_v1.mongodb_workload",
  "aws_eks_pod_identity_association.mongodb_workload",
}
module_text = root_text("modules/mongodb-prerequisites")
actual = {
  f"{resource_type}.{resource_name}"
  for resource_type, resource_name in re.findall(
    r'^resource\s+"([^"]+)"\s+"([^"]+)"', module_text, re.MULTILINE
  )
}
self.assertEqual(actual, expected)
```

Do not add no-op `moved` blocks and do not run `terraform state mv`.

- [ ] **Step 4: Run focused static validation**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_terraform_contract.TerraformContractTests.test_mongodb_root_is_environment_guarded_and_module_backed -v
terraform fmt -check -recursive platform-prerequisites/terraform/mongodb platform-prerequisites/terraform/modules/mongodb-prerequisites
```

Expected: PASS. Do not run `terraform init`, `plan`, or `apply`.

- [ ] **Step 5: Commit**

```bash
git add platform-prerequisites/terraform/mongodb platform-prerequisites/terraform/modules/mongodb-prerequisites platform-prerequisites/terraform/reusable
git commit -m "refactor: make mongodb prerequisites environment aware"
```

### Task 3: Build One Reusable Aurora Module And Two Independent Roots

**Files:**
- Create: `platform-prerequisites/terraform/modules/postgresql-cluster/main.tf`
- Create: `platform-prerequisites/terraform/modules/postgresql-cluster/variables.tf`
- Create: `platform-prerequisites/terraform/modules/postgresql-cluster/outputs.tf`
- Create: `platform-prerequisites/terraform/postgresql-core/{versions.tf,main.tf,variables.tf,outputs.tf,moved.tf}`
- Create: `platform-prerequisites/terraform/postgresql-brand/{versions.tf,main.tf,variables.tf,outputs.tf}`
- Delete: `platform-prerequisites/terraform/postgresql/main.tf`
- Delete: `platform-prerequisites/terraform/postgresql/variables.tf`
- Delete: `platform-prerequisites/terraform/postgresql/outputs.tf`
- Delete: `platform-prerequisites/terraform/postgresql/terraform.tfvars.sample`
- Delete: `platform-prerequisites/terraform/postgresql/README.md`

- [ ] **Step 1: Extend the failing test for exact module inputs**

Add this assertion to `test_postgresql_module_owns_complete_cluster_lifecycle`:

```python
for variable in (
    "environment", "cluster_role", "name_prefix", "cluster_identifier",
    "writer_identifier", "database_name", "master_username",
  "master_user_secret_kms_key_id", "eks_platform_state_key",
    "allowed_source_security_group_ids", "allowed_cidr_blocks",
    "engine_version", "instance_class", "writer_availability_zone",
    "backup_retention_period", "deletion_protection", "skip_final_snapshot",
    "final_snapshot_identifier", "enabled_cloudwatch_logs_exports",
    "cluster_parameter_group_name", "instance_parameter_group_name", "tags",
):
    self.assertIn(f'variable "{variable}"', text)
```

- [ ] **Step 2: Implement the reusable Aurora module**

The module must create distinct subnet group, security group, ingress rules, cluster parameter group, instance parameter group, Aurora cluster, and writer. Choose RDS-managed master credentials so no master password or secret value enters configuration, a plan, generated tfvars, or Terraform state as plaintext:

```hcl
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ClusterRole = var.cluster_role
    Component   = "postgresql-${var.cluster_role}"
    ManagedBy   = "terraform"
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = var.cluster_identifier
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = var.master_user_secret_kms_key_id == "" ? null : var.master_user_secret_kms_key_id
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  backup_retention_period         = var.backup_retention_period
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  storage_encrypted               = true
  apply_immediately               = false
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  tags                            = local.common_tags

  lifecycle {
    precondition {
      condition     = contains(["core", "brand"], var.cluster_role)
      error_message = "cluster_role must be core or brand."
    }
    precondition {
      condition     = var.skip_final_snapshot || length(var.final_snapshot_identifier) > 0
      error_message = "final_snapshot_identifier is required when skip_final_snapshot is false."
    }
  }
}
```

Set `log_connections=1`, `log_disconnections=1`, `log_statement=ddl`, `pgaudit.log=role,ddl,write`, and `shared_preload_libraries=pgaudit` in the cluster parameter group. Set `log_min_duration_statement=1000` in the instance parameter group. Export `postgresql` in `enabled_cloudwatch_logs_exports` for both roots.

The KMS key input is empty only until the security owner approves an environment-qualified customer-managed key; when approved, its policy grants only the required RDS and authorized runtime-reader operations. Terraform state stores the RDS-generated secret ARN and resource metadata, never the password. Database-access handlers read the selected root output `master_user_secret_arn`, call Secrets Manager at runtime after account/Region and scope verification, hold decoded credentials only in process memory or a mode-0600 ephemeral file beneath `.local/<env>/generated/`, register that file for trap cleanup, and never write a generated secret tfvars file, evidence value, command argument, or terminal output containing the credential.

- [ ] **Step 3: Create thin core and brand roots**

Both roots use the same `versions.tf` pattern as MongoDB, with AWS `allowed_account_ids`. Their `main.tf` differs only in `cluster_role`:

```hcl
module "postgresql" {
  source = "../modules/postgresql-cluster"

  environment                       = var.environment
  cluster_role                      = "core"
  name_prefix                       = var.name_prefix
  cluster_identifier                = var.cluster_identifier
  writer_identifier                 = var.writer_identifier
  database_name                     = var.database_name
  master_username                   = var.master_username
  master_user_secret_kms_key_id     = var.master_user_secret_kms_key_id
  vpc_id                            = data.terraform_remote_state.eks_platform.outputs.platform_contract.vpc_id
  private_subnet_ids                = values(data.terraform_remote_state.eks_platform.outputs.platform_contract.private_subnet_ids_by_az)
  allowed_source_security_group_ids = var.allowed_source_security_group_ids
  allowed_cidr_blocks               = var.allowed_cidr_blocks
  engine_version                    = var.engine_version
  instance_class                    = var.instance_class
  writer_availability_zone          = var.writer_availability_zone
  backup_retention_period           = var.backup_retention_period
  deletion_protection               = var.deletion_protection
  skip_final_snapshot               = var.skip_final_snapshot
  final_snapshot_identifier         = var.final_snapshot_identifier
  enabled_cloudwatch_logs_exports   = var.enabled_cloudwatch_logs_exports
  cluster_parameter_group_name      = var.cluster_parameter_group_name
  instance_parameter_group_name     = var.instance_parameter_group_name
  tags                              = var.tags
}
```

Use `cluster_role = "brand"` in the brand root. Each root configures an S3 remote-state data source whose bucket, Region, and `EKS_PLATFORM_STATE_KEY` come from the loaded environment contract; it must reject a state key outside the selected environment prefix. Consume only `data.terraform_remote_state.eks_platform.outputs.platform_contract.*`, including `values(...private_subnet_ids_by_az)` for subnets. Add fail-closed nested checks matching `aws_account_id`, `aws_region`, `environment`, `cluster_name`, and `cluster_arn` to the loaded contract; require the expected `cluster_security_group_id` and `workload_security_group_id` relationship for allowed access; and validate required `efs_file_system_id`, `efs_access_point_ids`, and `efs_security_group_id` values before any consumer uses them. Do not accept or commit manually copied network IDs, duplicate network state, or `local-input:` pseudo-values. Each root outputs cluster ID, writer ID, endpoint, reader endpoint, port, security-group ID, subnet-group name, both parameter-group names, and the RDS-managed master secret ARN. Do not output secret contents.

- [ ] **Step 4: Define explicit legacy-state migration only for the future selected root**

Create `postgresql-core/moved.tf` containing commented, non-executable documentation only until Task 12 selects the destination:

```hcl
# Dev adoption is intentionally absent. The legacy state remains at
# oms/dev/pg.tfstate until docs/operations/dev-postgresql-adoption-map.json is
# approved and a separate adoption plan supplies exact import/move operations.
```

Do not place moved/import blocks in both roots. One legacy cluster can map to exactly one future root.

- [ ] **Step 5: Run focused tests**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_terraform_contract.TerraformContractTests.test_dual_postgresql_roots_use_one_module_and_distinct_state_keys tests.phase2_data_telemetry.test_terraform_contract.TerraformContractTests.test_postgresql_module_owns_complete_cluster_lifecycle -v
terraform fmt -check -recursive platform-prerequisites/terraform/modules/postgresql-cluster platform-prerequisites/terraform/postgresql-core platform-prerequisites/terraform/postgresql-brand
```

Expected: module ownership assertions PASS. The generated-input contract remains RED until Task 5 adds environment-qualified generation and cleanup.

- [ ] **Step 6: Commit**

```bash
git add platform-prerequisites/terraform/modules/postgresql-cluster platform-prerequisites/terraform/postgresql-core platform-prerequisites/terraform/postgresql-brand platform-prerequisites/terraform/postgresql
git commit -m "feat: split core and brand aurora roots"
```

### Task 4: Extend The Existing EKS-Owned Workload Identity Maps

**Files:**
- Modify: `platform-prerequisites/terraform/environments/dev/workload-identity.tfvars`
- Modify: `platform-prerequisites/terraform/environments/uat/workload-identity.tfvars`
- Modify: `tests/phase2_data_telemetry/test_terraform_contract.py`

- [ ] **Step 1: Write the exact ownership test**

Extend `test_cloudwatch_collector_identity_has_one_owner` to parse the existing `identities` object in both environment tfvars files and assert the key set gains exactly `postgres_cloudwatch_monitor` once, with the exact namespace, ServiceAccount, policy JSON, and description shape. Also assert the EKS-owned generic root resource declarations remain unchanged:

```python
workload = root_text("workload-identity")
self.assertNotIn('resource "aws_iam_role" "postgres_cloudwatch_monitor"', workload)
self.assertNotIn('resource "aws_eks_pod_identity_association" "postgres_cloudwatch_monitor"', workload)
self.assertEqual(workload.count('resource "aws_iam_role" "identity"'), 1)
self.assertEqual(workload.count('resource "aws_eks_pod_identity_association" "identity"'), 1)
```

- [ ] **Step 2: Add one identity object to each environment map**

Data does not own a generic workload-identity root. Do not create or modify root files under `platform-prerequisites/terraform/workload-identity/`; the EKS plan owns that root, remote state, provider guard, trust policy, role naming, resources, variables, and outputs. Add only this exact-shape collector object inside each existing dev/UAT `identities` map:

```hcl
identities = {
  postgres_cloudwatch_monitor = {
    namespace       = "<mongodb|mongodb-uat>"
    service_account = "postgres-metrics-collector"
    policy_json     = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"]
        Resource = "*"
      }]
    })
    description = "Read CloudWatch metrics for the PostgreSQL collectors"
  }
}
```

Use `namespace = "mongodb"` in dev and `namespace = "mongodb-uat"` in UAT. Do not add `role_name`, `policy_actions`, or `policy_resources`; the generic root derives role names and resources. The test must prove one map entry per environment and therefore one instantiated role/policy/association for the selected environment. The PostgreSQL collector entry appears exactly once in each environment map and nowhere else.

- [ ] **Step 3: Validate and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_terraform_contract.TerraformContractTests.test_cloudwatch_collector_identity_has_one_owner -v
terraform fmt -check -recursive platform-prerequisites/terraform/workload-identity
```

Expected: PASS without Terraform initialization.

```bash
git add platform-prerequisites/terraform/environments/dev/workload-identity.tfvars \
  platform-prerequisites/terraform/environments/uat/workload-identity.tfvars \
  tests/phase2_data_telemetry/test_terraform_contract.py
git commit -m "feat: register postgres collector workload identity"
```

### Task 5: Generate Closed Nonsecret Inputs And Define Runtime Secret References

**Files:**
- Create: `config/environments/dev.local/database-access.json.example`
- Create: `config/environments/uat.local/database-access.json.example`
- Modify: `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh`
- Modify: `.gitignore`
- Modify: `tests/phase2_data_telemetry/test_terraform_contract.py`

- [ ] **Step 1: Generate scope-specific non-secret Terraform inputs**

Each handler derives immutable values from the loaded environment and writes only its own mode-0600 file beneath `.local/<env>/generated/`, for example `postgresql-core.<pid>.auto.tfvars.json`. Register every generated path through `register_generated_artifact` before invoking Terraform so foundation cleanup removes it on success, failure, or interruption. The generated shape contains account, Region, environment-qualified names, state keys, sizing, retention, allowed-source values, and the `eks-platform` remote-state backend reference. It contains no VPC/subnet/cluster copies, password, secret value, master secret ARN, or `local-input:` marker. The following is illustrative generated content, not a committed file:

```json
{
  "environment": "uat",
  "expected_account_id": "672172129937",
  "aws_region": "ap-east-1",
  "mongodb_state_key": "oms/uat/mongo.tfstate",
  "postgresql_core_state_key": "oms/uat/postgresql-core.tfstate",
  "postgresql_brand_state_key": "oms/uat/postgresql-brand.tfstate",
  "postgresql_core_cluster_identifier": "oms-uat-postgresql-core",
  "postgresql_core_writer_identifier": "oms-uat-postgresql-core-writer",
  "postgresql_core_security_group_name": "oms-uat-postgresql-core-sg",
  "postgresql_core_parameter_group_name": "oms-uat-postgresql-core-cluster-pg",
  "postgresql_core_final_snapshot_prefix": "oms-uat-postgresql-core-final",
  "postgresql_brand_cluster_identifier": "oms-uat-postgresql-brand",
  "postgresql_brand_writer_identifier": "oms-uat-postgresql-brand-writer",
  "postgresql_brand_security_group_name": "oms-uat-postgresql-brand-sg",
  "postgresql_brand_parameter_group_name": "oms-uat-postgresql-brand-cluster-pg",
  "postgresql_brand_final_snapshot_prefix": "oms-uat-postgresql-brand-final"
}
```

For dev, derive account `815402439714`, `oms/dev/...` state keys, and modeled names only if a future foundation promotion changes immutable `PROMOTION_MODE=modeled`; the current API must reject mutation before generated files or external commands. The legacy cluster ID belongs only in Task 12 inventory, never in generated Phase 2 inputs.

- [ ] **Step 2: Define local secret-reference examples**

Both canonical example files use this exact schema:

```json
{
  "mongodb_access_admin_secret_name": "replace-with-environment-qualified-mongodb-access-admin-secret",
  "postgresql_core_access_secret_arn": "RUNTIME_FROM_RDS_MANAGED_MASTER_SECRET_OUTPUT",
  "postgresql_brand_access_secret_arn": "RUNTIME_FROM_RDS_MANAGED_MASTER_SECRET_OUTPUT"
}
```

The PostgreSQL values are contract sentinels, not operator-supplied ARNs. The access handler obtains each selected root's `master_user_secret_arn` output at runtime and resolves only that ARN from Secrets Manager. It rejects a configured override, sibling-root ARN, secret value in a local file, or generated secret tfvars.

Add `.gitignore` entries:

```gitignore
config/environments/*.local/*.json
!config/environments/*.local/*.json.example
.local/
```

- [ ] **Step 3: Add secret and path isolation assertions**

Assert no committed or generated JSON contains a password, master secret ARN, network ID, subnet ID, or `local-input:` token; all generated paths are under `.local/<env>/generated/`, registered exactly once, and include environment and scope; runtime secret lookup reads only the selected root output; and no dev example contains UAT account/name/state tokens or vice versa.

- [ ] **Step 4: Run focused tests and commit**

`AUTHORIZED-ONLY` command:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_terraform_contract -v
```

Expected: all Terraform static-contract tests PASS.

```bash
git add .gitignore config/environments tests/phase2_data_telemetry/test_terraform_contract.py
git commit -m "feat: define isolated data environment inputs"
```

### Task 6: Parameterize MongoDB, Secrets, And Both PostgreSQL Collectors

**Files:**
- Modify: `k8s/base/kustomization.yaml`
- Modify: `k8s/base/psmdb-cluster.yaml`
- Modify: `k8s/base/mongodb-metrics-collector.yaml`
- Delete: `k8s/base/postgres-metrics-collector.yaml`
- Create: `k8s/base/postgres-metrics-collector-core.yaml`
- Create: `k8s/base/postgres-metrics-collector-brand.yaml`
- Modify: `k8s/overlays/dev/kustomization.yaml`
- Modify: `k8s/overlays/dev/patch-psmdb.yaml`
- Create: `k8s/overlays/dev/patch-environment.yaml`
- Create: `k8s/overlays/uat/kustomization.yaml`
- Create: `k8s/overlays/uat/patch-psmdb.yaml`
- Create: `k8s/overlays/uat/patch-environment.yaml`
- Create: `scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh`

- [ ] **Step 1: Make the base environment neutral**

Remove `dev`, fixed `mongodb` namespace fields, `pg18-dev`, and fixed Aurora identifiers/endpoints from the base. Split the PostgreSQL collector into two deployments named `postgres-metrics-collector-core` and `postgres-metrics-collector-brand`; both use ServiceAccount `postgres-metrics-collector` owned by `workload-identity`.

Each collector resource processor must include:

```yaml
resource:
  attributes:
    - key: deployment.environment
      value: ENVIRONMENT_VALUE
      action: upsert
    - key: cluster_role
      value: CLUSTER_ROLE_VALUE
      action: upsert
    - key: service.name
      value: POSTGRES_SERVICE_VALUE
      action: upsert
```

Use literal sentinel values in base (`ENVIRONMENT_VALUE`, `CLUSTER_ROLE_VALUE`, `POSTGRES_SERVICE_VALUE`) and replace them in overlays. This makes an unpatched base visibly non-runnable and statically detectable.

- [ ] **Step 2: Add complete dev and UAT overlays**

Each overlay sets `namespace`, common labels `environment` and `app.kubernetes.io/managed-by`, MongoDB replicas/storage/storage class, PBM bucket, SigNoz OTLP endpoint, core/brand writer identifiers, and all resource-processor sentinel values. Canonical namespaces are literal, not formulas: dev uses `mongodb`, `signoz`, and `boomi`; UAT uses `mongodb-uat`, `signoz-uat`, and `boomi-uat`. Collector rendering uses the loaded `POSTGRESQL_MONITOR_NAMESPACE`; it never constructs a namespace from the environment name.

Use Kustomize `replacements` sourced from one generated-safe ConfigMap:

```yaml
configMapGenerator:
  - name: environment-values
    literals:
      - environment=uat
      - mongodb_namespace=mongodb-uat
      - signoz_namespace=signoz-uat
      - postgres_core_service=oms-uat-postgresql-core
      - postgres_brand_service=oms-uat-postgresql-brand
generatorOptions:
  disableNameSuffixHash: true
commonLabels:
  environment: uat
```

Do not put passwords, secret values, or master secret ARNs in Kustomize.

- [ ] **Step 3: Add environment-qualified escrow without changing the legacy bootstrap**

Create private `data_internal_*` library functions with no canonical wrapper symbols, shebang-driven public lifecycle interface, or argument parser. Do not modify, delete, or invoke `scripts/bootstrap-dev-secrets.sh`; it remains owned by the frozen legacy dev path. The registered scope handler supplies the already-loaded environment and derives:

```bash
NAMESPACE="$MONGODB_NAMESPACE"
LOCAL_DIR="$ROOT_DIR/.local/$ENVIRONMENT/mongodb"
ENCRYPTION_ESCROW_FILE="$LOCAL_DIR/encryption-key.txt"
USERS_ESCROW_FILE="$LOCAL_DIR/operator-user-passwords.txt"
```

Create the directory with `umask 077`, reject symlinks, require mode `0700`, preserve mode `0600` for files, and implement equivalent encryption-key and Percona user reconciliation behavior without calling or changing the legacy script. The new script writes no root-level `.local-dev-*` paths. Dev mutation must pass the orchestrator's `PROMOTION_MODE` gate and call `require_environment_mutation_authorized` before `mkdir`, `openssl`, or `kubectl`.

- [ ] **Step 4: Run render and syntax tests**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_kustomize_contract -v
bash -n scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh
kubectl kustomize k8s/overlays/dev >/dev/null
kubectl kustomize k8s/overlays/uat >/dev/null
```

Expected: PASS; these commands render locally and do not contact a cluster.

- [ ] **Step 5: Commit**

```bash
git add k8s scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh tests/phase2_data_telemetry/test_kustomize_contract.py
git commit -m "feat: add environment isolated data overlays"
```

### Task 7: Implement Independent MongoDB And PostgreSQL Access Tooling

**Files:**
- Create: `tests/phase2_data_telemetry/test_access_contract.py`
- Create: `scripts/lib/database-access.sh`
- Create: `scripts/lib/packages/30-data-telemetry/internal/access.sh`
- Modify: `docs/operations/imported-code-review-matrix.md`
- Create: `config/database-access/postgresql-audit.sql`
- Create: `config/database-access/postgresql-core-grants.sql`
- Create: `config/database-access/postgresql-brand-grants.sql`

- [ ] **Step 1: Write exact canonical-row and negative-access tests**

Create `test_access_contract.py`:

```python
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config" / "database-access"
MATRIX = ROOT / "docs" / "operations" / "imported-code-review-matrix.md"


class AccessContractTests(unittest.TestCase):
    def test_canonical_imported_matrix_contains_data_domain_rows(self):
      text = MATRIX.read_text()
      for row_id in ("DATA-0001", "DATA-0002", "DATA-0003"):
        self.assertIn(row_id, text)
      self.assertNotIn("UNCLASSIFIED", text)

    def test_core_sql_explicitly_denies_boomi_roles(self):
        sql = (CONFIG / "postgresql-core-grants.sql").read_text()
        for role in ("oms_boomi_admin", "oms_boomi_process_owner"):
            self.assertIn(f"ALTER ROLE {role} NOLOGIN", sql)
            self.assertIn(f"REVOKE ALL PRIVILEGES ON DATABASE", sql)

    def test_no_competing_data_role_matrix_files_exist(self):
      self.assertEqual(list(CONFIG.glob("*role-matrix*.json")), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Append reviewed data-domain rows to the canonical imported matrix**

Append every considered MongoDB, PostgreSQL core, PostgreSQL brand, database-access, SigNoz, observability, Kubernetes, script, and configuration source item directly to `docs/operations/imported-code-review-matrix.md`. Use exactly `ID | Domain | Source | Target | Disposition | Evidence | Status`, IDs `DATA-0001`, `DATA-0002`, and so on, dispositions `KEEP|REWRITE|REPLACE|REJECT`, and statuses `PROPOSED|REVIEWED|VERIFIED`. Every `DATA-####` ID must be accepted through the foundation validator's closed domain/ID-prefix enum; this package does not widen, special-case, or parse that enum. Record rejected legacy patterns such as plaintext credentials, copied network IDs, duplicate state, hard-coded dev paths, and component-owned orchestration. Do not create another imported-code matrix, alter its schema, edit its validator, or create database role-matrix JSON files. Validate appended rows with `scripts/validate-imported-code-review-matrix.py`. The approved workforce design remains the authorization source; tests, SQL, and MongoDB reconciliation code are the machine-enforced representation.

- [ ] **Step 3: Implement shared guarded access helpers**

`scripts/lib/database-access.sh` must provide:

```bash
require_access_local_input <env>
require_access_scope <mongodb-access|database-access-core|database-access-brand>
resolve_secret_json <secret-id>
verify_postgresql_endpoint <cluster-role> <endpoint>
verify_mongodb_endpoint <endpoint>
cleanup_access_material
```

The PostgreSQL endpoint verifier compares the supplied endpoint to the selected root's `terraform output -raw postgresql_endpoint`; it must never initialize or query the sibling root. The MongoDB verifier compares namespace and replica-set service against selected environment configuration. The orchestrator's one environment lock is the only lifecycle lock; do not add an access lock. Access results remain in memory and package code creates, reads, and writes no evidence artifact. PostgreSQL runtime resolution reads `master_user_secret_arn` from only the selected root, verifies that ARN belongs to the selected account and Region, fetches it from Secrets Manager without printing it, and removes ephemeral mode-0600 secret material through registered cleanup. Ephemeral secret material is not evidence; no secret tfvars or evidence file is permitted.

- [ ] **Step 4: Implement reusable PostgreSQL access reconciliation**

The private `data_internal_configure_postgresql_access` function accepts only values already dispatched as:

```text
<core|brand> <reconcile|verify>
```

Map `core` to `database-access-core` and `postgresql-core`; map `brand` to `database-access-brand` and `postgresql-brand`. Load one admin secret, connect to one endpoint, apply `postgresql-audit.sql`, then exactly one grants file. Never loop over roles or clusters at orchestration level.

The core SQL creates/updates `oms_application_developer` with database/schema/table/sequence/function administration and explicitly executes:

```sql
ALTER ROLE oms_boomi_admin NOLOGIN;
ALTER ROLE oms_boomi_process_owner NOLOGIN;
REVOKE ALL PRIVILEGES ON DATABASE :database_name FROM oms_boomi_admin;
REVOKE ALL PRIVILEGES ON DATABASE :database_name FROM oms_boomi_process_owner;
```

The brand SQL grants the same database-admin privileges to `oms_application_developer`, `oms_boomi_admin`, and `oms_boomi_process_owner`. Infra access is not a standing login; `--break-glass-principal <name> --break-glass-ticket <id>` requires both fields and passes their validated attribution only in memory to the foundation-owned audit boundary; package code creates, reads, and writes no evidence artifact.

- [ ] **Step 5: Implement independent MongoDB access reconciliation**

Use `mongosh --file` with a generated mode-0600 JavaScript file under `.local/<env>/mongodb-access/`, removed by trap. Create named custom roles and users without printing credentials. Audit configuration must record authentication, authorization, role, DDL, and administrative events with the authenticated principal.

- [ ] **Step 6: Add mocked positive and negative tests**

Extend `test_access_contract.py` with subprocess mocks proving:

```text
database-access-core -> one core endpoint, core grants only
database-access-brand -> one brand endpoint, brand grants only
mongodb-access -> mongosh only, no psql
brand credentials used against core verifier -> rejected before psql
Boomi Admin core login verification -> expected authentication denial
Boomi Process Owner core login verification -> expected authentication denial
```

- [ ] **Step 7: Run focused tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_access_contract -v
bash -n scripts/lib/database-access.sh scripts/lib/packages/30-data-telemetry/internal/access.sh
python3 scripts/validate-imported-code-review-matrix.py docs/operations/imported-code-review-matrix.md
```

Expected: PASS using mocks only; no database connection.

```bash
git add docs/operations/imported-code-review-matrix.md \
  config/database-access scripts/lib/database-access.sh \
  scripts/lib/packages/30-data-telemetry/internal/access.sh \
  tests/phase2_data_telemetry/test_access_contract.py
git commit -m "feat: add independent database access scopes"
```

### Task 8: Add SigNoz Environment And Cluster-Role Observability

**Files:**
- Create: `gitops/signoz/overlays/dev/kustomization.yaml`
- Create: `gitops/signoz/overlays/uat/kustomization.yaml`
- Modify: `platform-prerequisites/terraform/signoz-observability/variables.tf`
- Modify: `platform-prerequisites/terraform/signoz-observability/dashboards.tf`
- Modify: `platform-prerequisites/terraform/signoz-observability/alerts.tf`
- Create: `platform-prerequisites/terraform/signoz-observability/versions.tf`
- Create: `tests/phase2_data_telemetry/test_observability_contract.py`
- Modify: `dashboards/signoz-import-pack/aws-rds-postgresql-overview.json`

- [ ] **Step 1: Write failing observability filter tests**

Create `test_observability_contract.py`:

```python
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OBS = ROOT / "platform-prerequisites/terraform/signoz-observability"


class ObservabilityContractTests(unittest.TestCase):
    def test_postgresql_dashboards_filter_environment_and_cluster_role(self):
        text = (OBS / "dashboards.tf").read_text()
        self.assertIn("var.environment", text)
        self.assertIn("cluster_role", text)
        self.assertIn('for_each = toset(["core", "brand"])', text)

    def test_postgresql_alerts_filter_environment_and_cluster_role(self):
        text = (OBS / "alerts.tf").read_text()
        for role in ("core", "brand"):
            self.assertIn(f'cluster_role = \'{role}\'', text)
        self.assertGreaterEqual(text.count("deployment.environment"), 2)

    def test_alert_labels_identify_both_dimensions(self):
        text = (OBS / "alerts.tf").read_text()
        self.assertIn("environment  = var.environment", text)
        self.assertIn("cluster_role = each.key", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Parameterize observability state and provider root**

Use Terraform >= 1.10 with `backend "s3" { use_lockfile = true }`. Add variables `environment`, `postgres_writer_instance_identifiers` as `map(string)` with exact keys `core` and `brand`, and preserve notification channels/audit service variables.

- [ ] **Step 3: Create one dashboard per cluster role**

Replace `signoz_dashboard.postgres_overview` with:

```hcl
resource "signoz_dashboard" "postgres_overview" {
  for_each = toset(["core", "brand"])
  name      = "aws-rds-postgresql-${var.environment}-${each.key}"
  title     = "${local.postgres_dashboard_json.title} (${var.environment}/${each.key})"
  description = "${local.postgres_dashboard_json.description} Filtered to environment=${var.environment}, cluster_role=${each.key}."
  version   = local.postgres_dashboard_json.version
  tags      = concat(try(local.postgres_dashboard_json.tags, []), [var.environment, each.key])
  uploaded_grafana          = try(local.postgres_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true
  layout    = jsonencode(local.postgres_dashboard_json.layout)
  widgets   = jsonencode(local.postgres_dashboard_json.widgets)
  variables = jsonencode(merge(try(local.postgres_dashboard_json.variables, {}), {
    environment  = { type = "CONSTANT", value = var.environment }
    cluster_role = { type = "CONSTANT", value = each.key }
  }))
  panel_map = length(try(local.postgres_dashboard_json.panelMap, {})) > 0 ? jsonencode(local.postgres_dashboard_json.panelMap) : null
}
```

Update every PostgreSQL widget query in the JSON template to include both `deployment.environment = {{.environment}}` and `cluster_role = {{.cluster_role}}`.

- [ ] **Step 4: Create one alert per cluster role**

Use `for_each = var.postgres_writer_instance_identifiers` for CPU/no-data alerts. Each query filter must be:

```hcl
expression = "dbinstance_identifier = '${each.value}' AND deployment.environment = '${var.environment}' AND cluster_role = '${each.key}'"
```

Each alert label map includes `environment = var.environment` and `cluster_role = each.key`; group by both dimensions where supported.

- [ ] **Step 5: Add SigNoz overlays**

Create overlays that set the literal canonical namespaces `signoz` for dev and `signoz-uat` for UAT, common `environment` labels, and environment-qualified release names. The base remains namespace-neutral; no `signoz-dev` formula is permitted.

- [ ] **Step 6: Run static tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_observability_contract tests.phase2_data_telemetry.test_kustomize_contract.KustomizeContractTests.test_signoz_overlays_are_environment_isolated -v
terraform fmt -check -recursive platform-prerequisites/terraform/signoz-observability
kubectl kustomize gitops/signoz/overlays/dev >/dev/null
kubectl kustomize gitops/signoz/overlays/uat >/dev/null
```

Expected: PASS without contacting SigNoz or Kubernetes.

```bash
git add gitops/signoz/overlays platform-prerequisites/terraform/signoz-observability dashboards/signoz-import-pack/aws-rds-postgresql-overview.json tests/phase2_data_telemetry
git commit -m "feat: split data observability by environment and role"
```

### Task 9: Supply Narrow Provision Symbols And Public Contracts

**Files:**
- Create: `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh`
- Create: `scripts/lib/scope-handlers.d/30-data-telemetry.sh`
- Modify: `tests/phase2_data_telemetry/test_lifecycle_contract.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`
- Modify: `tests/environment_orchestration/test_static_boundary.py`

- [ ] **Step 1: Define exact data handler routing**

Implement all data provision functions only in `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh`, with no canonical wrapper definitions or top-level execution:

```bash
data_internal_provision_mongodb
data_internal_provision_postgresql_core
data_internal_provision_postgresql_brand
data_internal_provision_mongodb_access
data_internal_provision_database_access_core
data_internal_provision_database_access_brand
data_internal_provision_signoz
data_internal_provision_signoz_observability
```

Each Terraform handler maps its own root internally and obtains the state-key variable through `state_key_variable_for_scope`; plan and generated paths come only from `orchestration-paths.sh`. Existing resources require a reviewed adoption record; a name match never authorizes import. The handler does not acquire a lock, parse `--env`, dispatch dependencies, or call a legacy component script.

The canonical orchestrator sequence remains: parse explicit environment/scope, pre-resolve the canonical graph, enforce `PROMOTION_MODE`, initialize paths, acquire one environment lock, call `verify_aws_identity_and_region` and other required guards, then dispatch the foundation-pre-mapped canonical handler symbol. Each mutating handler calls `require_environment_mutation_authorized` immediately before its first mutation, initializes only its selected backend, validates, writes and registers an environment/scope-qualified saved plan, prints the review command, and stops unless separately approved apply mode is active. `--auto-approve` may skip a prompt but no gate.

- [ ] **Step 2: Route Kustomize by explicit environment**

Implement the MongoDB handler's private overlay function in `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh`:

```bash
data_internal_apply_mongodb_overlay() {
  local overlay="$ROOT_DIR/k8s/overlays/$ENVIRONMENT"
  local rendered="$GENERATED_DIR/mongodb-rendered.$$.yaml"
  register_generated_artifact "$rendered"
  kubectl kustomize "$overlay" > "$rendered"
  verify_rendered_environment "$rendered" "$ENVIRONMENT" "$MONGODB_NAMESPACE"
  kubectl apply -f "$rendered"
}
```

Call the environment-qualified MongoDB bootstrap implementation only after context verification and the mutation gate, without modifying or invoking a frozen legacy component script. Route SigNoz privately to `gitops/signoz/overlays/$ENVIRONMENT`.

- [ ] **Step 3: Define only foundation-pre-mapped canonical wrappers**

`scripts/lib/scope-handlers.d/30-data-telemetry.sh` may load package internals only through `source_package_internal_library` under the foundation contract. It must contain no direct `source`/`.` command, other loader, registration call, registration data, scope/mode selection, graph/order data, dispatch, or top-level execution. It then defines only the exact canonical provision/destroy wrapper symbols returned for this package's slots by `provision_handler_for_scope` and `destroy_handler_for_scope`; each wrapper delegates directly to one distinctly named `data_internal_*` implementation function. Internal libraries must never define or reuse a pre-mapped canonical wrapper name. Tests must compare the fragment's defined symbol set to the immutable foundation allowlist and reject missing, extra, or renamed wrappers. Do not edit `scope-registry.sh`, dependencies, aliases, state mappings, deterministic `all` expansion, reverse-destroy order, the orchestrator, public entrypoints, or legacy scripts.

```bash
mongodb canonical provision wrapper -> data_internal_provision_mongodb
postgresql-core canonical provision wrapper -> data_internal_provision_postgresql_core
postgresql-brand canonical provision wrapper -> data_internal_provision_postgresql_brand
mongodb-access canonical provision wrapper -> data_internal_provision_mongodb_access
database-access-core canonical provision wrapper -> data_internal_provision_database_access_core
database-access-brand canonical provision wrapper -> data_internal_provision_database_access_brand
signoz canonical provision wrapper -> data_internal_provision_signoz
signoz-observability canonical provision wrapper -> data_internal_provision_signoz_observability
```

`workload-identity` remains entirely EKS-owned; this package changes only the existing dev/UAT environment identity maps and defines no workload-identity wrapper. The canonical graph and handler mapping already place it correctly. A failure exits before downstream handlers.

- [ ] **Step 4: Extend mocked scope-order tests**

Assert narrow scopes log only their canonical dependency closure, `all` uses the unchanged foundation order, and each foundation-pre-mapped data slot resolves to exactly one canonical wrapper. Assert both fragments contain no `register_scope_handler`, registration table, mode list, graph mutation, direct `source`/`.` command, package-internal path outside `scripts/lib/packages/30-data-telemetry/internal/`, or definitions outside their assigned allowlists. Assert every internal function is `data_internal_*`, no internal function equals a canonical wrapper symbol, and no private handler contains parser, graph, lock acquisition, direct public-script dispatch, `scripts/legacy/dev`, or legacy component-script calls. Exercise only `scripts/provision.sh`, `scripts/destroy.sh`, and `scripts/verify-platform-health.sh`; UAT never invokes `bootstrap-dev-secrets.sh` or no-`--env` paths, and missing/unknown environment fails before any mock command or `.local` creation. Mock external executables and canonical guard responses in the harness without production bypass environment variables.

- [ ] **Step 5: Run focused tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_lifecycle_contract tests.environment_orchestration.test_scope_registry tests.environment_orchestration.test_static_boundary -v
bash -n scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh scripts/lib/scope-handlers.d/30-data-telemetry.sh
```

Expected: PASS with mocks; no provisioning.

```bash
git add scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh scripts/lib/scope-handlers.d/30-data-telemetry.sh \
  tests/phase2_data_telemetry/test_lifecycle_contract.py \
  tests/environment_orchestration/test_scope_registry.py \
  tests/environment_orchestration/test_static_boundary.py
git commit -m "feat: integrate data telemetry provision scopes"
```

### Task 10: Supply Component Verifier And Pre-Destroy Guard Symbols

**Files:**
- Create: `scripts/lib/packages/30-data-telemetry/internal/verifiers.sh`
- Create: `scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh`
- Create: `scripts/lib/packages/30-data-telemetry/internal/retention.sh`
- Create: `scripts/lib/scope-verifiers.d/30-data-telemetry.sh`
- Modify: `tests/phase2_data_telemetry/test_lifecycle_contract.py`
- Modify: `tests/phase2_data_telemetry/test_access_contract.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`
- Modify: `tests/environment_orchestration/test_static_boundary.py`

- [ ] **Step 1: Fill foundation-owned verification slots**

Public verification forms are exactly:

```text
--preflight
--full
no flag, exactly equivalent to --full
--smoke-test
```

The existing public `scripts/verify-platform-health.sh` entrypoint is the only verification executable and continues to parse those modes and dispatch through `orchestrator.sh`; do not modify it. The foundation registry owns mode-to-slot lists. `scripts/lib/packages/30-data-telemetry/internal/verifiers.sh` contains component verification only and defines no pre-destroy guard. `scripts/lib/scope-verifiers.d/30-data-telemetry.sh` uses only `source_package_internal_library` under the foundation contract to source `internal/verifiers.sh`, `internal/pre-destroy-guards.sh`, and their read-only `internal/retention.sh` dependency. The fragment then alone defines the exact canonical component-verifier wrapper symbols returned by `verification_handler_for_slot`; it contains no direct `source`/`.` command, other loader, mode lists, registration calls/data, parsing, graph/order data, dispatch, or other top-level execution. Each wrapper delegates directly to one distinctly named `data_internal_*` verifier function; no internal function may equal a canonical wrapper symbol. Private verifier functions use loaded environment values instead of hard-coded account, cluster, namespaces, bucket, `pg18-dev`, or local ports. Full and smoke slots may call narrow internal checks, but there is no public component-selective verification grammar and no `verify-database-access.sh`.

- [ ] **Step 2: Add access verification with expected denials**

The private access verifier accepts one internal component slot selected by the foundation-mapped canonical wrapper. For core, test Application Developer administrative DDL in a transaction rolled back at the end, then test Boomi Admin and Process Owner credentials and require authentication/connect denial. Treat an unexpected successful core connection as a test failure.

For brand, require administrative DDL success for Application Developer, Boomi Admin, and Process Owner. For MongoDB, require Application Developer admin, Boomi Admin read/write with admin denial, and Process Owner read-only with write/admin denial. Verification keeps environment, cluster role, named principal, expected result, actual result, endpoint fingerprint, and timestamp in memory for the foundation-owned reporting boundary; package code creates, reads, and writes no evidence artifact and never retains passwords or full connection strings.

- [ ] **Step 3: Add audit and telemetry checks**

Verify PostgreSQL exported logs include named principal and configured `application_name=oms-access-<principal>`; verify collector telemetry includes `deployment.environment` and `cluster_role`; verify MongoDB audit records identify the named principal. `--smoke-test` remains runtime-authorized-only.

- [ ] **Step 4: Extend mocked tests**

Add tests proving selected-scope AWS/database calls only, successful expected denial behavior, failure on accidental Boomi core access, and no sibling endpoint/secret access.

Also lock the complete foundation-pre-mapped pre-destroy guard surface in the existing verifier fragment. The foundation fixed map already assigns one literal canonical wrapper to each data/telemetry scope; this package supplies those symbols and performs no registration. The fragment delegates one-to-one, with no generic scope switch:

```text
verify_mongodb_pre_destroy -> data_internal_guard_destroy_mongodb
verify_postgresql_core_pre_destroy -> data_internal_guard_destroy_postgresql_core
verify_postgresql_brand_pre_destroy -> data_internal_guard_destroy_postgresql_brand
verify_mongodb_access_pre_destroy -> data_internal_guard_destroy_mongodb_access
verify_database_access_core_pre_destroy -> data_internal_guard_destroy_database_access_core
verify_database_access_brand_pre_destroy -> data_internal_guard_destroy_database_access_brand
verify_signoz_pre_destroy -> data_internal_guard_destroy_signoz
verify_signoz_observability_pre_destroy -> data_internal_guard_destroy_signoz_observability
```

These canonical wrapper names are the exact symbols already returned by foundation `pre_destroy_guard_for_scope` and allowlisted for `scripts/lib/scope-verifiers.d/30-data-telemetry.sh`; implementation must not rename them, register them, or add mappings. The numbered fragment alone defines these wrappers, each delegating to one distinct `data_internal_guard_destroy_*` function in `internal/pre-destroy-guards.sh`. Each guard accepts only its fixed-scope dispatch context and no artifact path or confirmation value. After all live checks, including any failed check, it invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once and returns the same outcome. The callback digest is exact `sha256:<64 lowercase hex characters>`, computed from the SHA-256 of the foundation-canonical in-memory summary; the summary code is foundation-closed and status-compatible. Package code creates, reads, and writes no evidence artifact. Static tests reject evidence reads/writes, artifact APIs/paths, lifecycle mutation commands, internal definitions of canonical wrappers, and callback invocation outside `internal/pre-destroy-guards.sh`.

Add mocked behavioral tests proving one callback for each active guard and zero callbacks for inactive scopes. For each active scope, assert live checks finish before exactly one `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation. Assert the exact scope and canonical resource identity from the Required Upstream Interfaces table, `PASS` only when every required check passes and otherwise `FAIL`, the expected exact `sha256:<64 lowercase hex characters>` digest, and a status-compatible foundation-closed summary code. Apply identical cardinality, identity, ordering, digest, and no-artifact assertions to passing and failing sets. Mock package evidence reads/writes, general write primitives, and artifact APIs as fatal. Foundation tests alone assert durable artifact schema and path.

The guards have these non-interchangeable contracts:

```text
mongodb -> canonical psmdb/<namespace>/<name> identity; backup existence, immutable identity, recoverability, retention, PVC consequence, validated live audit contract, and dependencies
postgresql-core -> canonical rds/<region>/<account>/<core-cluster-id> identity; prepared snapshot equality, retention/protection readiness, validated live core audit contract, and dependencies; independent core status/summary/digest/code/callback; no brand lookup
postgresql-brand -> canonical rds/<region>/<account>/<brand-cluster-id> identity; prepared snapshot equality, retention/protection readiness, validated live brand audit contract, and dependencies; independent brand status/summary/digest/code/callback; no core lookup
mongodb-access -> canonical mongodb-access/<namespace>/<replica-set-service> identity; validated live MongoDB audit contract and consumer ordering
database-access-core -> canonical database-access/core/<core-cluster-id>/<core-endpoint>/<core-secret-arn> identity; validated live core audit contract and consumer ordering; no brand lookup
database-access-brand -> canonical database-access/brand/<brand-cluster-id>/<brand-endpoint>/<brand-secret-arn> identity; validated live brand audit contract and consumer ordering; no core lookup
signoz -> canonical helm/<namespace>/<release> identity; retention, live export/preservation contract, and dependencies
signoz-observability -> canonical environment/dashboard/alert-set identity using the exact sorted encoding above; live export contract where configured and dependencies
```


- [ ] **Step 5: Run focused tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_lifecycle_contract tests.phase2_data_telemetry.test_access_contract tests.environment_orchestration.test_scope_registry tests.environment_orchestration.test_static_boundary -v
bash -n scripts/lib/packages/30-data-telemetry/internal/verifiers.sh scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh scripts/lib/packages/30-data-telemetry/internal/retention.sh scripts/lib/scope-verifiers.d/30-data-telemetry.sh scripts/lib/packages/30-data-telemetry/internal/access.sh
```

Expected: PASS using mocks only. Do not run `--smoke-test`.

```bash
git add scripts/lib/packages/30-data-telemetry/internal/verifiers.sh scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh \
  scripts/lib/packages/30-data-telemetry/internal/retention.sh \
  scripts/lib/scope-verifiers.d/30-data-telemetry.sh scripts/lib/packages/30-data-telemetry/internal/access.sh \
  tests/phase2_data_telemetry tests/environment_orchestration/test_scope_registry.py \
  tests/environment_orchestration/test_static_boundary.py
git commit -m "feat: verify isolated data access and telemetry"
```

### Task 11: Integrate Reverse-Order Destruction And Independent Retention Gates

**Files:**
- Modify: `scripts/lib/packages/30-data-telemetry/internal/retention.sh`
- Modify: `scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh`
- Modify: `scripts/lib/scope-verifiers.d/30-data-telemetry.sh`
- Modify: `scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh`
- Modify: `scripts/lib/scope-handlers.d/30-data-telemetry.sh`
- Modify: `tests/phase2_data_telemetry/test_lifecycle_contract.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`
- Modify: `tests/environment_orchestration/test_static_boundary.py`

- [ ] **Step 1: Write failing retention and reverse-order tests**

Add tests proving:

```text
direct mongodb destruction requires exactly destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs
postgresql-brand confirmation cannot authorize postgresql-core
postgresql-core confirmation cannot authorize postgresql-brand
public parser rejects a missing destroy prefix, environment, account, scope, resource, or consequence before package dispatch
public parser rejects any expected-value mismatch before package dispatch
package internals contain no confirmation tokenization, field parsing, or expected-value derivation
all accepts repeated confirmations only when their ordered list exactly equals the artifact's foundation-generated union in dispatch order for selected destructive resources, including exactly destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs
all rejects a missing, duplicate, or unexpected repeated confirmation before package dispatch
every second pass requires the repository-relative path printed by its preparation pass through `--confirmation-artifact`, and rejects an omitted, absolute, stale, symlinked, escaped, or mismatched artifact before package dispatch
state-package handlers never receive or parse the confirmation-artifact path; they receive only foundation-validated confirmation values
destroying one PostgreSQL root never initializes the other state
postgresql destroy requires separately authorized deletion-protection disablement
postgresql destroy requires its unique deterministic final snapshot and configured retention
after artifact open and immutable request/artifact validation, the foundation dispatches every selected scope's pre-mapped read-only pre-destroy guard in reverse destroy order before approval, artifact consumption, or the first destroy handler
mongodb, postgresql-core, postgresql-brand, mongodb-access, database-access-core, database-access-brand, signoz, and signoz-observability each dispatch exactly its own canonical pre-destroy guard wrapper
each active data guard invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once after completing its live checks and before returning; inactive scopes invoke it zero times
callback order matches reverse guard order exactly, and each callback completes before the next guard begins or approval is requested
each callback carries the active fixed scope, exact canonical resource identity, `PASS` or `FAIL`, the exact `sha256:<64 lowercase hex characters>` digest of that scope's foundation-canonical in-memory summary, and one status-compatible foundation-allowed closed summary code
passing and failing guard outcomes each record exactly one result with the same scope and resource identity; missing, duplicate, wrong-scope, wrong-status, wrong-resource-identity, unknown or status-incompatible code, malformed or wrong digest, or out-of-order callback results fail closed before approval or artifact consumption
package guards, retention helpers, wrappers, verifiers, access helpers, and handlers never create, read, or write guard evidence or choose an evidence schema/path; only foundation callback handling may persist or read the canonical durable result artifact
mongodb guard independently verifies PBM backup completion, retained backup identity, retention, restore/recoverability evidence, MongoDB audit evidence, and access/collector dependencies
postgresql-core and postgresql-brand guards independently verify their distinct canonical cluster identities, configured backup retention, deletion-protection state, final-snapshot plan readiness, deterministic final-snapshot identifier, live audit contract, and access/collector dependencies without initializing the sibling state, and emit separate scope-specific status/identity/digest/code callback results with no shared accumulator or sibling result lookup
mongodb-access, database-access-core, and database-access-brand guards independently verify selected-scope audit evidence and dependency-removal readiness before access teardown
signoz and signoz-observability guards independently verify selected release/resource identity, configured retention, required export/preservation evidence, and dependency-removal readiness applicable to each scope
the final snapshot identifier in each guard event and foundation callback summary exactly equals the identifier generated during the matching foundation preparation pass and embedded in that scope's confirmation consequence
guard success is necessary but never the sole retention or destruction gate
any guard failure occurs before artifact consumption and package dispatch, leaves the unconsumed operation artifact byte-identical and reusable until its original expiry, and leaves infrastructure, access, package-owned evidence, plans, and generated inputs unmutated; any durable guard-result evidence is written only by the foundation callback implementation
each destroy handler immediately rechecks current account/Region and its selected resource identity/protection state after dispatch and before its first mutation
mongodb immediately rechecks current PSMDB identity, PBM backup/recoverability protection, and retained-PVC decision before access revocation or workload deletion
each PostgreSQL handler immediately rechecks selected cluster identity, deletion protection, backup retention, and exact prepared final-snapshot identifier before a protection change, plan write, or Terraform mutation
each access destroy handler immediately rechecks environment/account plus selected endpoint/namespace identity and audit-evidence dependency before revocation
signoz and signoz-observability destroy handlers immediately recheck environment/account, selected release/resource identity, retention/export protection, and dependency state before deletion or Terraform/Kubernetes mutation
an immediate recheck failure leaves the already consumed artifact consumed but leaves the selected resource and access state unmutated, requiring a new preparation pass
mongodb-access is removed before MongoDB workload
database-access-core is removed before postgresql-core
database-access-brand is removed before postgresql-brand
workload-identity is removed only after both PostgreSQL collectors are absent
ordinary all destruction never deletes backend or access-governance
dev destroy fails before external commands and local mutation
```

- [ ] **Step 2: Consume foundation-parsed exact retention contracts**

Persistent destroy is invoked only through the foundation public interface:

```bash
# Preparation pass: prints the repository-relative artifact path and exact confirmations,
# performs no mutation, and exits nonzero.
bash scripts/destroy.sh --env <dev|uat> <scope>

# Execution pass: repeats the printed path and every printed confirmation verbatim.
bash scripts/destroy.sh --env <dev|uat> <scope> \
  --confirmation-artifact '<repository-relative-path-printed-by-preparation-pass>' \
  --confirm 'destroy:<env>:<account>:<scope>:<resource>:<consequence>'
```

The repeatable foundation-owned grammar is exactly `destroy:<env>:<account>:<scope>:<resource>:<consequence>`. The foundation parser derives and validates the complete ordered confirmation list and operation artifact before dispatch. It invokes selected pre-mapped guards in reverse destroy order; each guard invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once after all live checks and returns the same outcome. The foundation validates callback cardinality, order, status, canonical resource identity, SHA-256 digest, and status-compatible closed summary code and alone persists accepted results. Only all-`PASS` results proceed to approval and atomic operation-artifact consumption. A `FAIL` result leaves the operation artifact unconsumed and causes no package or infrastructure mutation. Package code creates, reads, and writes no evidence artifact and receives only foundation-validated confirmation values. A narrow scope supplies its exact required confirmation; `all` supplies repeated `--confirm` options in the artifact's registry dispatch order, equal to the ordered union for selected destructive resources.

Exact examples are:

```text
destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs
destroy:uat:672172129937:postgresql-core:db/<cluster-id>:final-snapshot=<deterministic-id>
destroy:uat:672172129937:postgresql-brand:db/<cluster-id>:final-snapshot=<deterministic-id>
```

The first `all` invocation without confirmations is the foundation-owned preparation pass: it writes the mode-`0600` operation artifact, prints its repository-relative path and the exact follow-up confirmation arguments, exits nonzero, and performs no mutation. The second invocation supplies that printed artifact path and repeats every printed confirmation rather than combining values or using an `all`-specific token. The transcript shape is:

```bash
bash scripts/destroy.sh --env uat all
# output: Confirmation artifact: .local/uat/generated/<foundation-operation-artifact>
# output: --confirm 'destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster'
# output: --confirm 'destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs'
# output: --confirm 'destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs'
# output: --confirm '<exact-postgresql-core-value-printed-by-preparation-pass>'
# output: --confirm '<exact-postgresql-brand-value-printed-by-preparation-pass>'

bash scripts/destroy.sh --env uat all \
  --confirmation-artifact '.local/uat/generated/<foundation-operation-artifact>' \
  --confirm 'destroy:uat:672172129937:eks-platform:EKS-boomi-runtime-cluster:delete-cluster' \
  --confirm 'destroy:uat:672172129937:boomi-runtime:runtime/boomi-uat:retain-efs' \
  --confirm 'destroy:uat:672172129937:mongodb:psmdb/mongodb-uat/oms:delete-cluster-and-pvcs' \
  --confirm '<exact-postgresql-core-value-printed-by-preparation-pass>' \
  --confirm '<exact-postgresql-brand-value-printed-by-preparation-pass>'
```

Every angle-bracket value above denotes output printed by the first invocation; each is a documentation placeholder and is rejected if entered literally. Operators do not invent artifact names, operation identities, or snapshot timestamps, and there is no package-owned executable or parser. Tests retain the preparation helper's symlink, strict-resolution, generated-root containment, regular-file, and mode checks while returning both the repository-relative artifact path and the selected confirmation value for the second pass.

For PostgreSQL, `<deterministic-id>` is derived once by the foundation preparation pass from the configured final-snapshot prefix and deterministic operation identity; callers, guards, and handlers do not invent suffixes. The foundation supplies it as read-only dispatch context, the selected guard compares it with that root's final-snapshot plan and live retention contract, and the handler rechecks exact equality immediately before mutation. Package guard and retention files receive no artifact path, parse no confirmation grammar, and create, read, and write no evidence artifact. Core and brand use separate selected states, prepared IDs, live retention checks, canonical identities, summaries, digests, statuses, summary codes, and callback results. MongoDB backup/recoverability/retention, PBM object identity, PVC consequence, live audit contract, and dependencies remain separate mandatory live checks. Access and SigNoz scopes likewise use scope-specific live audit, retention/export, and dependency contracts. No single check, confirmation, or protection value is sufficient alone; no package-local parser or alternate confirmation channel is permitted.

#### Controlling Pre-Destroy Evidence Boundary

This subsection replaces any ambiguous older use of "retention evidence" or "artifact-free" in this plan. Data guards, access helpers, verifiers, retention helpers, wrappers, and lifecycle handlers may query validated live source contracts but never receive a foundation operation-artifact or durable-evidence-artifact path and never create, read, update, consume, rename, register, or delete evidence. Each active guard accumulates its outcomes only in memory and invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once after all checks and before return, then returns the same pass/fail status. Inactive scopes invoke it zero times. The foundation alone validates callback scope, status, canonical resource identity, cardinality, order, summary code, and SHA-256 digest and owns the canonical durable guard-result artifact, schema, and path.

PostgreSQL core and brand use separate live checks, accumulators, prepared snapshot IDs, canonical summaries, digests, closed codes, and callback calls. Selecting both produces two independent results; neither guard reads sibling state, shares a result accumulator, or inspects the sibling callback result. Package wrappers, retention helpers, verifiers, and lifecycle handlers never invoke the callback, and no package file writes guard evidence.

- [ ] **Step 3: Implement narrow data destruction**

Narrow scope functions are:

```bash
data_internal_destroy_mongodb_access
data_internal_destroy_database_access core
data_internal_destroy_database_access brand
data_internal_destroy_signoz_observability
data_internal_destroy_signoz
data_internal_destroy_mongodb
data_internal_destroy_postgresql brand
data_internal_destroy_postgresql core
```

Define the exact foundation-pre-mapped canonical data destroy wrappers only in `30-data-telemetry.sh`; each delegates to one distinct `data_internal_*` function. Define the exact foundation-pre-mapped canonical pre-destroy guard wrappers only in the existing numbered verifier fragment as specified by Task 10; each delegates to its fixed, distinct `data_internal_guard_destroy_*` function in `internal/pre-destroy-guards.sh`. The fragment sources both validated implementation files, `internal/verifiers.sh` and `internal/pre-destroy-guards.sh`, plus `internal/retention.sh`, only through `source_package_internal_library`. Do not register either class of wrapper and do not implement an `all` function, sequence, confirmation parser, guard registry, or confirmation-set union in this package. Data defines no `destroy_workload_identity`; the EKS-owned wrapper performs that removal after the foundation reverse graph proves both PostgreSQL collectors are absent.

`data_internal_guard_destroy_mongodb` independently verifies the current PSMDB identity; latest successful PBM backup and immutable bucket object identity; configured retention; restore/recoverability proof; retained-PVC consequence; required MongoDB audit evidence; and that access/collector dependency state permits the requested operation. `data_internal_guard_destroy_postgresql_core` and `data_internal_guard_destroy_postgresql_brand` each use only their selected Terraform state and AWS cluster, and independently verify cluster identity, backup retention, current deletion protection, separately authorized protection-disable readiness, audit evidence, access/collector dependency state, and an executable final-snapshot plan whose identifier exactly equals the prepared foundation snapshot ID embedded in that scope's artifact consequence. The three access guards use only their selected endpoint or namespace and independently verify audit evidence plus consumer-before-provider dependency-removal readiness. `data_internal_guard_destroy_signoz` and `data_internal_guard_destroy_signoz_observability` independently verify their selected release/resources, applicable retention and export/preservation evidence, and consumer/dependency ordering. None reads or writes a foundation operation artifact, and none writes evidence, generated inputs, plans, markers, temporary files, or infrastructure while guarding; each validates pre-existing state and evidence read-only.

Every destroy handler treats the pre-consumption guard result as stale immediately after dispatch. It first rechecks the loaded environment, canonical account/Region identity, and then the selected resource identity and protection state immediately before its first mutation. `data_internal_destroy_postgresql brand` uses only the `postgresql-brand` root/state/registered plan, the foundation environment lock, and the foundation-validated exact brand confirmation; it rechecks deletion protection, retention, and exact artifact-prepared snapshot ID before any protection change, plan write, or Terraform action. Core is separate and identical in ordering. MongoDB rechecks exact PSMDB identity, PBM backup/recoverability protection, and the retained-PVC consequence before access revocation, workload deletion, or PVC action. Access handlers recheck selected endpoint/namespace identity and audit-evidence dependency before revocation. SigNoz handlers recheck selected release/resource identity, applicable retention/export protection, and dependencies before deletion or Terraform/Kubernetes action. No handler is the sole retention gate and no handler uses retention as its only authorization. MongoDB separates access revocation, workload deletion, backup evidence, retained PVC decision, and Terraform prerequisites; record partial completion and permit safe retry.

- [ ] **Step 4: Run focused mocked tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_lifecycle_contract tests.environment_orchestration.test_scope_registry tests.environment_orchestration.test_static_boundary -v
bash -n scripts/lib/packages/30-data-telemetry/internal/retention.sh scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh scripts/lib/packages/30-data-telemetry/internal/verifiers.sh scripts/lib/scope-verifiers.d/30-data-telemetry.sh scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh scripts/lib/scope-handlers.d/30-data-telemetry.sh
```

Expected: PASS with mocks; no destroy command reaches AWS, Kubernetes, Terraform, or a database.

```bash
git add scripts/lib/packages/30-data-telemetry/internal/retention.sh \
  scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh \
  scripts/lib/packages/30-data-telemetry/internal/verifiers.sh scripts/lib/scope-verifiers.d/30-data-telemetry.sh \
  scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh scripts/lib/scope-handlers.d/30-data-telemetry.sh \
  tests/phase2_data_telemetry/test_lifecycle_contract.py tests/environment_orchestration/test_scope_registry.py \
  tests/environment_orchestration/test_static_boundary.py
git commit -m "feat: guard independent data destruction"
```

### Task 12: Create Read-Only Dev Legacy PostgreSQL Mapping And Adoption Artifacts

**Files:**
- Create: `scripts/inventory-dev-postgresql.sh`
- Create: `docs/operations/dev-postgresql-legacy-inventory.json`
- Create: `docs/operations/dev-postgresql-adoption-map.json`
- Create: `tests/phase2_data_telemetry/test_dev_adoption_contract.py`

- [ ] **Step 1: Write failing no-mutation and one-destination tests**

Create `test_dev_adoption_contract.py`:

```python
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class DevAdoptionContractTests(unittest.TestCase):
    def test_legacy_state_maps_to_exactly_one_destination(self):
        mapping = json.loads(
            (ROOT / "docs/operations/dev-postgresql-adoption-map.json").read_text()
        )
        self.assertEqual(mapping["legacy_state_key"], "oms/dev/pg.tfstate")
        self.assertIn(mapping["selected_destination"], ("postgresql-core", "postgresql-brand"))
        self.assertEqual(len(mapping["destinations"]), 1)
        self.assertEqual(mapping["status"], "read-only-pending-approval")

    def test_inventory_script_is_read_only(self):
        text = (ROOT / "scripts/inventory-dev-postgresql.sh").read_text()
        for forbidden in ("apply", "destroy", "import", "state mv", "kubectl apply", "aws rds modify"):
            self.assertNotIn(forbidden, text)
        self.assertIn("terraform state pull", text)
        self.assertIn("aws rds describe-db-clusters", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Implement read-only inventory**

The script requires `--env dev --output <path>`, verifies dev account `815402439714`, reads `oms/dev/pg.tfstate` using `terraform state pull`, and uses only `aws rds describe-db-clusters`, `describe-db-instances`, `describe-db-cluster-parameters`, `describe-db-parameters`, and `list-tags-for-resource`. It writes normalized identifiers, Terraform addresses, subnet/security/parameter groups, secret handling mode, engine/version, backup/logging/deletion settings, endpoints hashed with SHA-256, and capture timestamp. It never writes backend config into the legacy root and never initializes a Phase 2 destination root.

- [ ] **Step 3: Create committed reviewed artifacts**

Generate the inventory only after read-only AWS access is separately authorized. After the owner selects `postgresql-core` or `postgresql-brand` from business ownership evidence, generate the mapping directly from the captured inventory so no example identifier can leak into the artifact:

```bash
legacy_cluster_identifier="$(jq -er '.cluster.cluster_identifier' docs/operations/dev-postgresql-legacy-inventory.json)"
selected_destination="postgresql-core"
missing_destination="postgresql-brand"
jq -n \
  --arg legacy_cluster_identifier "$legacy_cluster_identifier" \
  --arg selected_destination "$selected_destination" \
  --arg missing_cluster_action "create-${missing_destination}-under-separate-approved-plan" \
  '{
    status: "read-only-pending-approval",
    legacy_source: "frozen legacy dev PostgreSQL state and inventory",
    legacy_state_key: "oms/dev/pg.tfstate",
    legacy_cluster_identifier: $legacy_cluster_identifier,
    selected_destination: $selected_destination,
    destinations: [$selected_destination],
    missing_cluster_action: $missing_cluster_action,
    state_operations_authorized: false,
    dev_mutation_authorized: false
  }' > docs/operations/dev-postgresql-adoption-map.json
```

The assignments shown encode the approved core selection only if ownership evidence reaches that conclusion. If evidence selects brand, set `selected_destination=postgresql-brand` and `missing_destination=postgresql-core`. Never choose merely because the old command was named `pg`. If evidence cannot decide, do not create the mapping artifact and stop for owner approval.

- [ ] **Step 4: Document adoption prohibition**

State that no import, move, duplicate cluster creation, or dev apply/destroy is authorized; list the future state backup, reviewed import/move, no-create/no-replace/no-destroy plan, and promotion approvals required.

- [ ] **Step 5: Run static tests and commit**

`AUTHORIZED-ONLY` commands:

```bash
python3 -m unittest tests.phase2_data_telemetry.test_dev_adoption_contract -v
bash -n scripts/inventory-dev-postgresql.sh
```

Expected: PASS. The inventory command itself is not run without explicit read-only AWS authorization.

```bash
git add scripts/inventory-dev-postgresql.sh \
  docs/operations/dev-postgresql-legacy-inventory.json \
  docs/operations/dev-postgresql-adoption-map.json \
  tests/phase2_data_telemetry/test_dev_adoption_contract.py
git commit -m "docs: map legacy dev postgresql adoption"
```

### Task 13: Defer Shared Documentation

**Files:**
- None.

- [ ] **Step 1: Preserve the package boundary**

Do not create or modify shared reference, navigation, operator, setup, recovery, verification-command, SigNoz, README, or component-catalog documentation in this package. The later documentation/acceptance/adoption package owns all shared documentation. The only documentation ledger touched here is the foundation-owned `docs/operations/imported-code-review-matrix.md`, solely to append reviewed `DATA-####` rows.

- [ ] **Step 2: Hand off exact documentation requirements**

Record in the later documentation/acceptance/adoption package that operator and recovery documentation must describe the foundation-owned two-pass operation-artifact workflow, all eight pre-mapped data/telemetry pre-destroy guards, reverse destroy ordering, and the guard-result evidence boundary: every active guard invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once after its live checks, including on failure, and package code creates, reads, and writes no evidence artifact; the foundation alone owns the canonical durable artifact, schema, and path. Document all eight canonical resource-identity encodings, status-compatible closed summary codes, and that guard failure leaves the operation artifact unconsumed with no mutation/dispatch while still requiring exactly one `FAIL` result. Also cover immediate post-consumption handler rechecks, MongoDB PBM/PVC consequences, independent core/brand PostgreSQL final-snapshot IDs and independent callback results, access consumer ordering, and applicable SigNoz retention/export dependencies. Documentation must preserve the dual PostgreSQL state and evidence boundaries and must not describe a package-owned registration, parser, evidence reader/writer, artifact consumer, schema/path, or alternate destroy entrypoint.

### Task 14: Run The Authorized Static Acceptance Suite

**Files:**
- Modify only package-owned files required to fix failures introduced by Tasks 1-13. Do not use acceptance failures to edit foundation public/legacy scripts or shared documentation.

- [ ] **Step 1: Run Python contract tests**

`AUTHORIZED-ONLY` local command:

```bash
python3 -m unittest discover -s tests/phase2_data_telemetry -p 'test_*.py' -v
```

Expected: all tests PASS; mock logs prove independent states, access scopes, negative core access, and lifecycle isolation.

Public contract coverage must invoke only `scripts/provision.sh`, `scripts/destroy.sh`, and `scripts/verify-platform-health.sh`. It must exercise verification as exact `--preflight`, exact `--full`, no flag with behavior identical to `--full`, and exact `--smoke-test`. The harness mocks external executables and canonical guard responses; it does not invoke `provision-platform-prereq.sh` and does not set production dry-run, live-preflight skip, or similar bypass variables.

Destroy acceptance must additionally assert the exact second-pass event order: operation artifact open; immutable request/artifact validation; for each selected data scope in reverse destroy order, live guard checks then exactly one `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation; completion of foundation-owned durable result recording; approval only after all results are `PASS`; operation-artifact identity/expiry revalidation; atomic consumed rename; canonical destroy dispatch; handler environment/account/resource identity and protection recheck; first mutation. Assert inactive scopes produce no callback; missing, duplicate, wrong-scope, wrong-status, wrong-resource-identity, unknown or status-incompatible code, malformed or wrong digest, and out-of-order callbacks fail closed before approval. Inject both passing and failing check outcomes at each of the eight guards and assert one callback per active scope, exact canonical resource identity, expected `PASS` or `FAIL`, expected status-compatible code and canonical-summary SHA-256 digest, unchanged operation-artifact bytes and filename on guard failure, no consumed marker, no handler dispatch, and empty package command/evidence-read/evidence-write/generated-input/write logs. Foundation-specific tests assert the canonical durable guard-result artifact schema and path. Inject a failure at each handler's immediate recheck and assert the consumed marker remains, no selected resource or access mutation occurs, and retry with the old artifact is rejected. Core/brand fixtures must prove the preparation snapshot ID, operation-artifact consequence, guard input, live retention contract, generated Terraform input, saved-plan expectation, destroy confirmation, and scope-specific callback digest input are one identical value with no sibling-root or sibling-result lookup; when both scopes are selected, they produce two independent callback results with distinct canonical resource identities.

- [ ] **Step 2: Run shell syntax checks**

`AUTHORIZED-ONLY` local command:

```bash
bash -n scripts/inventory-dev-postgresql.sh scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh scripts/lib/packages/30-data-telemetry/internal/access.sh scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh scripts/lib/packages/30-data-telemetry/internal/verifiers.sh scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh scripts/lib/packages/30-data-telemetry/internal/retention.sh scripts/lib/database-access.sh scripts/lib/scope-handlers.d/30-data-telemetry.sh scripts/lib/scope-verifiers.d/30-data-telemetry.sh
```

Expected: exit 0.

- [ ] **Step 3: Run local render checks**

`AUTHORIZED-ONLY` local commands:

```bash
kubectl kustomize k8s/overlays/dev >/dev/null
kubectl kustomize k8s/overlays/uat >/dev/null
kubectl kustomize gitops/signoz/overlays/dev >/dev/null
kubectl kustomize gitops/signoz/overlays/uat >/dev/null
```

Expected: exit 0 with no cluster contact.

- [ ] **Step 4: Run Terraform formatting and offline validation where providers are already cached**

`AUTHORIZED-ONLY` local commands:

```bash
terraform fmt -check -recursive platform-prerequisites/terraform
for root in mongodb postgresql-core postgresql-brand workload-identity signoz-observability; do
  terraform -chdir="platform-prerequisites/terraform/$root" validate
done
```

Expected: formatting and validation PASS. Do not run `terraform init`; if provider schemas are not already cached, record validation as unavailable rather than contacting registries without authorization.

- [ ] **Step 5: Confirm no forbidden execution occurred**

`AUTHORIZED-ONLY` local commands:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: only planned implementation files changed; no `.terraform`, plan, state, generated secret, `.local`, rendered manifest, or evidence file containing credentials is staged.

- [ ] **Step 6: Commit acceptance fixes**

```bash
git add tests/phase2_data_telemetry tests/environment_orchestration \
  scripts/lib/packages/30-data-telemetry/internal/bootstrap.sh \
  scripts/lib/packages/30-data-telemetry/internal/access.sh \
  scripts/lib/packages/30-data-telemetry/internal/lifecycle.sh \
  scripts/lib/packages/30-data-telemetry/internal/verifiers.sh \
  scripts/lib/packages/30-data-telemetry/internal/pre-destroy-guards.sh \
  scripts/lib/packages/30-data-telemetry/internal/retention.sh scripts/lib/database-access.sh \
  scripts/lib/scope-handlers.d/30-data-telemetry.sh \
  scripts/lib/scope-verifiers.d/30-data-telemetry.sh \
  scripts/inventory-dev-postgresql.sh config/database-access config/environments \
  k8s gitops platform-prerequisites dashboards \
  docs/operations/imported-code-review-matrix.md \
  docs/operations/dev-postgresql-legacy-inventory.json \
  docs/operations/dev-postgresql-adoption-map.json .gitignore
git commit -m "test: verify phase2 data telemetry contracts"
```

## Deferred Runtime Acceptance

Do not execute these commands during implementation unless the user explicitly authorizes UAT provisioning/testing in the current conversation. The canonical registry, not this displayed list, owns dependency ordering; when authorized, invoke public scopes and retain environment-qualified evidence:

```bash
# AUTHORIZED-ONLY UAT RUNTIME ACCEPTANCE
bash scripts/verify-platform-health.sh --env uat --preflight
bash scripts/provision.sh --env uat mongodb
bash scripts/provision.sh --env uat postgresql-core
bash scripts/provision.sh --env uat postgresql-brand
bash scripts/provision.sh --env uat mongodb-access
bash scripts/provision.sh --env uat database-access-core
bash scripts/provision.sh --env uat database-access-brand
bash scripts/provision.sh --env uat signoz
bash scripts/provision.sh --env uat signoz-observability
bash scripts/verify-platform-health.sh --env uat --full
bash scripts/verify-platform-health.sh --env uat
bash scripts/verify-platform-health.sh --env uat --smoke-test
```

Runtime acceptance must additionally prove:

1. A no-drift plan for each of the five Terraform roots.
2. Brand credentials and network paths cannot authenticate to or reach core.
3. Boomi Admin and Process Owner core logins fail while their brand administration succeeds.
4. Named principals and `cluster_role` appear in PostgreSQL audit logs.
5. Dashboards and alerts separate `dev|uat` and `core|brand` dimensions.
6. Plan/change/access update/restore/destroy for one PostgreSQL cluster does not initialize or drift the other state.
7. Full reverse-order UAT destroy preserves backend and governance, followed by a clean rebuild.

Dev inventory commands require separate read-only authorization. Dev import, plan, apply, destroy, secret rotation, Kubernetes mutation, and database mutation remain prohibited until the approved dev adoption plan and promotion gate explicitly authorize them.

## Required Execution Order

Implement Tasks 1-10 before Task 11 so the immutable foundation map, all eight canonical verifier-fragment wrappers, their distinct package-internal guard delegates, and the dual PostgreSQL contracts are locked before destructive behavior is added. Task 11 adds only package-internal retention checks and destroy handlers against those fixed interfaces; it does not register symbols or alter foundation ordering. Complete the read-only dev mapping and documentation handoff in Tasks 12-13, then run Task 14 only after separate authorization for local validation and commits. Deferred runtime acceptance remains separately authorized and is never implied by completion of this plan.

## Completion Criteria

Implementation is complete only after separately authorized checks prove all of the following:

1. The foundation fixed map resolves exactly one pre-destroy guard wrapper for each of `mongodb`, `postgresql-core`, `postgresql-brand`, `mongodb-access`, `database-access-core`, `database-access-brand`, `signoz`, and `signoz-observability`; `scripts/lib/scope-verifiers.d/30-data-telemetry.sh` defines those pre-mapped symbols with no registration.
2. The numbered verifier fragment sources the validated `internal/verifiers.sh` and `internal/pre-destroy-guards.sh` files, plus read-only `internal/retention.sh`, only through `source_package_internal_library`; it alone defines all canonical component-verifier and guard wrappers. Every guard wrapper delegates one-to-one to a distinct `data_internal_guard_destroy_*` function defined only in `internal/pre-destroy-guards.sh`, and no internal symbol equals a canonical wrapper name.
3. Foundation tests prove operation-artifact open/validation precedes reverse-order selected guards; each active guard's live checks precede exactly one `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation; callbacks preserve reverse guard order and complete before approval, operation-artifact consumption, and destroy dispatch. Inactive scopes produce zero callbacks. Missing, duplicate, wrong-scope, wrong-status, wrong-resource-identity, unknown or status-incompatible code, malformed or wrong digest, or out-of-order results fail closed. Every failed guard still records exactly one `FAIL` result, leaves the original operation artifact byte-identical and unconsumed, and causes no package mutation, package evidence read/write, generated input, plan, or handler dispatch.
4. Every package guard, access helper, verifier, retention helper, wrapper, and lifecycle handler is evidence-artifact-free, and every guard and retention helper is read-only with respect to files and infrastructure. Each active guard derives its exact canonical resource identity, computes one lowercase SHA-256 digest over its foundation-canonical in-memory summary, selects one status-compatible foundation-closed summary code, and invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once; retention helpers never invoke the callback. The foundation alone owns validation and persistence of the canonical durable artifact, schema, and path. MongoDB proves exact identity, backup/recoverability/retention, PVC consequence, live audit contract, and dependencies. Core and brand PostgreSQL independently prove their distinct exact identities, prepared snapshot equality, retention/protection readiness, live audit contracts, and dependencies without sibling-state or sibling-result access. The access scopes prove exact identities, live audit contracts, and consumer ordering. SigNoz scopes prove exact validated release/resource-set identities, applicable retention/export, and dependencies.
5. `internal/lifecycle.sh` remains the sole package owner of lifecycle mutation, while `internal/retention.sh` remains a separate read-only check library. After artifact consumption, every destroy handler immediately rechecks environment, account/Region, selected resource identity, and applicable protection state before mutation. Handler rechecks remain a defense against stale guard results and are not the sole retention gate.
6. The dual PostgreSQL roots, state objects, snapshot IDs, retention evidence, access paths, digest inputs, summary codes, callback results, and no-sibling-lookup tests remain independent; the foundation operation-artifact contract, durable guard-result evidence contract, and exact confirmation grammar remain unchanged.
7. Package-owned tests, acceptance ordering, later shared-documentation requirements, and reverse destroy ordering encode the same contract, and no task reports provisioning, destruction, validation, commit, or runtime acceptance that was not separately authorized and actually performed.

This plan update reports no execution, tests, Git operation, provisioning, mutation, destruction, or commit.