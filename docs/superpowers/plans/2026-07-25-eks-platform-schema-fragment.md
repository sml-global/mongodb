# EKS Platform Schema Fragment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the sole EKS environment-schema fragment and a contract test that proves the fragment is static, bounded, and collision-free when composed with the foundation schema.

**Architecture:** The foundation parser remains unchanged and continues to own schema loading and composition order. This plan adds one declarative fragment under `config/environment-schema/fragments/` and one focused test module that validates key membership, enum/bound rules, and composed-key uniqueness against the existing parser contract.

**Tech Stack:** Bash, Python 3 `unittest`, the existing foundation schema parser/validator, and the repository's manifest grammar.

---

### Task 1: Add the EKS schema contract test

**Files:**
- Create: `tests/eks_platform/test_environment_contract.py`

- [ ] **Step 1: Write the failing contract test**

Use the existing foundation loader from `scripts/lib/platform-env.sh` to source the composed schema and assert the EKS fragment contract in three parts:

```python
from pathlib import Path
import importlib.util
import os
import subprocess
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "config" / "environment-schema" / "fragments" / "20-eks-platform.manifest"

EXPECTED_KEYS = {
    "EKS_KUBERNETES_VERSION",
    "EKS_AUTHENTICATION_MODE",
    "EKS_ENDPOINT_PUBLIC_ACCESS",
    "EKS_ENDPOINT_PRIVATE_ACCESS",
    "EKS_DELETION_PROTECTION",
    "EKS_VPC_CIDR",
    "EKS_CONNECTED_CIDR",
    "EKS_AZ_LAYOUT_MODE",
    "EKS_AZ_COUNT",
    "EKS_PRIVATE_SUBNET_CIDRS",
    "EKS_PUBLIC_SUBNET_CIDRS",
    "EKS_NAT_GATEWAY_COUNT",
    "EKS_NODE_INSTANCE_TYPE",
    "EKS_NODE_MIN_SIZE",
    "EKS_NODE_DESIRED_SIZE",
    "EKS_NODE_MAX_SIZE",
    "EKS_NODE_ROOT_VOLUME_GB",
    "EKS_SPOT_ENABLED",
    "EKS_EFS_ENABLED",
    "EKS_EFS_THROUGHPUT_MODE",
    "EKS_EFS_BACKUP_ENABLED",
    "EKS_BACKUP_RETENTION_DAYS",
    "EKS_ADDON_DELIVERY_MODE",
    "EKS_ENABLE_VPC_CNI",
    "EKS_ENABLE_COREDNS",
    "EKS_ENABLE_KUBE_PROXY",
    "EKS_ENABLE_EBS_CSI",
    "EKS_ENABLE_EFS_CSI",
    "EKS_ENABLE_POD_IDENTITY_AGENT",
    "EKS_ENABLE_CLUSTER_AUTOSCALER",
    "EKS_ENABLE_METRICS_SERVER",
}


def read_fragment_keys(path):
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("@constraint"):
            continue
        key, required, validator, immutable = stripped.split("|")
        if key == "EKS_CLUSTER_NAME":
            continue
        keys.add(key)
    return keys


class EksEnvironmentContractTests(unittest.TestCase):
    def run_bash(self, script, env=None):
        result = subprocess.run(
            ["bash", "-lc", script],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            env=env or os.environ.copy(),
        )
        return result

    def test_fragment_contains_only_expected_eks_keys(self):
        keys = read_fragment_keys(SCHEMA_PATH)
        self.assertEqual(EXPECTED_KEYS, keys)

    def test_fragment_rejects_invalid_enum_and_bound_values(self):
        self.assertTrue(SCHEMA_PATH.exists())
        with self.subTest("exact enums"):
            manifest = SCHEMA_PATH.read_text(encoding="utf-8")
            self.assertIn("EKS_AZ_LAYOUT_MODE|required|enum:single,one-per-az|-", manifest)
            self.assertIn("EKS_ADDON_DELIVERY_MODE|required|enum:managed-addon,helm-fallback|-", manifest)
        with self.subTest("bounds and containment are encoded in constraints"):
            manifest = SCHEMA_PATH.read_text(encoding="utf-8")
            self.assertIn("@constraint|cidr-contained-by|EKS_CONNECTED_CIDR,EKS_VPC_CIDR|-", manifest)
            self.assertIn("@constraint|cidr-nonoverlap|EKS_PRIVATE_SUBNET_CIDRS,EKS_PUBLIC_SUBNET_CIDRS|-", manifest)
            self.assertIn("@constraint|integer-order|EKS_NODE_MIN_SIZE,EKS_NODE_DESIRED_SIZE,EKS_NODE_MAX_SIZE|-", manifest)

    def test_composed_schema_has_no_duplicate_keys(self):
        script = f'''
set -euo pipefail
source "{REPO_ROOT / "scripts" / "lib" / "platform-env.sh"}"
load_platform_env uat >/dev/null
printf '%s\n' "${{_platform_env_schema_keys[@]}}"
'''
        result = self.run_bash(script)
        self.assertEqual(0, result.returncode, result.stderr)
        keys = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertIn("ENVIRONMENT", keys)
        self.assertIn("EKS_PLATFORM_STATE_KEY", keys)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Verify the test fails before the fragment exists**

Run:

```bash
python3 -m unittest tests.eks_platform.test_environment_contract -v
```

Expected: FAIL because `config/environment-schema/fragments/20-eks-platform.manifest` does not exist yet.

- [ ] **Step 3: Keep the test focused on the static contract only**

Ensure the test does not import or exercise any Terraform root, handler, verifier, backend bootstrap, or access-entry code. The test should only validate manifest composition and key-level rules.

### Task 2: Add the EKS manifest fragment

**Files:**
- Create: `config/environment-schema/fragments/20-eks-platform.manifest`

- [ ] **Step 1: Write the fragment with the exact approved EKS keys**

Use the foundation manifest grammar to declare only the keys approved by the design spec. The fragment must include the platform identity, network, compute, storage, and add-on flags from the spec and nothing else.

The fragment must declare the allowed enums and bounds exactly as specified:

```text
EKS_AZ_LAYOUT_MODE = single|one-per-az
EKS_ADDON_DELIVERY_MODE = managed-addon|helm-fallback
```

- [ ] **Step 2: Keep the fragment purely declarative**

Do not add defaults that trigger runtime mutation, do not declare Region or account values, and do not add any IAM, access-entry, backend, or path settings.

- [ ] **Step 3: Verify the parser accepts the fragment**

Run:

```bash
python3 -m unittest tests.eks_platform.test_environment_contract -v
```

Expected: PASS for the key membership, exact enum text, and composed-schema uniqueness checks once the fragment is present and correct.

### Task 3: Validate and commit

**Files:**
- Modify: `docs/superpowers/specs/2026-07-22-eks-platform-schema-design.md` (if small review fixes are needed)
- Add: `config/environment-schema/fragments/20-eks-platform.manifest`
- Add: `tests/eks_platform/test_environment_contract.py`

- [ ] **Step 1: Run the focused validation commands**

Run:

```bash
python3 -m unittest tests.eks_platform.test_environment_contract -v
git diff --check
```

Expected: PASS with no whitespace or formatting issues.

- [ ] **Step 2: Commit the Task 2 checkpoint**

```bash
git add docs/superpowers/specs/2026-07-22-eks-platform-schema-design.md \
  docs/superpowers/plans/2026-07-25-eks-platform-schema-fragment.md \
  config/environment-schema/fragments/20-eks-platform.manifest \
  tests/eks_platform/test_environment_contract.py
git commit -m "feat: add EKS platform schema fragment"
```

Expected: a clean commit that captures the spec, plan, fragment, and contract test together.