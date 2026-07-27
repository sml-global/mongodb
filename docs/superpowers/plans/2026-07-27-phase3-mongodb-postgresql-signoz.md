# Phase 3 MongoDB + PostgreSQL + SigNoz Platform Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the MongoDB (Percona PSMDB Operator), PostgreSQL (CloudNativePG), and SigNoz observability platform onto the Phase 2 EKS cluster, wiring each service through the Phase 2 workload identity root (IRSA) with zero hardcoded credentials.

**Architecture:** Phase 3 consumes the Phase 2 `platform_contract` outputs as the sole source of namespace, IAM role ARNs, and service account names. Terraform handles infrastructure prerequisites (KMS, IRSA policies, EBS/EFS bindings); GitOps (Flux) handles Kubernetes operator deployment and CRD instantiation. Every scope — `mongodb`, `postgresql-core`, `postgresql-brand`, `mongodb-access`, `signoz`, `signoz-observability` — follows the same handler/verifier/guard pattern established in Phase 2. No scope may bypass the foundation registry or the workload identity root.

**Tech Stack:** Bash 3.2, Python 3 `unittest`, Terraform >= 1.10, AWS provider >= 6.0 and < 7.0, AWS CLI v2, Kubernetes/Kustomize, Helm, Flux, Percona PSMDB Operator, CloudNativePG, SigNoz, Amazon EBS CSI, Amazon EFS, AWS Backup, AWS KMS, IRSA (EKS Pod Identity)

---

## Architectural Decisions (Locked Before Implementation)

### Decision 1: AWS Testing Strategy for Phase 3

Phase 2 used `terraform plan` only — no `terraform apply`. Phase 3 introduces stateful Kubernetes operators that require a running EKS cluster to validate CRD behavior.

**Resolution:**
- **Terraform validation:** `terraform plan` only (same as Phase 2) for all Terraform modules. No actual cluster apply in sandbox.
- **Operator validation:** Unit tests mock `kubectl`/`helm` invocations. Static manifest rendering via `kustomize build` and `helm template` validates YAML correctness without a live cluster.
- **Integration gate:** Gate 2 for Phase 3 requires `terraform plan` to succeed **and** `kustomize build` + `helm template` to produce valid, non-empty manifests.
- **No sandbox apply required:** Phase 3 follows the same read-only validation discipline as Phase 2.

### Decision 2: Terraform vs GitOps Boundary

| Layer | Owner | Examples |
|-------|-------|---------|
| **Terraform** | Infrastructure provisioning | IRSA roles, KMS keys, EBS/EFS storage classes, S3 buckets (PBM), namespace creation, PodDisruptionBudgets |
| **GitOps (Flux)** | Kubernetes workload delivery | Operator Deployments, CRDs, OperatorGroups, Helm releases, PSMDB cluster CRs, CNPGcluster CRs, SigNoz chart |

Terraform outputs feed GitOps values via `platform_contract` and Kubernetes ConfigMaps. GitOps never calls AWS APIs directly.

### Decision 3: Workload Identity Enforcement Gate

Every database/operator that accesses AWS APIs (S3 for PBM backups, KMS for encryption) **must** use the IRSA service account defined in Phase 2's `platform_contract` outputs. This is enforced by:

1. A static test asserting no Kubernetes `serviceAccountName` appears in Phase 3 manifests outside the Phase 2 contract values.
2. A Terraform `check` block verifying the `operator_iam_role_arn` output from Phase 2 state is non-empty before Phase 3 Terraform runs.

---

## Foundation Contract (Phase 3 reads, never modifies)

- `platform_contract.mongodb_namespace` — Kubernetes namespace for MongoDB operator
- `platform_contract.pbm_bucket_name` — S3 bucket for Percona Backup for MongoDB
- `platform_contract.operator_iam_role_arn` — IRSA role ARN for MongoDB PBM service account
- `platform_contract.mongodb_workload_service_account` — Service account name for MongoDB workload pods
- Scope registry already contains: `mongodb`, `postgresql-core`, `postgresql-brand`, `mongodb-access`, `signoz`, `signoz-observability`
- Provision order (from registry): mongodb → postgresql-core → postgresql-brand → mongodb-access → signoz → signoz-observability
- Destroy order (from registry): reverse of provision order

---

## File Structure

### New Files (Phase 3)

**Terraform Infrastructure:**
- `platform-prerequisites/terraform/mongodb/main.tf` — PSMDB IRSA policy, PBM S3 binding, KMS grant
- `platform-prerequisites/terraform/mongodb/variables.tf`
- `platform-prerequisites/terraform/mongodb/outputs.tf`
- `platform-prerequisites/terraform/mongodb/versions.tf`
- `platform-prerequisites/terraform/postgresql/main.tf` — CNPG IRSA policy, backup bucket, KMS grant
- `platform-prerequisites/terraform/postgresql/variables.tf`
- `platform-prerequisites/terraform/postgresql/outputs.tf`
- `platform-prerequisites/terraform/postgresql/versions.tf`
- `platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars`
- `platform-prerequisites/terraform/environments/sandbox/postgresql.tfvars`

**GitOps Manifests:**
- `gitops/mongodb/base/kustomization.yaml`
- `gitops/mongodb/base/namespace.yaml`
- `gitops/mongodb/base/operator.yaml` — PSMDB Operator HelmRelease
- `gitops/mongodb/base/cluster.yaml` — PerconaServerMongoDB CR
- `gitops/mongodb/overlays/uat/kustomization.yaml`
- `gitops/mongodb/overlays/uat/cluster-patch.yaml`
- `gitops/postgresql/base/kustomization.yaml`
- `gitops/postgresql/base/operator.yaml` — CloudNativePG HelmRelease
- `gitops/postgresql/base/cluster.yaml` — Cluster CR
- `gitops/postgresql/overlays/uat/kustomization.yaml`
- `gitops/signoz/base/kustomization.yaml` (already partially present in `k8s/`)
- `gitops/signoz/base/helmrelease.yaml`
- `gitops/signoz/overlays/uat/kustomization.yaml`

**Handler/Verifier Packages:**
- `scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh`
- `scripts/lib/packages/30-mongodb/internal/verifiers.sh`
- `scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh`
- `scripts/lib/scope-handlers.d/30-mongodb.sh`
- `scripts/lib/scope-verifiers.d/30-mongodb.sh`
- `scripts/lib/packages/40-postgresql/internal/lifecycle-handlers.sh`
- `scripts/lib/packages/40-postgresql/internal/verifiers.sh`
- `scripts/lib/packages/40-postgresql/internal/pre-destroy-guards.sh`
- `scripts/lib/scope-handlers.d/40-postgresql.sh`
- `scripts/lib/scope-verifiers.d/40-postgresql.sh`
- `scripts/lib/packages/50-signoz/internal/lifecycle-handlers.sh`
- `scripts/lib/packages/50-signoz/internal/verifiers.sh`
- `scripts/lib/packages/50-signoz/internal/pre-destroy-guards.sh`
- `scripts/lib/scope-handlers.d/50-signoz.sh`
- `scripts/lib/scope-verifiers.d/50-signoz.sh`

**Tests:**
- `tests/mongodb/test_handlers.py`
- `tests/mongodb/test_verifiers.py`
- `tests/mongodb/test_documentation.py`
- `tests/postgresql/test_handlers.py`
- `tests/postgresql/test_verifiers.py`
- `tests/postgresql/test_documentation.py`
- `tests/signoz/test_handlers.py`
- `tests/signoz/test_verifiers.py`

**Documentation:**
- `docs/references/mongodb-platform-contract.md`
- `docs/references/postgresql-platform-contract.md`
- `docs/references/signoz-platform-contract.md`
- `config/environment-schema/fragments/30-mongodb.manifest`
- `config/environment-schema/fragments/40-postgresql.manifest`
- `config/environment-schema/fragments/50-signoz.manifest`

### Modified Files (Phase 3)

- `scripts/lib/scope-registry.sh` — already contains Phase 3 scopes; verify handler/verifier mappings are complete
- `docs/index.md` — add Phase 3 component references

---

## Task 1: MongoDB Terraform Infrastructure Prerequisites

**Purpose:** Terraform validates (plan only) the IRSA policy extension and KMS grant needed for MongoDB PBM backup access. Consumes `operator_iam_role_arn` from Phase 2 `platform_contract` remote state.

**Files:**
- Create: `platform-prerequisites/terraform/mongodb/versions.tf`
- Create: `platform-prerequisites/terraform/mongodb/variables.tf`
- Create: `platform-prerequisites/terraform/mongodb/main.tf`
- Create: `platform-prerequisites/terraform/mongodb/outputs.tf`
- Create: `platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars`
- Test: `tests/mongodb/test_terraform_contract.py`

- [ ] **Write failing test asserting Terraform files exist and declare required outputs**

```python
# tests/mongodb/test_terraform_contract.py
import pathlib, unittest
TF_DIR = pathlib.Path("platform-prerequisites/terraform/mongodb")
class MongodbTerraformContractTests(unittest.TestCase):
    def test_main_tf_exists(self):
        self.assertTrue((TF_DIR / "main.tf").exists())
    def test_outputs_tf_declares_pbm_policy_arn(self):
        content = (TF_DIR / "outputs.tf").read_text()
        self.assertIn('output "pbm_policy_arn"', content)
    def test_variables_tf_declares_expected_account_id(self):
        content = (TF_DIR / "variables.tf").read_text()
        self.assertIn('variable "expected_account_id"', content)
    def test_sandbox_tfvars_uses_production_account(self):
        tfvars = pathlib.Path("platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars")
        self.assertIn("632674123947", tfvars.read_text())
```

- [ ] **Run to verify FAIL** — `python3 -m unittest tests.mongodb.test_terraform_contract -v`
- [ ] **Create `platform-prerequisites/terraform/mongodb/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10.0"
  backend "s3" {}
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
  }
}
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}
```

- [ ] **Create `platform-prerequisites/terraform/mongodb/variables.tf`**

```hcl
variable "aws_region" { type = string }
variable "expected_account_id" { type = string }
variable "environment" { type = string }
variable "name_prefix" { type = string }
variable "pbm_bucket_name" {
  description = "From platform_contract.pbm_bucket_name (Phase 2 output)"
  type        = string
}
variable "operator_iam_role_arn" {
  description = "From platform_contract.operator_iam_role_arn (Phase 2 output)"
  type        = string
}
variable "cluster_kms_key_arn" {
  description = "KMS key ARN for PBM S3 encryption"
  type        = string
}
variable "tags" { type = map(string); default = {} }
```

- [ ] **Create `platform-prerequisites/terraform/mongodb/main.tf`**

```hcl
# Attach PBM S3 access policy to Phase 2 IRSA operator role
resource "aws_iam_role_policy" "pbm_s3_access" {
  name = "${var.name_prefix}-pbm-s3-access"
  role = element(split("/", var.operator_iam_role_arn), length(split("/", var.operator_iam_role_arn)) - 1)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.pbm_bucket_name}",
        "arn:aws:s3:::${var.pbm_bucket_name}/*"
      ]
    }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [var.cluster_kms_key_arn]
    }]
  })
}

check "operator_role_is_provided" {
  assert {
    condition     = length(var.operator_iam_role_arn) > 0
    error_message = "operator_iam_role_arn must be provided from Phase 2 platform_contract. Direct IAM bypass is not allowed."
  }
}

check "pbm_bucket_is_provided" {
  assert {
    condition     = length(var.pbm_bucket_name) > 0
    error_message = "pbm_bucket_name must be provided from Phase 2 platform_contract."
  }
}
```

- [ ] **Create `platform-prerequisites/terraform/mongodb/outputs.tf`**

```hcl
output "pbm_policy_arn" {
  description = "ARN of the PBM S3 access policy attached to the Phase 2 operator role"
  value       = aws_iam_role_policy.pbm_s3_access.id
}
```

- [ ] **Create `platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars`**

```hcl
# MongoDB Terraform Configuration — Sandbox (Production account as temporary sandbox)
# Account: 632674123947 (Production account; UAT 672172129937 reserved for Phase 3+)
aws_region          = "us-east-1"
expected_account_id = "632674123947"
environment         = "sandbox"
name_prefix         = "oms-sandbox-mongodb"
# Dummy values from Phase 2 platform_contract (plan validation only)
pbm_bucket_name       = "oms-sandbox-eks-pbm-backup"
operator_iam_role_arn = "arn:aws:iam::632674123947:role/oms-sandbox-eks-mongodb-operator"
cluster_kms_key_arn   = "arn:aws:kms:us-east-1:632674123947:key/11111111-2222-3333-4444-555555555555"
tags = { Environment = "sandbox", Purpose = "Phase3-Validation", ManagedBy = "Terraform" }
```

- [ ] **Run test to verify PASS** — `python3 -m unittest tests.mongodb.test_terraform_contract -v`
- [ ] **Commit**

```bash
git add platform-prerequisites/terraform/mongodb/ \
        platform-prerequisites/terraform/environments/sandbox/mongodb.tfvars \
        tests/mongodb/
git commit -m "feat(mongodb): add Terraform infrastructure prerequisites for PBM IRSA"
```

---

## Task 2: MongoDB Environment Schema Fragment

**Purpose:** Register MongoDB-specific environment variables in the unified schema manifest so the orchestration layer can validate them before any provisioning.

**Files:**
- Create: `config/environment-schema/fragments/30-mongodb.manifest`
- Test: `tests/mongodb/test_environment_contract.py`

- [ ] **Write failing test asserting schema fragment exists with required keys**

```python
# tests/mongodb/test_environment_contract.py
import pathlib, unittest
FRAGMENT = pathlib.Path("config/environment-schema/fragments/30-mongodb.manifest")
class MongodbSchemaFragmentTests(unittest.TestCase):
    def test_fragment_exists(self):
        self.assertTrue(FRAGMENT.exists())
    def test_fragment_declares_replica_count(self):
        self.assertIn("MONGODB_REPLICA_COUNT", FRAGMENT.read_text())
    def test_fragment_declares_storage_class(self):
        self.assertIn("MONGODB_STORAGE_CLASS", FRAGMENT.read_text())
    def test_fragment_has_no_hardcoded_arns(self):
        content = FRAGMENT.read_text()
        self.assertNotIn("arn:aws:", content)
```

- [ ] **Run to verify FAIL**
- [ ] **Create `config/environment-schema/fragments/30-mongodb.manifest`**

```
@fragment mongodb
@version 1
@requires eks-platform
MONGODB_REPLICA_COUNT|required|integer-min:1|-
MONGODB_STORAGE_CLASS|required|fixed:gp3|-
MONGODB_IMAGE_REPO|required|nonempty|-
MONGODB_OPERATOR_VERSION|required|nonempty|-
MONGODB_BACKUP_ENABLED|required|enum:true,false|-
MONGODB_BACKUP_SCHEDULE|optional|-|-
```

- [ ] **Run test to verify PASS**
- [ ] **Commit**

```bash
git add config/environment-schema/fragments/30-mongodb.manifest tests/mongodb/test_environment_contract.py
git commit -m "feat(mongodb): add environment schema fragment"
```

---

## Task 3: MongoDB GitOps Manifests

**Purpose:** Create Kustomize-based GitOps manifests for PSMDB Operator HelmRelease and PerconaServerMongoDB cluster CR, consuming namespace/service-account from Phase 2 platform_contract.

**Files:**
- Create: `gitops/mongodb/base/kustomization.yaml`
- Create: `gitops/mongodb/base/namespace.yaml`
- Create: `gitops/mongodb/base/operator.yaml`
- Create: `gitops/mongodb/base/cluster.yaml`
- Create: `gitops/mongodb/overlays/uat/kustomization.yaml`
- Create: `gitops/mongodb/overlays/uat/cluster-patch.yaml`
- Test: `tests/mongodb/test_gitops_manifests.py`

- [ ] **Write failing test asserting manifests render without error**

```python
# tests/mongodb/test_gitops_manifests.py
import subprocess, unittest
class MongodbGitopsManifestTests(unittest.TestCase):
    def test_base_kustomize_build_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/mongodb/base"],
            capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HelmRelease", result.stdout)
    def test_uat_overlay_renders(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/mongodb/overlays/uat"],
            capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
    def test_no_hardcoded_iam_arns_in_manifests(self):
        import pathlib
        for f in pathlib.Path("gitops/mongodb").rglob("*.yaml"):
            content = f.read_text()
            self.assertNotIn("arn:aws:iam", content, f"IAM ARN found in {f}")
```

- [ ] **Run to verify FAIL**
- [ ] **Create `gitops/mongodb/base/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - operator.yaml
  - cluster.yaml
```

- [ ] **Create `gitops/mongodb/base/operator.yaml`**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: psmdb-operator
  namespace: mongodb-operator
spec:
  interval: 10m
  chart:
    spec:
      chart: psmdb-operator
      version: "1.16.x"
      sourceRef:
        kind: HelmRepository
        name: percona
        namespace: flux-system
  values:
    watchNamespace: "mongodb"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

- [ ] **Create `gitops/mongodb/base/cluster.yaml`**

```yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: oms-mongodb
  namespace: mongodb
spec:
  crVersion: "1.16.0"
  image: percona/percona-server-mongodb:7.0
  replsets:
    - name: rs0
      size: 3
      volumeSpec:
        pvc:
          storageClassName: gp3
          resources:
            requests:
              storage: 50Gi
  backup:
    enabled: true
    storages:
      s3-backup:
        type: s3
        s3:
          region: $(AWS_REGION)
          credentialsSecret: ""  # Uses IRSA — no credentials secret
```

- [ ] **Create `gitops/mongodb/overlays/uat/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: cluster-patch.yaml
    target:
      kind: PerconaServerMongoDB
      name: oms-mongodb
```

- [ ] **Create `gitops/mongodb/overlays/uat/cluster-patch.yaml`**

```yaml
- op: replace
  path: /spec/replsets/0/size
  value: 3
- op: replace
  path: /spec/backup/enabled
  value: true
```

- [ ] **Run test to verify PASS**
- [ ] **Commit**

```bash
git add gitops/mongodb/ tests/mongodb/test_gitops_manifests.py
git commit -m "feat(mongodb): add GitOps manifests for PSMDB Operator and cluster CR"
```

---

## Task 4: MongoDB Canonical Handler + Verifier + Guard Wrappers

**Purpose:** Add the 6 canonical wrappers (3 provision/destroy handlers + 3 verifiers + 3 pre-destroy guards) for the `mongodb`, `mongodb-access` scopes, following the exact Phase 2 pattern from `20-eks-platform.sh`.

**Files:**
- Create: `scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh`
- Create: `scripts/lib/packages/30-mongodb/internal/verifiers.sh`
- Create: `scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh`
- Create: `scripts/lib/scope-handlers.d/30-mongodb.sh`
- Create: `scripts/lib/scope-verifiers.d/30-mongodb.sh`
- Test: `tests/mongodb/test_handlers.py`
- Test: `tests/mongodb/test_verifiers.py`

- [ ] **Write failing handler test**

```python
# tests/mongodb/test_handlers.py
import subprocess, pathlib, unittest
HANDLER_FRAGMENT = pathlib.Path("scripts/lib/scope-handlers.d/30-mongodb.sh")
class MongodbHandlerFragmentTests(unittest.TestCase):
    def test_fragment_exists(self):
        self.assertTrue(HANDLER_FRAGMENT.exists())
    def test_fragment_sources_only_lifecycle_handlers(self):
        content = HANDLER_FRAGMENT.read_text()
        self.assertIn("lifecycle-handlers.sh", content)
        self.assertNotIn("verifiers.sh", content)
        self.assertNotIn("pre-destroy-guards.sh", content)
    def test_fragment_defines_exactly_two_provision_wrappers(self):
        content = HANDLER_FRAGMENT.read_text()
        self.assertIn("scope_registry_deferred_provision_mongodb()", content)
        self.assertIn("scope_registry_deferred_provision_mongodb_access()", content)
    def test_bash_syntax_valid(self):
        result = subprocess.run(["bash", "-n", str(HANDLER_FRAGMENT)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
```

- [ ] **Run to verify FAIL**
- [ ] **Create `scripts/lib/scope-handlers.d/30-mongodb.sh`** (follow exact pattern from `20-eks-platform.sh`)

```bash
#!/usr/bin/env bash
# MongoDB scope handler fragment — canonical wrappers only.
# Sources lifecycle-handlers.sh exclusively; never sources verifiers or guards.
set -euo pipefail
_mongodb_handler_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../packages/30-mongodb/internal/lifecycle-handlers.sh
source "${_mongodb_handler_dir}/../packages/30-mongodb/internal/lifecycle-handlers.sh"

scope_registry_deferred_provision_mongodb()        { mongodb_internal_provision_mongodb        "$@"; }
scope_registry_deferred_destroy_mongodb()          { mongodb_internal_destroy_mongodb          "$@"; }
scope_registry_deferred_provision_mongodb_access() { mongodb_internal_provision_mongodb_access "$@"; }
scope_registry_deferred_destroy_mongodb_access()   { mongodb_internal_destroy_mongodb_access   "$@"; }
```

- [ ] **Create `scripts/lib/packages/30-mongodb/internal/lifecycle-handlers.sh`** with stub implementations
- [ ] **Create `scripts/lib/scope-verifiers.d/30-mongodb.sh`** (same pattern as `20-eks-platform.sh`)
- [ ] **Create `scripts/lib/packages/30-mongodb/internal/verifiers.sh`**
- [ ] **Create `scripts/lib/packages/30-mongodb/internal/pre-destroy-guards.sh`**
- [ ] **Run all handler + verifier tests to PASS**
- [ ] **Commit**

```bash
git add scripts/lib/packages/30-mongodb/ scripts/lib/scope-handlers.d/30-mongodb.sh \
        scripts/lib/scope-verifiers.d/30-mongodb.sh tests/mongodb/
git commit -m "feat(mongodb): add canonical handler/verifier/guard wrappers"
```

---

## Task 5: PostgreSQL Terraform + Schema + GitOps + Handlers

**Purpose:** Same pattern as Tasks 1–4 but for the `postgresql-core` and `postgresql-brand` scopes using CloudNativePG.

**Files:** (same structure as Tasks 1–4 under `40-postgresql`)

- [ ] **Write failing Terraform contract test** (same pattern as Task 1)
- [ ] **Create `platform-prerequisites/terraform/postgresql/`** module
- [ ] **Create `config/environment-schema/fragments/40-postgresql.manifest`**
- [ ] **Create `gitops/postgresql/base/`** (CloudNativePG HelmRelease + Cluster CR)
- [ ] **Create `gitops/postgresql/overlays/uat/`**
- [ ] **Create `scripts/lib/packages/40-postgresql/`** (3 internal files)
- [ ] **Create `scripts/lib/scope-handlers.d/40-postgresql.sh`**
- [ ] **Create `scripts/lib/scope-verifiers.d/40-postgresql.sh`**
- [ ] **Write + run tests** for handlers, verifiers, gitops manifests, environment contract
- [ ] **Commit**

```bash
git add platform-prerequisites/terraform/postgresql/ \
        config/environment-schema/fragments/40-postgresql.manifest \
        gitops/postgresql/ \
        scripts/lib/packages/40-postgresql/ \
        scripts/lib/scope-handlers.d/40-postgresql.sh \
        scripts/lib/scope-verifiers.d/40-postgresql.sh \
        tests/postgresql/
git commit -m "feat(postgresql): add Terraform, schema, GitOps, and handler wrappers for CloudNativePG"
```

---

## Task 6: SigNoz Observability Platform

**Purpose:** Deploy SigNoz via GitOps for the `signoz` and `signoz-observability` scopes. SigNoz does not require IRSA; it uses internal ClickHouse + Kafka. Terraform is minimal (StorageClass, namespace PDB).

**Files:** (same structure under `50-signoz`)

- [ ] **Create `gitops/signoz/base/`** (SigNoz HelmRelease)
- [ ] **Create `gitops/signoz/overlays/uat/`**
- [ ] **Create `scripts/lib/packages/50-signoz/`** (3 internal files)
- [ ] **Create `scripts/lib/scope-handlers.d/50-signoz.sh`**
- [ ] **Create `scripts/lib/scope-verifiers.d/50-signoz.sh`**
- [ ] **Write + run tests** for handlers, verifiers, gitops manifests
- [ ] **Commit**

```bash
git add gitops/signoz/ \
        scripts/lib/packages/50-signoz/ \
        scripts/lib/scope-handlers.d/50-signoz.sh \
        scripts/lib/scope-verifiers.d/50-signoz.sh \
        tests/signoz/
git commit -m "feat(signoz): add GitOps manifests and handler wrappers for SigNoz"
```

---

## Task 7: Contract Documentation + Test Suite Completion

**Purpose:** Write the component contract documents and complete the documentation test suite (same as Phase 2 Task 8).

**Files:**
- Create: `docs/references/mongodb-platform-contract.md`
- Create: `docs/references/postgresql-platform-contract.md`
- Create: `docs/references/signoz-platform-contract.md`
- Create: `tests/mongodb/test_documentation.py`
- Create: `tests/postgresql/test_documentation.py`
- Create: `tests/signoz/test_documentation.py`

- [ ] **Create contract documents** for mongodb, postgresql, signoz (each with: ownership, lifecycle, identities, guard semantics, workload identity binding)
- [ ] **Write documentation tests** asserting required sections exist
- [ ] **Run all Phase 3 tests** — all must PASS
- [ ] **Commit**

```bash
git add docs/references/*-platform-contract.md \
        tests/mongodb/test_documentation.py \
        tests/postgresql/test_documentation.py \
        tests/signoz/test_documentation.py
git commit -m "feat(phase3): add contract documentation and documentation test suites"
```

---

## Completion Gates

### Gate 1: All Tests Pass

```bash
python3 -m unittest \
  tests.mongodb.test_handlers \
  tests.mongodb.test_verifiers \
  tests.mongodb.test_documentation \
  tests.mongodb.test_environment_contract \
  tests.mongodb.test_terraform_contract \
  tests.mongodb.test_gitops_manifests \
  tests.postgresql.test_handlers \
  tests.postgresql.test_verifiers \
  tests.postgresql.test_documentation \
  tests.signoz.test_handlers \
  tests.signoz.test_verifiers \
  tests.environment_orchestration.test_scope_registry -v
```

Expected: All PASS, 0 failures.

### Gate 2: Terraform Plan (Sandbox)

```bash
source config/environments/sandbox.env && \
cd platform-prerequisites/terraform/mongodb && \
terraform init -reconfigure \
  -backend-config="bucket=$EKS_PLATFORM_STATE_BUCKET" \
  -backend-config="key=mongodb.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="use_lockfile=true" && \
terraform plan \
  -var-file="../environments/sandbox/mongodb.tfvars" \
  -out=/tmp/phase3-mongodb.tfplan
```

Expected: Plan succeeds with 0 errors.

### Gate 3: GitOps Manifest Rendering

```bash
kustomize build gitops/mongodb/overlays/uat
kustomize build gitops/postgresql/overlays/uat
kustomize build gitops/signoz/overlays/uat
```

Expected: All render without errors, producing valid YAML.

### Gate 4: Merge to main

Same process as Phase 2 — all 3 prior gates must pass first.
