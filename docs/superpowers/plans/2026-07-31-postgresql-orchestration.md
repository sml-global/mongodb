# PostgreSQL Dev/SIT Orchestration & IaC Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the existing `gitops/postgresql/base/cluster.yaml` CNPG manifest into this repo's provisioning scripts for Dev/SIT, fix the `gp3` storage anti-pattern, eliminate the operator/Cluster-CR CRD race condition, delete the dead UAT CNPG overlay, and correct the resulting doc/test drift.

**Architecture:** Mirror the existing, proven MongoDB pattern exactly: a StorageClass + Kyverno WFFC policy pair, an operator-only GitOps base, a separate per-environment overlay containing the Cluster CR, and a bash orchestration sequence that applies the operator, waits for its CRD, then applies the overlay.

**Tech Stack:** Kustomize, Flux `HelmRelease`/`HelmRepository`, CloudNativePG (CNPG) `Cluster` CRD, Kyverno `ClusterPolicy`, bash (`scripts/provision-k8s-components.sh`, `scripts/legacy/dev/provision.sh`), Python `unittest` (structural/static tests only — no live execution).

## Global Constraints

- No `kubectl apply`, `terraform apply`, `helm install`, or any other live-infrastructure command may be executed as part of this plan. Every task's verification step is static/structural (file existence, text/YAML parsing, `kustomize build` — a local templating command, not a cluster mutation).
- Every new bash function name must be distinct from existing MongoDB-specific functions (`apply_operators`, `apply_overlay`) — do not reuse or overload them.
- StorageClass and Kyverno policy naming/structure must mirror the existing `gp3-mongodb` / `require-wffc-storageclass.yaml` pair exactly (same keys, same `volumeBindingMode: WaitForFirstConsumer`, match-by-name only — StorageClass is cluster-scoped).
- CNPG pods are 1-indexed (`oms-postgresql-1`, not `oms-postgresql-0`).

---

### Task 1: `gp3-postgresql` StorageClass + Kyverno WFFC policy

**Files:**
- Create: `k8s/base/storageclass-gp3-postgresql.yaml`
- Modify: `k8s/base/kustomization.yaml`
- Create: `policies/kyverno/require-wffc-storageclass-postgresql.yaml`
- Modify: `policies/kyverno/kustomization.yaml`
- Test: `tests/postgresql/test_storage_and_policy.py`

**Interfaces:**
- Produces: StorageClass named `gp3-postgresql` with `volumeBindingMode: WaitForFirstConsumer`, referenced by Task 2's `cluster.yaml`.

- [ ] **Step 1: Write the failing test**

```python
"""Static/structural tests for the PostgreSQL StorageClass and Kyverno WFFC policy."""
import pathlib
import unittest

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


class PostgresqlStorageClassTests(unittest.TestCase):
    def test_storageclass_file_exists(self):
        path = REPO_ROOT / "k8s/base/storageclass-gp3-postgresql.yaml"
        self.assertTrue(path.exists())

    def test_storageclass_uses_wait_for_first_consumer(self):
        path = REPO_ROOT / "k8s/base/storageclass-gp3-postgresql.yaml"
        doc = yaml.safe_load(path.read_text())
        self.assertEqual(doc["kind"], "StorageClass")
        self.assertEqual(doc["metadata"]["name"], "gp3-postgresql")
        self.assertEqual(doc["volumeBindingMode"], "WaitForFirstConsumer")

    def test_storageclass_registered_in_k8s_base_kustomization(self):
        content = (REPO_ROOT / "k8s/base/kustomization.yaml").read_text()
        self.assertIn("storageclass-gp3-postgresql.yaml", content)


class PostgresqlWffcPolicyTests(unittest.TestCase):
    def test_policy_file_exists(self):
        path = REPO_ROOT / "policies/kyverno/require-wffc-storageclass-postgresql.yaml"
        self.assertTrue(path.exists())

    def test_policy_matches_storageclass_by_name_only(self):
        path = REPO_ROOT / "policies/kyverno/require-wffc-storageclass-postgresql.yaml"
        doc = yaml.safe_load(path.read_text())
        self.assertEqual(doc["kind"], "ClusterPolicy")
        match = doc["spec"]["rules"][0]["match"]["any"][0]
        self.assertEqual(match["resources"]["kinds"], ["StorageClass"])
        self.assertEqual(match["resources"]["names"], ["gp3-postgresql"])
        self.assertNotIn("namespaces", match["resources"])

    def test_policy_registered_in_kyverno_kustomization(self):
        content = (REPO_ROOT / "policies/kyverno/kustomization.yaml").read_text()
        self.assertIn("require-wffc-storageclass-postgresql.yaml", content)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_storage_and_policy.py -v`
Expected: FAIL — `storageclass-gp3-postgresql.yaml` does not exist yet.

- [ ] **Step 3: Create the StorageClass, mirroring `k8s/base/storageclass-gp3-mongodb.yaml` exactly**

`k8s/base/storageclass-gp3-postgresql.yaml`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-postgresql
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  fsType: xfs
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

Modify `k8s/base/kustomization.yaml` — add the new file to `resources:`:
```yaml
resources:
  - storageclass-gp3-mongodb.yaml
  - storageclass-gp3-postgresql.yaml
  - certificates.yaml
  - pdb.yaml
  - psmdb-cluster.yaml
  - mongodb-metrics-collector.yaml
  - postgres-metrics-collector.yaml
```

- [ ] **Step 4: Create the Kyverno policy, mirroring `require-wffc-storageclass.yaml`'s match-by-name structure**

`policies/kyverno/require-wffc-storageclass-postgresql.yaml`:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-wffc-for-postgresql-storageclass
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: validate-gp3-postgresql-storageclass
      match:
        any:
          - resources:
              kinds:
                - StorageClass
              names:
                - gp3-postgresql
      validate:
        message: "gp3-postgresql must use WaitForFirstConsumer."
        pattern:
          volumeBindingMode: WaitForFirstConsumer
```

Modify `policies/kyverno/kustomization.yaml`:
```yaml
resources:
  - require-wffc-storageclass.yaml
  - require-wffc-storageclass-postgresql.yaml
  - block-app-mongo-password-secrets.yaml
  - require-pbm-sidecar-resources.yaml
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_storage_and_policy.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add k8s/base/storageclass-gp3-postgresql.yaml k8s/base/kustomization.yaml \
  policies/kyverno/require-wffc-storageclass-postgresql.yaml policies/kyverno/kustomization.yaml \
  tests/postgresql/test_storage_and_policy.py
git commit -m "feat(postgresql): add gp3-postgresql StorageClass with WFFC enforcement"
```

---

### Task 2: Split `cluster.yaml` into a `dev` overlay; delete the dead `uat` overlay

**Files:**
- Modify: `gitops/postgresql/base/kustomization.yaml`
- Create: `gitops/postgresql/overlays/dev/kustomization.yaml`
- Create: `gitops/postgresql/overlays/dev/cluster.yaml` (moved + edited from `gitops/postgresql/base/cluster.yaml`)
- Delete: `gitops/postgresql/base/cluster.yaml`
- Delete: `gitops/postgresql/overlays/uat/` (both files)
- Modify: `tests/postgresql/test_gitops_manifests.py`

**Interfaces:**
- Consumes: `gp3-postgresql` StorageClass from Task 1.
- Produces: `gitops/postgresql/base` (operator-only, kustomize-buildable), `gitops/postgresql/overlays/dev` (Cluster CR, kustomize-buildable) — both consumed by Task 3's bash wiring.

- [ ] **Step 1: Write the failing test (replacing the existing test file's UAT/base-cluster assumptions)**

Replace the full contents of `tests/postgresql/test_gitops_manifests.py`:

```python
"""
Task 5 (revised): PostgreSQL GitOps Manifests — static rendering and
constraint tests. Base is operator-only; the Cluster CR lives in the `dev`
overlay to avoid a CRD race condition (see docs/superpowers/specs/
2026-07-31-postgresql-orchestration-design.md, decision D2).
"""
import pathlib
import subprocess
import unittest

BASE_DIR = pathlib.Path("gitops/postgresql/base")
DEV_DIR = pathlib.Path("gitops/postgresql/overlays/dev")


class PostgresqlGitopsBaseTests(unittest.TestCase):

    def test_base_has_no_cluster_resource(self):
        content = (BASE_DIR / "kustomization.yaml").read_text()
        self.assertNotIn("cluster.yaml", content)

    def test_base_cluster_file_does_not_exist(self):
        self.assertFalse((BASE_DIR / "cluster.yaml").exists())

    def test_helmrelease_postgresql_operator_exists(self):
        operator_file = BASE_DIR / "operator.yaml"
        self.assertTrue(operator_file.exists())

    def test_helmrelease_postgresql_operator_valid_yaml(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: HelmRelease", content)

    def test_helmrelease_references_correct_namespace(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertIn("postgresql-operator", content)

    def test_operator_service_account_not_hardcoded_with_arn(self):
        content = (BASE_DIR / "operator.yaml").read_text()
        self.assertNotIn("arn:aws:iam", content)

    def test_kustomize_build_base_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/base"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HelmRelease", result.stdout)
        self.assertNotIn("kind: Cluster\n", result.stdout)


class PostgresqlGitopsDevOverlayTests(unittest.TestCase):

    def test_cluster_manifest_exists_and_valid_yaml(self):
        cluster_file = DEV_DIR / "cluster.yaml"
        self.assertTrue(cluster_file.exists())
        content = cluster_file.read_text()
        self.assertIn("apiVersion:", content)
        self.assertIn("kind: Cluster", content)

    def test_cluster_manifest_uses_iam_workload_identity(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("inheritFromIAMRole: true", content)

    def test_cluster_manifest_has_no_hardcoded_aws_credentials(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertNotIn("accessKey", content)
        self.assertNotIn("secretKey", content)
        self.assertNotIn("credentialsSecret", content)

    def test_cluster_manifest_uses_workload_service_account(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("serviceAccountName: oms-postgresql-workload", content)

    def test_cluster_manifest_uses_wffc_storageclass(self):
        content = (DEV_DIR / "cluster.yaml").read_text()
        self.assertIn("storageClass: gp3-postgresql", content)

    def test_dev_overlay_lists_cluster_as_resource_not_patch(self):
        content = (DEV_DIR / "kustomization.yaml").read_text()
        self.assertIn("cluster.yaml", content)
        # cluster.yaml must be a standalone resource, not a strategic-merge
        # patch target (nothing in base exists to patch anymore).
        self.assertIn("resources:", content)

    def test_kustomize_build_dev_overlay_succeeds(self):
        result = subprocess.run(
            ["kustomize", "build", "gitops/postgresql/overlays/dev"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("kind: Cluster", result.stdout)
        self.assertIn("HelmRelease", result.stdout)


class PostgresqlUatOverlayRemovedTests(unittest.TestCase):

    def test_uat_overlay_directory_does_not_exist(self):
        self.assertFalse(pathlib.Path("gitops/postgresql/overlays/uat").exists())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_gitops_manifests.py -v`
Expected: FAIL — `gitops/postgresql/overlays/dev` doesn't exist yet, `uat` still does, base still references `cluster.yaml`.

- [ ] **Step 3: Delete the dead UAT overlay**

```bash
git rm -r gitops/postgresql/overlays/uat
```

- [ ] **Step 4: Move `cluster.yaml` into a new `dev` overlay, updating its StorageClass**

Create `gitops/postgresql/overlays/dev/cluster.yaml` (same content as the
current `gitops/postgresql/base/cluster.yaml`, with `storageClass` changed):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: oms-postgresql
  namespace: postgresql
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  # IRSA: pods use this service account, which is annotated by Phase 2 Terraform
  # with the operator IAM role ARN via platform_contract.postgresql_workload_service_account
  serviceAccountTemplate:
    metadata:
      annotations: {}
  storage:
    storageClass: gp3-postgresql
    size: 50Gi
  backup:
    barmanObjectStore:
      destinationPath: s3://oms-postgresql-backup
      s3Credentials:
        inheritFromIAMRole: true
      wal:
        compression: gzip
  # IRSA authentication — no credentials secret; pod identity via
  # service account oms-postgresql-workload annotated with IAM role
  serviceAccountName: oms-postgresql-workload
```

Create `gitops/postgresql/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - cluster.yaml
```

Delete the old file and remove it from base's resource list:

```bash
git rm gitops/postgresql/base/cluster.yaml
```

Modify `gitops/postgresql/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrepository.yaml
  - operator.yaml
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_gitops_manifests.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add gitops/postgresql tests/postgresql/test_gitops_manifests.py
git commit -m "refactor(postgresql): split Cluster CR into dev overlay, delete dead uat overlay"
```

---

### Task 3: Wire the `postgresql` scope into `scripts/provision-k8s-components.sh`

**Files:**
- Modify: `scripts/provision-k8s-components.sh`
- Test: `tests/postgresql/test_provisioning_script_wiring.py`

**Interfaces:**
- Consumes: `gitops/postgresql/base` and `gitops/postgresql/overlays/dev` from Task 2.
- Produces: `postgresql` scope, callable as `scripts/provision-k8s-components.sh postgresql`, consumed by Task 4.

- [ ] **Step 1: Write the failing test**

```python
"""Structural (text-parsing) tests asserting provision-k8s-components.sh
wires the postgresql scope correctly. No live kubectl/terraform execution."""
import pathlib
import re
import unittest

SCRIPT = pathlib.Path("scripts/provision-k8s-components.sh").read_text()


class PostgresqlScopeWiringTests(unittest.TestCase):

    def test_postgresql_crd_name_defined(self):
        self.assertIn('POSTGRESQL_CRD_NAME="clusters.postgresql.cnpg.io"', SCRIPT)

    def test_apply_postgresql_operator_function_targets_postgresql_base(self):
        self.assertIn("apply_postgresql_operator()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_operator()", 1)[1].split("\n}", 1)[0]
        self.assertIn("gitops/postgresql/base", func_body)

    def test_apply_postgresql_overlay_function_targets_dev_overlay(self):
        self.assertIn("apply_postgresql_overlay()", SCRIPT)
        func_body = SCRIPT.split("apply_postgresql_overlay()", 1)[1].split("\n}", 1)[0]
        self.assertIn("gitops/postgresql/overlays/dev", func_body)

    def test_postgresql_case_does_not_call_mongodb_specific_functions(self):
        # The postgresql scope must call its own apply_postgresql_* functions,
        # never the MongoDB-only apply_operators/apply_overlay (which target
        # gitops/operators/base and k8s/overlays/dev respectively).
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        postgresql_case = case_block.split("postgresql)", 1)[1].split(";;", 1)[0]
        self.assertNotIn("apply_operators", postgresql_case)
        self.assertNotIn("apply_overlay()", postgresql_case)
        self.assertNotIn("apply_overlay\n", postgresql_case)

    def test_wait_for_postgresql_crd_function_exists(self):
        self.assertIn("wait_for_postgresql_crd()", SCRIPT)
        func_body = SCRIPT.split("wait_for_postgresql_crd()", 1)[1].split("\n}", 1)[0]
        self.assertIn("POSTGRESQL_CRD_NAME", func_body)

    def test_preflight_scope_has_postgresql_case(self):
        preflight_body = SCRIPT.split("preflight_scope() {", 1)[1]
        self.assertIn("postgresql)", preflight_body)

    def test_postgresql_scope_case_calls_functions_in_order(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        postgresql_case = case_block.split("postgresql)", 1)[1].split(";;", 1)[0]
        operator_pos = postgresql_case.find("apply_postgresql_operator")
        policies_pos = postgresql_case.find("apply_policies")
        wait_pos = postgresql_case.find("wait_for_postgresql_crd")
        overlay_pos = postgresql_case.find("apply_postgresql_overlay")
        self.assertTrue(
            -1 < operator_pos < policies_pos < wait_pos < overlay_pos,
            f"expected order operator < policies < wait < overlay, got "
            f"{operator_pos}, {policies_pos}, {wait_pos}, {overlay_pos}",
        )

    def test_usage_text_documents_postgresql_scope(self):
        usage_block = SCRIPT.split("usage() {", 1)[1].split("EOF", 1)[0]
        self.assertIn("postgresql", usage_block)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_provisioning_script_wiring.py -v`
Expected: FAIL — none of the postgresql-specific symbols exist yet.

- [ ] **Step 3: Add `POSTGRESQL_CRD_NAME` and the CRD-wait function**

Modify `scripts/provision-k8s-components.sh` — add near `MONGODB_CRD_NAME`:

```bash
MONGODB_CRD_NAME="perconaservermongodbs.psmdb.percona.com"
POSTGRESQL_CRD_NAME="clusters.postgresql.cnpg.io"
```

Add alongside `wait_for_mongodb_crd()`:

```bash
wait_for_postgresql_crd() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  echo "Waiting for PostgreSQL CRD $POSTGRESQL_CRD_NAME (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."
  while ! kubectl get crd "$POSTGRESQL_CRD_NAME" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: PostgreSQL CRD '$POSTGRESQL_CRD_NAME' not found within ${WAIT_TIMEOUT_SECONDS}s." >&2
      echo "Hint: ensure Flux and the CNPG operator HelmRelease are healthy before applying the overlay." >&2
      exit 1
    fi
    sleep 5
  done
}
```

- [ ] **Step 4: Add the `apply_postgresql_operator` / `apply_postgresql_overlay` functions**

Add alongside `apply_signoz()`:

```bash
apply_postgresql_operator() {
  require_crd "helmreleases.helm.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
  require_crd "helmrepositories.source.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
  kubectl apply -k "$ROOT_DIR/gitops/postgresql/base"
}

apply_postgresql_overlay() {
  kubectl apply -k "$ROOT_DIR/gitops/postgresql/overlays/dev"
}
```

- [ ] **Step 5: Add the `postgresql` case to `preflight_scope()`**

Modify `preflight_scope()`'s bootstrap block:

```bash
preflight_scope() {
  if [[ "$BOOTSTRAP_PLATFORM_CONTROLLERS" == "true" ]]; then
    case "$1" in
      mongodb|mongo)
        bootstrap_ebs_csi_driver
        bootstrap_flux_controllers
        bootstrap_kyverno
        bootstrap_cert_manager
        ;;
      postgresql)
        bootstrap_ebs_csi_driver
        bootstrap_flux_controllers
        bootstrap_kyverno
        ;;
      signoz|operators)
        bootstrap_flux_controllers
        ;;
      policies)
        bootstrap_kyverno
        ;;
    esac
  fi

  MISSING_CRDS=()
  case "$1" in
    mongodb|mongo)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
      record_missing_crd "certificates.cert-manager.io" \
        "Install cert-manager first (Certificate CRD is missing), then rerun this command."
      record_missing_crd "issuers.cert-manager.io" \
        "Install cert-manager first (Issuer CRD is missing), then rerun this command."
      if ! kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
        MISSING_CRDS+=("ebs.csi.aws.com|Install the AWS EBS CSI driver addon first, then rerun this command.")
      fi
      ensure_no_missing_crds "$1"
      ;;
    postgresql)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
      if ! kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
        MISSING_CRDS+=("ebs.csi.aws.com|Install the AWS EBS CSI driver addon first, then rerun this command.")
      fi
      ensure_no_missing_crds "$1"
      ;;
    signoz|operators)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      ensure_no_missing_crds "$1"
      ;;
    policies)
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
      ensure_no_missing_crds "$1"
      ;;
  esac
}
```

- [ ] **Step 6: Add the `postgresql` case to the main scope dispatch and usage text**

Modify the `case "$SCOPE" in` dispatch:

```bash
case "$SCOPE" in
  mongodb|mongo)
    preflight_scope "$SCOPE"
    apply_operators
    "$ROOT_DIR/scripts/bootstrap-dev-secrets.sh"
    apply_policies
    wait_for_mongodb_crd
    apply_overlay
    ;;
  postgresql)
    preflight_scope "$SCOPE"
    apply_postgresql_operator
    apply_policies
    wait_for_postgresql_crd
    apply_postgresql_overlay
    ;;
  signoz)
    preflight_scope "$SCOPE"
    apply_signoz
    ;;
  operators)
    preflight_scope "$SCOPE"
    apply_operators
    ;;
  policies)
    preflight_scope "$SCOPE"
    apply_policies
    ;;
  overlay)
    apply_overlay
    ;;
  all)
    if [[ "$BOOTSTRAP_PLATFORM_CONTROLLERS" == "true" ]]; then
      "$0" mongodb --bootstrap-platform-controllers
      "$0" signoz --bootstrap-platform-controllers
    else
      "$0" mongodb
      "$0" signoz
    fi
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, mongo, postgresql, signoz, operators, policies, overlay, all" >&2
    usage
    exit 1
    ;;
esac
```

Modify the `usage()` heredoc to document the new scope:

```
Scopes:
  mongodb    Apply MongoDB operator, Kyverno policies, bootstrap secrets, and dev overlay.
  mongo      Alias of mongodb.
  postgresql Apply CNPG operator, Kyverno policies, and the dev Cluster overlay.
  signoz     Apply optional open-source SigNoz GitOps base only.
  operators  Apply only operator Helm layer.
  policies   Apply only Kyverno policies.
  overlay    Apply only MongoDB dev overlay.
  all        Apply MongoDB scope, then SigNoz.
```

- [ ] **Step 7: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_provisioning_script_wiring.py -v`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add scripts/provision-k8s-components.sh tests/postgresql/test_provisioning_script_wiring.py
git commit -m "feat(postgresql): wire postgresql scope into provision-k8s-components.sh"
```

---

### Task 4: Wire `run_k8s postgresql` into `scripts/legacy/dev/provision.sh`

**Files:**
- Modify: `scripts/legacy/dev/provision.sh`
- Test: `tests/postgresql/test_legacy_provision_wiring.py`

**Interfaces:**
- Consumes: the `postgresql` scope from Task 3.

- [ ] **Step 1: Write the failing test**

```python
"""Structural tests asserting legacy/dev/provision.sh's pg and all scopes
apply the PostgreSQL k8s manifests, not just Terraform prerequisites."""
import pathlib
import unittest

SCRIPT = pathlib.Path("scripts/legacy/dev/provision.sh").read_text()


class LegacyProvisionPostgresqlWiringTests(unittest.TestCase):

    def test_pg_case_calls_run_k8s_postgresql(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        pg_case = case_block.split("pg)", 1)[1].split(";;", 1)[0]
        self.assertIn("run_platform pg", pg_case)
        self.assertIn("run_k8s postgresql", pg_case)

    def test_all_case_calls_run_k8s_postgresql_after_mongodb(self):
        case_block = SCRIPT.split('case "$SCOPE" in', 1)[1]
        all_case = case_block.split("all)", 1)[1].split(";;", 1)[0]
        mongodb_pos = all_case.find("run_k8s mongodb")
        postgresql_pos = all_case.find("run_k8s postgresql")
        self.assertTrue(-1 < mongodb_pos < postgresql_pos)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_legacy_provision_wiring.py -v`
Expected: FAIL — `run_k8s postgresql` is not present yet.

- [ ] **Step 3: Update the `pg` and `all` cases**

Modify `scripts/legacy/dev/provision.sh`:

```bash
case "$SCOPE" in
  all)
    run_platform mongodb
    run_platform pg
    run_k8s mongodb
    run_k8s postgresql
    ;;
  mongodb|mongo)
    run_platform mongodb
    run_k8s mongodb
    ;;
  pg)
    run_platform pg
    run_k8s postgresql
    ;;
  signoz)
    run_k8s signoz
    ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_legacy_provision_wiring.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/legacy/dev/provision.sh tests/postgresql/test_legacy_provision_wiring.py
git commit -m "feat(postgresql): apply CNPG k8s manifests from provision.sh pg/all scopes"
```

---

### Task 5: Documentation corrections

**Files:**
- Modify: `docs/references/postgresql-platform-contract.md`
- Modify: `docs/references/component-catalog.md`
- Modify: `docs/references/verification-commands.md`
- Modify: `docs/index.md`
- Test: `tests/postgresql/test_documentation.py`

- [ ] **Step 1: Write the failing test**

```python
"""Assertions that PostgreSQL docs reflect the corrected orchestration reality."""
import pathlib
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


class PostgresqlDocumentationTests(unittest.TestCase):

    def test_contract_references_real_pod_name(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("oms-postgresql-1", content)
        self.assertNotIn("exec -it postgresql-1", content)

    def test_contract_references_gp3_postgresql_storageclass(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("k8s/base/storageclass-gp3-postgresql.yaml", content)
        self.assertNotIn("k8s/base/storage-classes.yaml", content)

    def test_contract_references_real_provisioning_command(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_contract_has_no_stale_uat_decommission_warning(self):
        content = (REPO_ROOT / "docs/references/postgresql-platform-contract.md").read_text()
        self.assertNotIn("requires a manual decommission step", content)

    def test_component_catalog_references_real_provisioning_command(self):
        content = (REPO_ROOT / "docs/references/component-catalog.md").read_text()
        self.assertIn("scripts/provision.sh pg", content)

    def test_verification_commands_reference_real_cluster_name(self):
        content = (REPO_ROOT / "docs/references/verification-commands.md").read_text()
        self.assertIn("oms-postgresql-1", content)

    def test_index_has_no_stale_uat_decommission_followup(self):
        content = (REPO_ROOT / "docs/index.md").read_text()
        self.assertNotIn("needs an explicit, manual decommission step", content)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/postgresql/test_documentation.py -v`
Expected: FAIL against current doc text.

- [ ] **Step 3: Fix `docs/references/postgresql-platform-contract.md`**

- Replace `**StorageClass:** gp3-postgresql` header value's implied location and the
  "Configuration Reference" bullet `StorageClass: gp3-postgresql (defined in k8s/base/storage-classes.yaml)`
  with `StorageClass: gp3-postgresql (defined in k8s/base/storageclass-gp3-postgresql.yaml)`.
- Replace `bash scripts/provision.sh postgresql` with `bash scripts/provision.sh pg`.
- Replace `kubectl -n postgresql get cluster postgresql` with `kubectl -n postgresql get cluster oms-postgresql`.
- Replace `kubectl -n postgresql exec -it postgresql-1 -- psql ...` with `kubectl -n postgresql exec -it oms-postgresql-1 -- psql ...`.
- Replace the `**Overlay (UAT):** gitops/postgresql/overlays/uat/ (environment-specific values)` bullet with
  `**Overlay (Dev/SIT):** gitops/postgresql/overlays/dev/ (Cluster CR, kept separate from base to avoid a CRD race — see design spec D2)`.
- Delete the `> **Scope update (2026-07-30):** ...` callout's final sentence about the manual decommission
  step (the UAT overlay is now deleted, not pending decommission); keep the rest of the scope-update note.

- [ ] **Step 4: Fix `docs/references/component-catalog.md`**

Replace `**Provisioned by** | Dev/SIT: \`scripts/provision.sh postgresql\` (GitOps).` with
`**Provisioned by** | Dev/SIT: \`scripts/provision.sh pg\` (GitOps).`

- [ ] **Step 5: Fix `docs/references/verification-commands.md`**

Replace:
```
kubectl -n postgresql get cluster postgresql
# Expect: status=Ready

kubectl -n postgresql exec -it postgresql-1 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```
with:
```
kubectl -n postgresql get cluster oms-postgresql
# Expect: status=Ready

kubectl -n postgresql exec -it oms-postgresql-1 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

- [ ] **Step 6: Fix `docs/index.md`**

Replace the bullet:
```
- **Follow-up required:** `gitops/postgresql/overlays/uat/` (the existing CNPG deployment for
  UAT) is superseded by this migration and needs an explicit, manual decommission step before
  Aurora becomes UAT's live database — see the status note in
  [PostgreSQL Platform Contract](references/postgresql-platform-contract.md).
```
with:
```
- **Resolved:** `gitops/postgresql/overlays/uat/` (the superseded CNPG deployment for UAT) has
  been deleted — see [PostgreSQL Platform Contract](references/postgresql-platform-contract.md)
  and Issue #6 for the Dev/SIT orchestration wiring that replaced it.
```

- [ ] **Step 7: Run test to verify it passes**

Run: `python -m pytest tests/postgresql/test_documentation.py -v`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add docs/references/postgresql-platform-contract.md docs/references/component-catalog.md \
  docs/references/verification-commands.md docs/index.md tests/postgresql/test_documentation.py
git commit -m "docs(postgresql): correct pod/cluster names, storage class path, provisioning command"
```

---

### Task 6: Full suite run, Issue #6 update

**Files:** none (verification + GitHub update only)

- [ ] **Step 1: Run the full postgresql test suite**

Run: `python -m pytest tests/postgresql/ -v`
Expected: all tests pass, including the pre-existing ones untouched by this plan.

- [ ] **Step 2: Run the full repo test suite to check for cross-suite regressions**

Run: `python -m pytest tests/ -v`
Expected: all tests pass (no other suite references the moved/deleted PostgreSQL files).

- [ ] **Step 3: Update Issue #6 via `gh` CLI**

```bash
gh issue comment 6 --body "Corrected premise: gitops/postgresql/base/cluster.yaml already existed; the actual gap was that no provisioning script ever applied it, cluster.yaml was bundled with the operator HelmRelease (a CRD race condition), and storageClass: gp3 referenced a StorageClass that doesn't exist. Fixed in <branch/PR>: split cluster.yaml into gitops/postgresql/overlays/dev, added gp3-postgresql StorageClass + WFFC Kyverno policy, wired a new postgresql scope into scripts/provision-k8s-components.sh and scripts/legacy/dev/provision.sh, deleted the dead gitops/postgresql/overlays/uat, and corrected doc/test drift."
gh issue close 6
```

- [ ] **Step 4: Final commit (if any stragglers)**

```bash
git status --short
git add -A
git commit -m "chore(postgresql): finalize orchestration wiring" --allow-empty
```
