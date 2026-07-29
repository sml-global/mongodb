# Network CIDR Redesign & UAT/Prod Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder per-environment `/16` CIDR scheme with the approved shared `10.200.0.0/16` allocation, add the missing database subnet tier and Aurora PostgreSQL Terraform for UAT/Prod, enable EKS pod IP density headroom, and safely tear down the `sandbox` environment to make way for Production — all backed by an automated CIDR-overlap regression test.

**Architecture:** Extends the existing three-root Terraform layout (`eks-platform`, `workload-identity`, `postgresql`, `mongodb`) with a new `database` subnet tier in `modules/network`, EKS VPC CNI prefix-delegation wiring in `modules/eks`, and new `aws_rds_cluster`/`aws_db_subnet_group` resources in the `postgresql` root. New/updated environment tfvars under `platform-prerequisites/terraform/environments/{prod,uat,dev}/` encode the approved CIDR spec. A standalone Python validator enforces non-overlap across all environments as a repeatable regression check, independent of any single environment's tfvars.

**Tech Stack:** Terraform (AWS provider), HCL, Python 3 `unittest` (repo convention per `tests/dr_drill/`, `tests/boomi_runtime/`), `python3 -m ipaddress` (standard library, no new dependency).

## Global Constraints

- Approved design: `docs/superpowers/specs/2026-07-29-vpc-subnet-and-boomi-routing-design.md` — every CIDR value in this plan is copied verbatim from that spec's Final CIDR Allocation section (as corrected during this plan's own preparation — see Task 1 for the two arithmetic bugs found and fixed).
- Per `AGENTS.md`: this repository's scripts/Terraform are the only thing this plan touches. No sibling repos.
- Per `AGENTS.md` / operational safety: **no task in this plan runs `terraform apply` or `terraform destroy` against real AWS infrastructure.** Every task's automated verification is offline (`terraform fmt -check`, `terraform validate` against a local backend only where safe, and Python static/content assertions). Real `apply`/`destroy` commands are written out in full for the operator to run manually, with explicit confirmation, once this plan's tasks are reviewed and merged.
- Multi-account topology (from the spec): Dev = account `815402439714`, UAT = account `672172129937`, Sandbox/Production = account `632674123947`. Region `ap-east-1` for all except sandbox today (`us-east-1`).
- Landing Zone / Transit Gateway / VPN is owned by a separate infra team — this plan never creates `aws_ec2_transit_gateway*`, `aws_vpc_peering_connection`, or RAM share resources.
- SIT is deferred (no AWS account exists yet) — out of scope for every task below.
- The Boomi inbound-listener risk and NAT EIP allowlisting question are tracked, non-blocking risks — no task below is gated on them.

---

### Task 1: Automated CIDR-Overlap Validation Test

**Files:**
- Create: `scripts/validate_cidr_allocations.py`
- Create: `tests/network_cidr/__init__.py`
- Create: `tests/network_cidr/test_cidr_allocation.py`

**Interfaces:**
- Produces: `parse_environment_cidrs(tfvars_path: pathlib.Path) -> dict` returning
  `{"vpc_cidr": str, "subnets": list[str]}` by regex-extracting `vpc_cidr`,
  `private_subnet_cidrs`, `public_subnet_cidrs`, and `database_subnet_cidrs` (the last one
  optional — not every environment has a database tier) from a `*.tfvars` file's text.
  `validate_no_overlaps(environments: dict[str, dict]) -> list[str]` returning a list of
  human-readable conflict descriptions (empty list means valid). Later tasks' tfvars changes
  are checked by re-running this same test — no later task redefines these functions.

- [ ] **Step 1: Write the failing test using the CURRENT (pre-redesign) tfvars**

Create `tests/network_cidr/__init__.py` as an empty file.

Create `tests/network_cidr/test_cidr_allocation.py`:

```python
import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"
ENVIRONMENTS_DIR = REPO_ROOT / "platform-prerequisites" / "terraform" / "environments"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class CidrAllocationTests(unittest.TestCase):
    def test_parse_environment_cidrs_extracts_vpc_and_subnets(self):
        dev_tfvars = ENVIRONMENTS_DIR / "dev" / "eks-platform.tfvars"
        parsed = validator.parse_environment_cidrs(dev_tfvars)
        self.assertTrue(parsed["vpc_cidr"].startswith("10."))
        self.assertGreaterEqual(len(parsed["subnets"]), 2)

    def test_no_overlaps_across_current_dev_uat_sandbox(self):
        environments = {
            "dev": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "dev" / "eks-platform.tfvars"),
            "uat": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "uat" / "eks-platform.tfvars"),
            "sandbox": validator.parse_environment_cidrs(ENVIRONMENTS_DIR / "sandbox" / "eks-platform.tfvars"),
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertEqual(conflicts, [])

    def test_detects_overlap_when_present(self):
        environments = {
            "a": {"vpc_cidr": "10.0.0.0/24", "subnets": ["10.0.0.0/25"]},
            "b": {"vpc_cidr": "10.0.0.0/24", "subnets": ["10.0.0.128/25"]},
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertTrue(any("a" in c and "b" in c for c in conflicts))

    def test_detects_subnet_not_contained_in_own_vpc(self):
        environments = {
            "a": {"vpc_cidr": "10.0.0.0/28", "subnets": ["10.0.1.0/28"]},
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertTrue(any("not contained" in c for c in conflicts))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_cidr_allocation -v`
Expected: `ModuleNotFoundError` / `FileNotFoundError` — `scripts/validate_cidr_allocations.py` does not exist yet.

- [ ] **Step 3: Write the validator implementation**

Create `scripts/validate_cidr_allocations.py`:

```python
"""Validate that environment VPC/subnet CIDR allocations do not overlap.

Used both as a standalone check (see __main__) and as a library imported by
tests/network_cidr/test_cidr_allocation.py.
"""
import ipaddress
import re
import sys
from pathlib import Path

_VPC_CIDR_RE = re.compile(r'vpc_cidr\s*=\s*"([^"]+)"')
_LIST_VAR_RE = re.compile(r'(\w*subnet_cidrs)\s*=\s*\[([^\]]*)\]', re.DOTALL)
_STRING_RE = re.compile(r'"([^"]+)"')


def parse_environment_cidrs(tfvars_path: Path) -> dict:
    """Extract vpc_cidr and every subnet CIDR listed in a *.tfvars file."""
    text = tfvars_path.read_text(encoding="utf-8")

    vpc_match = _VPC_CIDR_RE.search(text)
    if not vpc_match:
        raise ValueError(f"{tfvars_path}: no vpc_cidr found")
    vpc_cidr = vpc_match.group(1)

    subnets: list[str] = []
    for _, list_body in _LIST_VAR_RE.findall(text):
        subnets.extend(_STRING_RE.findall(list_body))

    return {"vpc_cidr": vpc_cidr, "subnets": subnets}


def validate_no_overlaps(environments: dict[str, dict]) -> list[str]:
    """Return a list of conflict descriptions; empty list means everything is valid."""
    conflicts: list[str] = []

    networks: dict[str, ipaddress.IPv4Network] = {}
    for name, data in environments.items():
        networks[name] = ipaddress.ip_network(data["vpc_cidr"])

    # 1. No two environment VPC CIDRs may overlap.
    names = list(networks)
    for i, name_a in enumerate(names):
        for name_b in names[i + 1:]:
            if networks[name_a].overlaps(networks[name_b]):
                conflicts.append(
                    f"VPC CIDR overlap: {name_a} ({networks[name_a]}) overlaps "
                    f"{name_b} ({networks[name_b]})"
                )

    # 2. Every subnet must be contained within its own environment's VPC CIDR,
    #    and no two subnets within the same environment may overlap each other.
    for name, data in environments.items():
        vpc_net = networks[name]
        subnet_nets = [ipaddress.ip_network(cidr) for cidr in data["subnets"]]

        for subnet in subnet_nets:
            if not subnet.subnet_of(vpc_net):
                conflicts.append(
                    f"{name}: subnet {subnet} is not contained within its own vpc_cidr {vpc_net}"
                )

        for i, subnet_a in enumerate(subnet_nets):
            for subnet_b in subnet_nets[i + 1:]:
                if subnet_a.overlaps(subnet_b):
                    conflicts.append(
                        f"{name}: subnet {subnet_a} overlaps subnet {subnet_b}"
                    )

    return conflicts


def _discover_environment_tfvars(environments_dir: Path) -> dict[str, Path]:
    result = {}
    for env_dir in sorted(environments_dir.iterdir()):
        candidate = env_dir / "eks-platform.tfvars"
        if candidate.is_file():
            result[env_dir.name] = candidate
    return result


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parents[1]
    environments_dir = repo_root / "platform-prerequisites" / "terraform" / "environments"
    tfvars_by_env = _discover_environment_tfvars(environments_dir)
    parsed = {name: parse_environment_cidrs(path) for name, path in tfvars_by_env.items()}
    found_conflicts = validate_no_overlaps(parsed)
    if found_conflicts:
        for conflict in found_conflicts:
            print(f"CONFLICT: {conflict}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {len(parsed)} environment(s) checked, no CIDR conflicts.")
```

- [ ] **Step 4: Run the test to verify it passes against current tfvars**

Run: `python3 -m unittest tests.network_cidr.test_cidr_allocation -v`
Expected: all 4 tests PASS (current `dev`=`10.70.0.0/16`, `uat`=`10.80.0.0/16`,
`sandbox`=`10.90.0.0/16` don't overlap today).

- [ ] **Step 5: Run the standalone script directly**

Run: `python3 scripts/validate_cidr_allocations.py`
Expected: `OK: 3 environment(s) checked, no CIDR conflicts.`

- [ ] **Step 6: Commit**

```bash
git add scripts/validate_cidr_allocations.py tests/network_cidr/
git commit -m "test: add automated CIDR-overlap validator for environment tfvars"
```

---

### Task 2: Add a Database Subnet Tier to the Network Module

**Files:**
- Modify: `platform-prerequisites/terraform/modules/network/variables.tf`
- Modify: `platform-prerequisites/terraform/modules/network/main.tf`
- Modify: `platform-prerequisites/terraform/modules/network/outputs.tf`
- Modify: `platform-prerequisites/terraform/eks-platform/variables.tf`
- Modify: `platform-prerequisites/terraform/eks-platform/main.tf`
- Modify: `platform-prerequisites/terraform/eks-platform/outputs.tf`
- Test: `tests/network_cidr/test_network_module_database_tier.py`

**Interfaces:**
- Consumes: nothing new from earlier tasks.
- Produces: `module.network.database_subnet_ids` (list of strings, empty list when
  `database_subnet_cidrs` is `[]`), and `eks-platform` `platform_contract.database_subnet_ids`.
  Task 7 (Aurora resources) consumes this exact output name.

**Verified gap this task fixes:** `modules/network/main.tf` currently only creates
`aws_subnet.public` and `aws_subnet.private` — there is no third tier for the dedicated
Aurora DB subnets the design spec requires for UAT/Prod. This was not caught until this
plan's preparation actually opened the module source.

- [ ] **Step 1: Write the failing static-content test**

Create `tests/network_cidr/test_network_module_database_tier.py`:

```python
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
NETWORK_VARS = REPO_ROOT / "platform-prerequisites/terraform/modules/network/variables.tf"
NETWORK_MAIN = REPO_ROOT / "platform-prerequisites/terraform/modules/network/main.tf"
NETWORK_OUTPUTS = REPO_ROOT / "platform-prerequisites/terraform/modules/network/outputs.tf"


class DatabaseSubnetTierTests(unittest.TestCase):
    def test_database_subnet_cidrs_variable_exists_and_defaults_empty(self):
        text = NETWORK_VARS.read_text(encoding="utf-8")
        self.assertIn('variable "database_subnet_cidrs"', text)
        self.assertIn("default     = []", text)

    def test_database_subnet_resource_exists(self):
        text = NETWORK_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_subnet" "database"', text)

    def test_database_subnet_ids_output_exists(self):
        text = NETWORK_OUTPUTS.read_text(encoding="utf-8")
        self.assertIn('output "database_subnet_ids"', text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_network_module_database_tier -v`
Expected: FAIL — none of the three assertions are true yet.

- [ ] **Step 3: Add the `database_subnet_cidrs` variable**

In `platform-prerequisites/terraform/modules/network/variables.tf`, add after the existing
`public_subnet_cidrs` variable block:

```hcl
variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks, one per AZ. Empty list means no database tier (CNPG environments)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.database_subnet_cidrs) == 0 || length(var.database_subnet_cidrs) == length(var.availability_zones)
    error_message = "database_subnet_cidrs must be empty or match availability_zones length."
  }
}
```

- [ ] **Step 4: Add the `aws_subnet.database` resource and a private route table for it**

In `platform-prerequisites/terraform/modules/network/main.tf`, add after the existing
`resource "aws_subnet" "private"` block:

```hcl
resource "aws_subnet" "database" {
  for_each = {
    for index, cidr in var.database_subnet_cidrs :
    index => cidr
  }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[each.key]
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-database-${each.key + 1}"
  }
}
```

Add after the existing `resource "aws_route_table_association" "private"` block (database
subnets are private-only per the AWS RDS/Aurora hard constraint verified in the design spec —
no route to the internet gateway, egress via the same NAT gateways as the private tier so
Aurora can still reach S3/KMS endpoints if needed):

```hcl
resource "aws_route_table" "database" {
  for_each = aws_subnet.database

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key % var.nat_gateway_count].id
  }

  tags = {
    Name = "${var.name_prefix}-database-rt-${each.key + 1}"
  }
}

resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database[each.key].id
}
```

- [ ] **Step 5: Add the `database_subnet_ids` output**

In `platform-prerequisites/terraform/modules/network/outputs.tf`, add:

```hcl
output "database_subnet_ids" {
  description = "Database subnet IDs for Aurora DB subnet groups. Empty list when no database tier exists."
  value       = [for subnet in aws_subnet.database : subnet.id]
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_network_module_database_tier -v`
Expected: PASS (all 3 tests).

- [ ] **Step 7: Wire the new variable and output through `eks-platform`**

In `platform-prerequisites/terraform/eks-platform/variables.tf`, add after `public_subnet_cidrs`:

```hcl
variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks for Aurora, one per AZ. Empty list for CNPG-only environments (dev)."
  type        = list(string)
  default     = []
}
```

In `platform-prerequisites/terraform/eks-platform/main.tf`, add `database_subnet_cidrs = var.database_subnet_cidrs` to the existing `module "network"` block, immediately after the existing `public_subnet_cidrs = var.public_subnet_cidrs` line.

In `platform-prerequisites/terraform/eks-platform/outputs.tf`, add `database_subnet_ids = module.network.database_subnet_ids` to the `platform_contract` output map, immediately after the existing `public_subnet_ids = module.network.public_subnet_ids` line.

- [ ] **Step 8: Add a static test confirming the eks-platform wiring**

Append to `tests/network_cidr/test_network_module_database_tier.py` (inside the same class):

```python
    def test_eks_platform_wires_database_subnet_cidrs(self):
        eks_platform_main = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/main.tf"
        eks_platform_outputs = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/outputs.tf"
        self.assertIn("database_subnet_cidrs = var.database_subnet_cidrs", eks_platform_main.read_text(encoding="utf-8"))
        self.assertIn("database_subnet_ids = module.network.database_subnet_ids", eks_platform_outputs.read_text(encoding="utf-8"))
```

- [ ] **Step 9: Run the full test file to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_network_module_database_tier -v`
Expected: PASS (all 4 tests).

- [ ] **Step 10: Commit**

```bash
git add platform-prerequisites/terraform/modules/network/ platform-prerequisites/terraform/eks-platform/ tests/network_cidr/test_network_module_database_tier.py
git commit -m "feat: add database subnet tier to network module for Aurora DB subnet groups"
```

---

### Task 3: Enable EKS VPC CNI Prefix Delegation

**Files:**
- Modify: `platform-prerequisites/terraform/modules/eks/variables.tf`
- Modify: `platform-prerequisites/terraform/modules/eks/main.tf`
- Modify: `platform-prerequisites/terraform/eks-platform/variables.tf`
- Test: `tests/network_cidr/test_prefix_delegation.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `addons["vpc-cni"].configuration_values` optional field, consumed directly by
  every environment's `eks-platform.tfvars` `addons.vpc-cni` block in Tasks 4-6.

**Verified fact backing this task:** AWS EKS Best Practices Guide (fetched 2026-07-29),
exact quote: *"you can now configure Amazon VPC CNI to assign /28 (16 IP addresses) IPv4
address prefixes."* Enabled via the `aws_eks_addon` resource's `configuration_values`
argument (a JSON string), which is not currently wired through either module.

- [ ] **Step 1: Write the failing static-content test**

Create `tests/network_cidr/test_prefix_delegation.py`:

```python
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EKS_MODULE_VARS = REPO_ROOT / "platform-prerequisites/terraform/modules/eks/variables.tf"
EKS_MODULE_MAIN = REPO_ROOT / "platform-prerequisites/terraform/modules/eks/main.tf"
EKS_PLATFORM_VARS = REPO_ROOT / "platform-prerequisites/terraform/eks-platform/variables.tf"


class PrefixDelegationTests(unittest.TestCase):
    def test_addons_object_type_has_configuration_values_field(self):
        module_text = EKS_MODULE_VARS.read_text(encoding="utf-8")
        platform_text = EKS_PLATFORM_VARS.read_text(encoding="utf-8")
        self.assertIn("configuration_values = optional(string)", module_text)
        self.assertIn("configuration_values = optional(string)", platform_text)

    def test_addon_resource_passes_configuration_values(self):
        text = EKS_MODULE_MAIN.read_text(encoding="utf-8")
        self.assertIn("configuration_values", text)
        self.assertIn("each.value.configuration_values", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_prefix_delegation -v`
Expected: FAIL — neither field exists yet.

- [ ] **Step 3: Add `configuration_values` to the addons object type in both modules**

In `platform-prerequisites/terraform/modules/eks/variables.tf`, replace the `addons` variable block:

```hcl
variable "addons" {
  description = "Explicit add-on versions and enabled flags."
  type = map(object({
    enabled              = bool
    addon_version        = string
    resolve_conflicts    = optional(string, "OVERWRITE")
    service_account_role = optional(bool, false)
    configuration_values = optional(string)
  }))
}
```

In `platform-prerequisites/terraform/eks-platform/variables.tf`, replace the matching `addons` variable block (the one with the `validation` block checking `addon_version != "latest"`) so its `type` matches exactly:

```hcl
variable "addons" {
  description = "Explicit add-on version map; never use latest selectors."
  type = map(object({
    enabled              = bool
    addon_version        = string
    resolve_conflicts    = optional(string, "OVERWRITE")
    service_account_role = optional(bool, false)
    configuration_values = optional(string)
  }))

  validation {
    condition = alltrue([
      for addon in values(var.addons) :
      lower(addon.addon_version) != "latest"
    ])
    error_message = "addons[*].addon_version must be explicit and cannot be latest."
  }
}
```

- [ ] **Step 4: Pass `configuration_values` through to the `aws_eks_addon` resource**

In `platform-prerequisites/terraform/modules/eks/main.tf`, modify the `resource "aws_eks_addon" "managed"` block, adding one line:

```hcl
resource "aws_eks_addon" "managed" {
  for_each = local.enabled_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  resolve_conflicts_on_create = each.value.resolve_conflicts
  resolve_conflicts_on_update = each.value.resolve_conflicts
  service_account_role_arn    = each.value.service_account_role ? var.addon_role_arn : null
  configuration_values        = each.value.configuration_values

  depends_on = [aws_eks_node_group.primary]
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_prefix_delegation -v`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add platform-prerequisites/terraform/modules/eks/ platform-prerequisites/terraform/eks-platform/variables.tf tests/network_cidr/test_prefix_delegation.py
git commit -m "feat: wire configuration_values through EKS managed addons for prefix delegation"
```

---

### Task 4: New `prod` Environment tfvars

**Files:**
- Create: `platform-prerequisites/terraform/environments/prod/eks-platform.tfvars`
- Create: `platform-prerequisites/terraform/environments/prod/workload-identity.tfvars`
- Test: `tests/network_cidr/test_prod_environment_tfvars.py`

**Interfaces:**
- Consumes: `database_subnet_cidrs` (Task 2), `configuration_values` (Task 3),
  `parse_environment_cidrs`/`validate_no_overlaps` (Task 1).
- Produces: nothing new consumed by later tasks (mongodb/postgresql tfvars for prod are
  explicitly out of scope — see Global Constraints and Task 7's note).

- [ ] **Step 1: Write the failing test**

Create `tests/network_cidr/test_prod_environment_tfvars.py`:

```python
import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROD_DIR = REPO_ROOT / "platform-prerequisites/terraform/environments/prod"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class ProdEnvironmentTfvarsTests(unittest.TestCase):
    def test_prod_eks_platform_tfvars_exists_with_expected_cidrs(self):
        path = PROD_DIR / "eks-platform.tfvars"
        self.assertTrue(path.is_file())
        parsed = validator.parse_environment_cidrs(path)
        self.assertEqual(parsed["vpc_cidr"], "10.200.0.0/17")
        self.assertIn("10.200.0.0/19", parsed["subnets"])
        self.assertIn("10.200.32.0/19", parsed["subnets"])
        self.assertIn("10.200.64.0/19", parsed["subnets"])
        self.assertIn("10.200.96.0/26", parsed["subnets"])
        self.assertIn("10.200.97.0/24", parsed["subnets"])

    def test_prod_targets_the_correct_account_and_region(self):
        text = (PROD_DIR / "eks-platform.tfvars").read_text(encoding="utf-8")
        self.assertIn('expected_account_id  = "632674123947"', text)
        self.assertIn('aws_region           = "ap-east-1"', text)

    def test_prod_enables_prefix_delegation(self):
        text = (PROD_DIR / "eks-platform.tfvars").read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)

    def test_prod_workload_identity_tfvars_exists(self):
        path = PROD_DIR / "workload-identity.tfvars"
        self.assertTrue(path.is_file())
        text = path.read_text(encoding="utf-8")
        self.assertIn('expected_account_id             = "632674123947"', text)

    def test_prod_does_not_overlap_with_dev_uat_sandbox(self):
        environments_dir = REPO_ROOT / "platform-prerequisites/terraform/environments"
        environments = {
            "prod": validator.parse_environment_cidrs(environments_dir / "prod" / "eks-platform.tfvars"),
            "dev": validator.parse_environment_cidrs(environments_dir / "dev" / "eks-platform.tfvars"),
            "uat": validator.parse_environment_cidrs(environments_dir / "uat" / "eks-platform.tfvars"),
        }
        conflicts = validator.validate_no_overlaps(environments)
        self.assertEqual(conflicts, [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_prod_environment_tfvars -v`
Expected: FAIL — `platform-prerequisites/terraform/environments/prod/` does not exist yet.

- [ ] **Step 3: Create `environments/prod/eks-platform.tfvars`**

```hcl
# Production EKS Platform Terraform Configuration
# Replaces the temporary `sandbox` validation environment in this same AWS account.
# Sandbox MUST be fully torn down first — see docs/superpowers/plans/2026-07-29-network-and-uat-provisioning.md Task 8.

name_prefix          = "oms-prod-eks"
environment          = "prod"
aws_region           = "ap-east-1"
expected_account_id  = "632674123947"

vpc_cidr              = "10.200.0.0/17"
availability_zones    = ["ap-east-1a", "ap-east-1b", "ap-east-1c"]
private_subnet_cidrs  = ["10.200.0.0/19", "10.200.32.0/19", "10.200.64.0/19"]
public_subnet_cidrs   = ["10.200.96.0/26", "10.200.96.64/26", "10.200.96.128/26"]
database_subnet_cidrs = ["10.200.97.0/24", "10.200.98.0/24", "10.200.99.0/24"]
nat_gateway_count     = 3
nat_mode              = "one-per-az"

kubernetes_version      = "1.33"
authentication_mode     = "API"
endpoint_public_access  = false
endpoint_private_access = true
deletion_protection     = true

node_instance_type    = "m6i.xlarge"
node_min_size         = 3
node_desired_size     = 3
node_max_size         = 9
node_root_volume_size = 100
node_spot_enabled     = false

# Placeholder — operator must replace with the real KMS key ARN before apply.
cluster_kms_key_arn     = "arn:aws:kms:ap-east-1:632674123947:key/REPLACE-ME-PROD-CLUSTER-KEY"
cluster_oidc_thumbprint = "9e99a48a9960b14926bb7f3b02e22da0afd40a4d"
cluster_oidc_issuer_url = "https://oidc.eks.ap-east-1.amazonaws.com/id/REPLACE-ME-PROD-OIDC"
enable_load_balancer_controller = true

efs_enabled         = true
efs_throughput_mode = "bursting"

backup_enabled            = true
backup_retention_days     = 35
backup_kms_key_arn        = "arn:aws:kms:ap-east-1:632674123947:key/REPLACE-ME-PROD-BACKUP-KEY"
backup_service_role_arn   = "arn:aws:iam::632674123947:role/service-role/AWSBackupDefaultServiceRole"
vault_min_retention_days  = 35
vault_max_retention_days  = 365

addons = {
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
    configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } })
  }
  coredns = {
    enabled              = true
    addon_version        = "v1.12.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
  kube-proxy = {
    enabled              = true
    addon_version        = "v1.33.0-eksbuild.2"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
  aws-ebs-csi-driver = {
    enabled              = true
    addon_version        = "v1.44.0-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = true
  }
  aws-efs-csi-driver = {
    enabled              = true
    addon_version        = "v2.1.10-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = true
  }
  eks-pod-identity-agent = {
    enabled              = true
    addon_version        = "v1.3.8-eksbuild.2"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
}
```

- [ ] **Step 4: Create `environments/prod/workload-identity.tfvars`**

```hcl
aws_region                      = "ap-east-1"
expected_account_id             = "632674123947"
environment                     = "prod"
cluster_name                    = "oms-prod-eks"
eks_platform_state_bucket       = "oms-terraform-state"
eks_platform_state_key          = "oms/prod/eks-platform.tfstate"
eks_platform_state_use_lockfile = true

identities = {}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_prod_environment_tfvars -v`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Run the Task 1 validator across all environments including the new prod**

Run: `python3 scripts/validate_cidr_allocations.py`
Expected: `OK: 4 environment(s) checked, no CIDR conflicts.`

- [ ] **Step 7: Commit**

```bash
git add platform-prerequisites/terraform/environments/prod/ tests/network_cidr/test_prod_environment_tfvars.py
git commit -m "feat: add prod environment tfvars under the new 10.200.0.0/16 CIDR scheme"
```

---

### Task 5: Update `uat` Environment tfvars

**Files:**
- Modify: `platform-prerequisites/terraform/environments/uat/eks-platform.tfvars`
- Test: `tests/network_cidr/test_uat_environment_tfvars.py`

**Interfaces:**
- Consumes: same as Task 4.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Create `tests/network_cidr/test_uat_environment_tfvars.py`:

```python
import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
UAT_TFVARS = REPO_ROOT / "platform-prerequisites/terraform/environments/uat/eks-platform.tfvars"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class UatEnvironmentTfvarsTests(unittest.TestCase):
    def test_uat_uses_new_cidr_scheme(self):
        parsed = validator.parse_environment_cidrs(UAT_TFVARS)
        self.assertEqual(parsed["vpc_cidr"], "10.200.216.0/21")
        self.assertIn("10.200.216.0/23", parsed["subnets"])
        self.assertIn("10.200.218.0/23", parsed["subnets"])
        self.assertIn("10.200.220.0/26", parsed["subnets"])
        self.assertIn("10.200.220.128/25", parsed["subnets"])
        self.assertIn("10.200.221.0/25", parsed["subnets"])

    def test_uat_enables_prefix_delegation(self):
        text = UAT_TFVARS.read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)

    def test_uat_account_and_region_unchanged(self):
        text = UAT_TFVARS.read_text(encoding="utf-8")
        self.assertIn('expected_account_id  = "672172129937"', text)
        self.assertIn('aws_region           = "ap-east-1"', text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_uat_environment_tfvars -v`
Expected: FAIL — current file still has the old `10.80.0.0/16` scheme.

- [ ] **Step 3: Update `environments/uat/eks-platform.tfvars`**

Replace the networking block (`vpc_cidr` through `nat_mode`) and the `vpc-cni` addon entry:

```hcl
vpc_cidr              = "10.200.216.0/21"
availability_zones    = ["ap-east-1a", "ap-east-1b"]
private_subnet_cidrs  = ["10.200.216.0/23", "10.200.218.0/23"]
public_subnet_cidrs   = ["10.200.220.0/26", "10.200.220.64/26"]
database_subnet_cidrs = ["10.200.220.128/25", "10.200.221.0/25"]
nat_gateway_count     = 1
nat_mode              = "single"
```

And update the `vpc-cni` entry inside `addons = { ... }`:

```hcl
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
    configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } })
  }
```

Leave every other line in the file (account ID, region, KMS ARNs, node sizing, other addons)
unchanged — this task only touches networking and the `vpc-cni` addon entry.

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_uat_environment_tfvars -v`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Re-run the full CIDR validator to confirm no regressions**

Run: `python3 scripts/validate_cidr_allocations.py`
Expected: `OK: 4 environment(s) checked, no CIDR conflicts.`

- [ ] **Step 6: Commit**

```bash
git add platform-prerequisites/terraform/environments/uat/eks-platform.tfvars tests/network_cidr/test_uat_environment_tfvars.py
git commit -m "feat: migrate uat to the new 10.200.216.0/21 CIDR allocation"
```

---

### Task 6: Update `dev` Environment tfvars

**Files:**
- Modify: `platform-prerequisites/terraform/environments/dev/eks-platform.tfvars`
- Test: `tests/network_cidr/test_dev_environment_tfvars.py`

**Interfaces:**
- Consumes: same as Task 4/5.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Create `tests/network_cidr/test_dev_environment_tfvars.py`:

```python
import importlib.util
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEV_TFVARS = REPO_ROOT / "platform-prerequisites/terraform/environments/dev/eks-platform.tfvars"
VALIDATOR = REPO_ROOT / "scripts" / "validate_cidr_allocations.py"

SPEC = importlib.util.spec_from_file_location("validate_cidr_allocations", VALIDATOR)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class DevEnvironmentTfvarsTests(unittest.TestCase):
    def test_dev_uses_new_cidr_scheme_with_two_azs(self):
        parsed = validator.parse_environment_cidrs(DEV_TFVARS)
        self.assertEqual(parsed["vpc_cidr"], "10.200.208.0/21")
        self.assertIn("10.200.208.0/23", parsed["subnets"])
        self.assertIn("10.200.210.0/23", parsed["subnets"])
        self.assertIn("10.200.212.0/26", parsed["subnets"])
        self.assertIn("10.200.212.64/26", parsed["subnets"])

    def test_dev_has_no_database_subnet_tier(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertNotIn("database_subnet_cidrs", text)

    def test_dev_still_uses_two_availability_zones(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertIn('availability_zones   = ["ap-east-1a", "ap-east-1b"]', text)

    def test_dev_enables_prefix_delegation(self):
        text = DEV_TFVARS.read_text(encoding="utf-8")
        self.assertIn("ENABLE_PREFIX_DELEGATION", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_dev_environment_tfvars -v`
Expected: FAIL — current file still has `10.70.0.0/16`, and there is no `vpc-cni`
`configuration_values` entry.

- [ ] **Step 3: Update `environments/dev/eks-platform.tfvars`**

Replace the networking block:

```hcl
vpc_cidr             = "10.200.208.0/21"
availability_zones   = ["ap-east-1a", "ap-east-1b"]
private_subnet_cidrs = ["10.200.208.0/23", "10.200.210.0/23"]
public_subnet_cidrs  = ["10.200.212.0/26", "10.200.212.64/26"]
nat_gateway_count    = 1
nat_mode             = "single"
```

Note: no `database_subnet_cidrs` line is added — Dev uses CNPG (in-cluster PostgreSQL), not
Aurora, per the Database Engine Decision in the design spec. The `eks-platform` module's
`database_subnet_cidrs` variable defaults to `[]` (Task 2, Step 3), so omitting it here is
correct and requires no other change.

Dev's `eks-platform.tfvars` already has an `addons` block with a `vpc-cni` entry (confirmed
by reading the full file), identical in shape to UAT's pre-Task-5 entry:

```hcl
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
  }
```

Replace it with:

```hcl
  vpc-cni = {
    enabled              = true
    addon_version        = "v1.20.4-eksbuild.1"
    resolve_conflicts    = "OVERWRITE"
    service_account_role = false
    configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } })
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_dev_environment_tfvars -v`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Re-run the full CIDR validator to confirm no regressions**

Run: `python3 scripts/validate_cidr_allocations.py`
Expected: `OK: 4 environment(s) checked, no CIDR conflicts.`

- [ ] **Step 6: Commit**

```bash
git add platform-prerequisites/terraform/environments/dev/eks-platform.tfvars tests/network_cidr/test_dev_environment_tfvars.py
git commit -m "feat: migrate dev to the new 10.200.208.0/21 CIDR allocation"
```

---

### Task 7: Aurora PostgreSQL Terraform Resources in the `postgresql` Root

**Files:**
- Modify: `platform-prerequisites/terraform/postgresql/variables.tf`
- Modify: `platform-prerequisites/terraform/postgresql/main.tf`
- Modify: `platform-prerequisites/terraform/postgresql/terraform.tfvars.sample`
- Test: `tests/network_cidr/test_aurora_resources.py`

**Interfaces:**
- Consumes: `database_subnet_ids` output (Task 2) — supplied by the operator as a tfvars
  value copied from `eks-platform`'s `platform_contract.database_subnet_ids` output (this
  root does not use `terraform_remote_state`, matching its existing pattern — see design
  spec's verified note that `mongodb`/`postgresql` roots have no remote-state dependency).
- Produces: nothing consumed by later tasks in this plan.

**Explicit scope boundary (see Global Constraints):** this task only adds the Aurora
resources to the shared `postgresql` root module. It does **not** create
`environments/uat/postgresql.tfvars` or `environments/prod/postgresql.tfvars` — those files
don't exist yet for uat, require real bucket/role ARN values from an applied
`workload-identity` state, and are a separate operational step for whoever runs the actual
provisioning after this plan merges. `terraform.tfvars.sample` is updated instead, since the
current sample is stale (references variables that don't exist in `variables.tf` at all).

**Security note:** the current stale sample includes a plaintext
`db_master_password = "CHANGE_ME_STRONG_DEV_PASSWORD"` variable. This task does not carry
that pattern forward — Aurora's `manage_master_user_password = true` (an AWS-managed secret
in Secrets Manager) is used instead, so no plaintext database password ever appears in any
tfvars file or Terraform state.

- [ ] **Step 1: Write the failing test**

Create `tests/network_cidr/test_aurora_resources.py`:

```python
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PG_VARS = REPO_ROOT / "platform-prerequisites/terraform/postgresql/variables.tf"
PG_MAIN = REPO_ROOT / "platform-prerequisites/terraform/postgresql/main.tf"


class AuroraResourceTests(unittest.TestCase):
    def test_new_variables_exist(self):
        text = PG_VARS.read_text(encoding="utf-8")
        for name in [
            "vpc_id",
            "database_subnet_ids",
            "aurora_engine_version",
            "aurora_instance_class",
            "aurora_instance_count",
            "aurora_database_name",
            "aurora_master_username",
            "allowed_source_security_group_id",
        ]:
            self.assertIn(f'variable "{name}"', text)

    def test_db_subnet_group_resource_exists(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_db_subnet_group" "aurora"', text)

    def test_rds_cluster_resource_exists_and_uses_managed_password(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_rds_cluster" "aurora"', text)
        self.assertIn("manage_master_user_password = true", text)
        self.assertNotIn("master_password", text)

    def test_rds_cluster_instance_resource_exists(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_rds_cluster_instance" "aurora"', text)

    def test_security_group_restricts_ingress_to_source_sg_only(self):
        text = PG_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_security_group" "aurora"', text)
        self.assertIn("var.allowed_source_security_group_id", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_aurora_resources -v`
Expected: FAIL — none of these variables/resources exist yet.

- [ ] **Step 3: Add the new variables**

Append to `platform-prerequisites/terraform/postgresql/variables.tf`:

```hcl
variable "vpc_id" {
  description = "VPC ID from the eks-platform platform_contract output, for the Aurora security group."
  type        = string
}

variable "database_subnet_ids" {
  description = "Database subnet IDs from eks-platform's platform_contract.database_subnet_ids output."
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "database_subnet_ids must include at least two subnets (AWS RDS/Aurora hard requirement: a DB subnet group must span at least two Availability Zones)."
  }
}

variable "allowed_source_security_group_id" {
  description = "Security group ID (typically the EKS node/workload security group) allowed to reach Aurora on the PostgreSQL port."
  type        = string
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version, kept in lockstep between uat and prod per the Database Engine Decision in the design spec."
  type        = string
}

variable "aurora_instance_class" {
  description = "Aurora DB instance class (for example db.r6g.large)."
  type        = string
}

variable "aurora_instance_count" {
  description = "Number of Aurora cluster instances (writer + readers)."
  type        = number
  default     = 1

  validation {
    condition     = var.aurora_instance_count >= 1
    error_message = "aurora_instance_count must be at least 1."
  }
}

variable "aurora_database_name" {
  description = "Initial database name created in the Aurora cluster."
  type        = string
}

variable "aurora_master_username" {
  description = "Aurora master username. The password is managed by AWS Secrets Manager (manage_master_user_password), never set here."
  type        = string
}
```

- [ ] **Step 4: Add the DB subnet group, security group, and Aurora cluster resources**

Append to `platform-prerequisites/terraform/postgresql/main.tf`:

```hcl
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora"
  subnet_ids = var.database_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  description = "Restricts PostgreSQL traffic to the approved workload security group only."
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_source_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.name_prefix}-aurora"
  engine                          = "aurora-postgresql"
  engine_version                  = var.aurora_engine_version
  database_name                   = var.aurora_database_name
  master_username                 = var.aurora_master_username
  manage_master_user_password     = true
  db_subnet_group_name             = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  storage_encrypted               = true
  kms_key_id                      = var.cluster_kms_key_arn
  backup_retention_period          = 7
  preferred_backup_window          = "03:00-04:00"
  skip_final_snapshot              = false
  final_snapshot_identifier        = "${var.name_prefix}-aurora-final"
  deletion_protection              = true

  tags = var.tags
}

resource "aws_rds_cluster_instance" "aurora" {
  count              = var.aurora_instance_count
  identifier         = "${var.name_prefix}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = var.tags
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_aurora_resources -v`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Replace the stale `terraform.tfvars.sample`**

Replace the entire contents of `platform-prerequisites/terraform/postgresql/terraform.tfvars.sample`:

```hcl
# PostgreSQL Terraform Configuration Sample — Aurora (uat/prod only; dev/sit use CNPG in-cluster, no tfvars needed here)
aws_region          = "ap-east-1"
expected_account_id = "REPLACE_ME"
environment         = "REPLACE_ME"
name_prefix         = "oms-REPLACE_ME-postgresql"

# From eks-platform's platform_contract output — copy manually, this root has no remote_state dependency.
vpc_id               = "REPLACE_ME_VPC_ID"
database_subnet_ids  = ["REPLACE_ME_SUBNET_ID_1", "REPLACE_ME_SUBNET_ID_2"]
allowed_source_security_group_id = "REPLACE_ME_WORKLOAD_SG_ID"

# From workload-identity's applied state.
cnpg_backup_bucket_name          = "REPLACE_ME"
postgresql_operator_iam_role_arn = "REPLACE_ME"
cluster_kms_key_arn              = "REPLACE_ME"

aurora_engine_version  = "REPLACE_ME"
aurora_instance_class  = "db.r6g.large"
aurora_instance_count  = 1
aurora_database_name   = "oms"
aurora_master_username = "oms_admin"

tags = { Environment = "REPLACE_ME", ManagedBy = "Terraform" }
```

- [ ] **Step 7: Commit**

```bash
git add platform-prerequisites/terraform/postgresql/ tests/network_cidr/test_aurora_resources.py
git commit -m "feat: add Aurora PostgreSQL cluster resources to the postgresql root for uat/prod"
```

---

### Task 8: Sandbox Teardown Runbook

**Files:**
- Create: `docs/references/sandbox-teardown-runbook.md`
- Test: `tests/network_cidr/test_sandbox_teardown_runbook.py`

**Interfaces:**
- Consumes: nothing from earlier tasks (this is a documentation/procedure deliverable, not
  code — no automated `terraform destroy` execution per Global Constraints).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/network_cidr/test_sandbox_teardown_runbook.py`:

```python
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNBOOK = REPO_ROOT / "docs/references/sandbox-teardown-runbook.md"


class SandboxTeardownRunbookTests(unittest.TestCase):
    def test_runbook_exists(self):
        self.assertTrue(RUNBOOK.is_file())

    def test_runbook_documents_correct_destroy_order(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        mongodb_pos = text.find("terraform destroy")
        # The destroy order (mongodb/postgresql -> workload-identity -> eks-platform)
        # is verified in the design spec's 4-Perspective Critique Findings section.
        self.assertIn("mongodb", text)
        self.assertIn("postgresql", text)
        self.assertIn("workload-identity", text)
        self.assertIn("eks-platform", text)
        order_workload_identity = text.find("cd platform-prerequisites/terraform/workload-identity")
        order_eks_platform = text.find("cd platform-prerequisites/terraform/eks-platform")
        order_mongodb = text.find("cd platform-prerequisites/terraform/mongodb")
        self.assertGreater(order_workload_identity, order_mongodb)
        self.assertGreater(order_eks_platform, order_workload_identity)

    def test_runbook_documents_prevent_destroy_override(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        self.assertIn("prevent_destroy", text)
        self.assertIn("modules/efs/main.tf", text)

    def test_runbook_requires_explicit_confirmation(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        self.assertIn("CONFIRM", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.network_cidr.test_sandbox_teardown_runbook -v`
Expected: FAIL — the runbook file doesn't exist yet.

- [ ] **Step 3: Write the runbook**

Create `docs/references/sandbox-teardown-runbook.md`:

```markdown
# Sandbox Teardown Runbook

**Status:** Manual, operator-executed procedure. No step in this runbook runs automatically —
every command below requires the platform owner to run it explicitly with real AWS
credentials for account `632674123947`.

**Why this exists:** the new Production VPC (`10.200.0.0/17`) fully replaces the `sandbox`
validation environment in the same AWS account, per
`docs/superpowers/specs/2026-07-29-vpc-subnet-and-boomi-routing-design.md`. This must be a
complete teardown with zero leftover resources before Production is provisioned.

## Prerequisites

- AWS credentials for account `632674123947`, region `us-east-1` (sandbox's region).
- Confirm you are targeting `sandbox`, not `prod`, `uat`, or `dev` — every command below
  operates on `platform-prerequisites/terraform/environments/sandbox/*.tfvars`.

## Step 1: Destroy consumers first — `mongodb`

```bash
cd platform-prerequisites/terraform/mongodb
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/mongodb.tfvars -out=sandbox-mongodb-destroy.tfplan
# Review the plan output. It should show only sandbox-prefixed resources.
terraform apply sandbox-mongodb-destroy.tfplan
```

## Step 2: Destroy consumers — `postgresql`

```bash
cd ../postgresql
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/postgresql.tfvars -out=sandbox-postgresql-destroy.tfplan
terraform apply sandbox-postgresql-destroy.tfplan
```

## Step 3: Destroy `workload-identity`

**Verified reason this comes before `eks-platform`, not before `mongodb`/`postgresql`:**
`platform-prerequisites/terraform/workload-identity/main.tf` creates `aws_iam_role.identity`
resources trusted by `pods.eks.amazonaws.com` (EKS Pod Identity), and
`environments/sandbox/mongodb.tfvars` / `environments/sandbox/postgresql.tfvars` reference
those exact roles (`operator_iam_role_arn`, `postgresql_operator_iam_role_arn`). Destroying
`workload-identity` before Steps 1-2 would revoke IAM permissions those operators need for
their own teardown mid-way through.

```bash
cd ../workload-identity
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/workload-identity.tfvars -out=sandbox-workload-identity-destroy.tfplan
terraform apply sandbox-workload-identity-destroy.tfplan
```

## Step 4: Bypass the EFS `prevent_destroy` lifecycle guard, then destroy `eks-platform`

`platform-prerequisites/terraform/modules/efs/main.tf` sets
`lifecycle { prevent_destroy = true }` on `aws_efs_file_system.this`. This must stay `true`
permanently in the module (it protects the future Production EFS filesystem) — do **not**
edit the module file. Instead, override it for this one destroy operation only:

```bash
cd ../eks-platform
terraform init -reconfigure

terraform plan -destroy \
  -var-file=../environments/sandbox/eks-platform.tfvars \
  -out=sandbox-eks-platform-destroy.tfplan
```

**This step will always fail with `Instance cannot be destroyed`, not conditionally.**
Verified against HashiCorp's own documentation (fetched 2026-07-29): *"When
`prevent_destroy` is set to `true`, Terraform rejects **plans** that would destroy the
infrastructure object... and returns an error."* Since the module's `prevent_destroy = true`
is never changed, `terraform plan -destroy` fails deterministically every time, not only
"if" it happens to fail. The state-rm + AWS CLI delete path below is not an optional
fallback — it is the officially documented method for this exact situation (HashiCorp's own
docs point to "Remove a resource from state" for precisely this case) and is the only path
that will work here:

```bash
cd ../eks-platform
terraform state show 'module.efs[0].aws_efs_file_system.this'   # confirm the exact file system ID
terraform state rm 'module.efs[0].aws_efs_file_system.this'
aws efs delete-file-system --file-system-id <FILE_SYSTEM_ID_FROM_ABOVE> --region us-east-1
terraform plan -destroy -var-file=../environments/sandbox/eks-platform.tfvars -out=sandbox-eks-platform-destroy.tfplan
terraform apply sandbox-eks-platform-destroy.tfplan
```

## Step 5: Verify zero leftover resources

```bash
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=Environment,Values=sandbox --query 'ResourceTagMappingList[].ResourceARN'
```

CONFIRM the output is an empty list before proceeding to provision Production in this
account. If any resources remain, investigate and remove them manually before continuing —
do not provision Production until this returns empty.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest tests.network_cidr.test_sandbox_teardown_runbook -v`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add docs/references/sandbox-teardown-runbook.md tests/network_cidr/test_sandbox_teardown_runbook.py
git commit -m "docs: add sandbox teardown runbook with verified destroy order and EFS override"
```

---

### Task 9: Final Integration Verification

**Files:**
- None created or modified — this task only runs checks across everything from Tasks 1-8.

**Interfaces:**
- Consumes: every artifact from Tasks 1-8.
- Produces: nothing (terminal task).

- [ ] **Step 1: Run the full `network_cidr` test suite**

Run: `python3 -m unittest discover -s tests/network_cidr -v`
Expected: every test across all 8 test files PASSES.

- [ ] **Step 2: Run the standalone CIDR validator one more time**

Run: `python3 scripts/validate_cidr_allocations.py`
Expected: `OK: 4 environment(s) checked, no CIDR conflicts.`

- [ ] **Step 3: Run `terraform fmt -check` across every modified/created root and module (offline, safe)**

```bash
cd platform-prerequisites/terraform
terraform fmt -check -recursive modules/network modules/eks eks-platform postgresql
```

Expected: no output (all files already correctly formatted). If it reports a file, run
`terraform fmt -recursive <path>` on that file and re-check.

- [ ] **Step 4: Document the manual apply sequence for the operator (not executed by this plan)**

Confirm the following sequence is understood before any real `terraform apply` runs (this
step is a checklist review, not a command to execute):

1. Run `docs/references/sandbox-teardown-runbook.md` in full for account `632674123947`,
   and confirm Step 5's empty-resource check passes.
2. `terraform apply` the new `environments/prod/eks-platform.tfvars` (after replacing the
   `REPLACE-ME` KMS/OIDC placeholders with real values), then `environments/prod/workload-identity.tfvars`.
3. `terraform apply` the updated `environments/uat/eks-platform.tfvars` (existing UAT
   workload-identity state is unaffected by this plan).
4. `terraform apply` the updated `environments/dev/eks-platform.tfvars`.
5. Create real (non-sample) `postgresql.tfvars` for `uat` and `prod` once `workload-identity`
   is applied for each, using `platform-prerequisites/terraform/postgresql/terraform.tfvars.sample`
   (Task 7) as the template, then `terraform apply` the `postgresql` root for each.

- [ ] **Step 5: Final commit confirming plan completion**

```bash
git add -A
git commit -m "chore: complete network CIDR redesign and Aurora Terraform implementation plan" --allow-empty
```
