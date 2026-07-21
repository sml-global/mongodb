# UAT Access Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build UAT account safety, Access Analyzer, and EKS workforce access entries without changing dev or accessing any AWS account other than the two approved accounts.

**Architecture:** The approved IAM Identity Center groups, permission sets, memberships, and UAT assignments are an external prerequisite owned outside this repository. This repository validates the resulting UAT `AWSReservedSSO_*` role ARNs offline, then uses account-guarded Terraform to create Access Analyzer and EKS access entries only in UAT. Every entrypoint verifies account `672172129937` before backend initialization and never invokes Identity Center APIs.

**Tech Stack:** Bash, Python `unittest`, Terraform >= 1.5, AWS provider >= 5.0, AWS CLI v2, `jq`, EKS access entries, IAM Access Analyzer

---

## Scope And Prerequisites

This is work package 1 of
`docs/superpowers/specs/2026-07-21-uat-workforce-access-design.md`.
Separate plans cover database roles, workload/CSI identity and audit controls,
and any later cross-account S3 access.

Repository-managed mutations are UAT-only. Dev account `815402439714` is
read-only evidence and is not needed during implementation. No other AWS
account may be accessed. This plan creates no Identity Center resources, IAM
users, SAML provider, database users, Pod Identity roles, or S3 permissions.

Before EKS access can be planned, the authorized identity owner supplies:

| JSON key | Permission set | Membership | EKS result |
|---|---|---|---|
| `infra_admin_role_arn` | `UATInfraAdminEA` | `frankcheong` | Cluster admin |
| `application_developer_role_arn` | `UATApplicationDeveloper` | `yczhang`, `xavierlee`, `jiaweima` | Cluster admin |
| `boomi_admin_role_arn` | `UATBoomiAdmin` | `JesusRosario`, `jacklee` | Admin in `boomi-uat` |
| `process_owner_role_arn` | `UATBoomiProcessOwner` | No initial members | No EKS entry |

If these external UAT roles do not exist, stop at the prerequisite report. Do
not replace them with IAM users or SAML roles.

## File Structure

| File | Responsibility |
|---|---|
| `config/environments/uat.env` | UAT account, region, cluster, namespace, and state contract. |
| `scripts/lib/platform-env.sh` | Reject wrong AWS identity or Kubernetes context. |
| `scripts/validate-uat-workforce-principals.sh` | Validate external UAT role ARNs offline. |
| `scripts/provision-uat-access.sh` | UAT-only governance and EKS orchestration. |
| `platform-prerequisites/terraform/access-governance/` | UAT Access Analyzer. |
| `platform-prerequisites/terraform/eks-access/` | UAT EKS access entries and associations. |
| `tests/uat_access/` | Safety, ordering, and static-contract tests. |

### Task 1: Add fail-closed UAT environment safety

**Files:**
- Create: `tests/uat_access/__init__.py`
- Create: `tests/uat_access/test_platform_env.py`
- Create: `config/environments/uat.env`
- Create: `scripts/lib/platform-env.sh`

- [ ] **Step 1: Write failing preflight tests**

Use Python `unittest` with temporary mocked `aws` and `kubectl` executables.
The AWS mock returns `MOCK_AWS_ACCOUNT_ID` only for
`sts get-caller-identity`; both mocks append invocations to
`MOCK_COMMAND_LOG`. Implement:

```python
def run_shell(self, command, account="672172129937", context=""):
    env = os.environ.copy()
    env.update({
        "PATH": f"{self.mock_bin}:{env['PATH']}",
        "MOCK_AWS_ACCOUNT_ID": account,
        "MOCK_KUBE_CONTEXT": context,
        "MOCK_COMMAND_LOG": str(self.command_log),
    })
    return subprocess.run(
        ["bash", "-c", command], cwd=REPO_ROOT, env=env,
        text=True, capture_output=True,
    )
```

Test that UAT succeeds, dev fails with `expected 672172129937`, an unknown
environment fails with `accepts only uat`, and a dev Kubernetes context fails
with `does not target UAT`.

- [ ] **Step 2: Verify the tests fail**

```bash
python3 -m unittest tests.uat_access.test_platform_env -v
```

Expected: FAIL because config and shell library do not exist.

- [ ] **Step 3: Create exact UAT configuration**

```bash
ENVIRONMENT=uat
EXPECTED_AWS_ACCOUNT_ID=672172129937
AWS_REGION=ap-east-1
EKS_CLUSTER_NAME=EKS-boomi-runtime-cluster
BOOMI_NAMESPACE=boomi-uat
TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937
TF_STATE_REGION=ap-east-1
ACCESS_GOVERNANCE_STATE_KEY=oms/uat/access-governance.tfstate
EKS_ACCESS_STATE_KEY=oms/uat/eks-access.tfstate
```

- [ ] **Step 4: Implement `platform-env.sh`**

Implement `load_platform_env uat`, required-variable checks, exact UAT account
contract validation, `verify_aws_identity` using STS, and
`verify_kubernetes_context` requiring the UAT account and cluster in the
current context. Functions return non-zero with actionable errors; the file has
no top-level execution.

- [ ] **Step 5: Verify and commit**

```bash
python3 -m unittest tests.uat_access.test_platform_env -v
bash -n scripts/lib/platform-env.sh
git add config/environments/uat.env scripts/lib/platform-env.sh tests/uat_access
git commit -m "feat: add UAT access safety preflight"
```

Expected: tests PASS and Bash syntax exits 0.

### Task 2: Validate external workforce principals offline

**Files:**
- Create: `tests/uat_access/test_principal_validation.py`
- Create: `scripts/validate-uat-workforce-principals.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing validator tests**

Use role ARNs shaped as:

```text
arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_<PermissionSet>_<suffix>
```

Valid input has exactly the four table keys. Assert output has exactly the
three EKS keys. Add failures for a missing key, extra key, wrong account, wrong
permission-set prefix, duplicate ARN, and non-`AWSReservedSSO_` role. Put a
mock `aws` in `PATH` that fails if invoked.

- [ ] **Step 2: Verify the tests fail**

```bash
python3 -m unittest tests.uat_access.test_principal_validation -v
```

Expected: FAIL because the validator does not exist.

- [ ] **Step 3: Implement strict offline validation**

Create a script accepting `--input <json> --output <json>`. Use `jq -e` to
require exact keys, account `672172129937`, unique values, and prefixes:

```text
AWSReservedSSO_UATInfraAdminEA_
AWSReservedSSO_UATApplicationDeveloper_
AWSReservedSSO_UATBoomiAdmin_
AWSReservedSSO_UATBoomiProcessOwner_
```

Write only the three EKS keys to a temporary file, validate with `jq empty`,
set mode `0600`, and atomically rename. Do not call AWS.

- [ ] **Step 4: Ignore local inputs and verify**

Append to `.gitignore`:

```gitignore
config/environments/uat-workforce-principals.json
platform-prerequisites/terraform/eks-access/generated.auto.tfvars.json
```

Run and commit:

```bash
python3 -m unittest tests.uat_access.test_principal_validation -v
bash -n scripts/validate-uat-workforce-principals.sh
git add .gitignore scripts/validate-uat-workforce-principals.sh \
  tests/uat_access/test_principal_validation.py
git commit -m "feat: validate UAT workforce principals"
```

Expected: tests PASS and no AWS invocation occurs.

### Task 3: Add UAT access governance

**Files:**
- Create: `tests/uat_access/test_static_contract.py`
- Create: `platform-prerequisites/terraform/access-governance/versions.tf`
- Create: `platform-prerequisites/terraform/access-governance/variables.tf`
- Create: `platform-prerequisites/terraform/access-governance/main.tf`
- Create: `platform-prerequisites/terraform/access-governance/outputs.tf`
- Create: `platform-prerequisites/terraform/access-governance/uat.tfvars`

- [ ] **Step 1: Write failing static tests**

Assert `main.tf` contains `aws_accessanalyzer_analyzer`. Across both new roots,
assert absence of `aws_ssoadmin_`, `aws_identitystore_`, `aws_iam_user`,
`aws_iam_access_key`, dev account ID, and any unapproved account ID.

- [ ] **Step 2: Verify the tests fail**

```bash
python3 -m unittest tests.uat_access.test_static_contract -v
```

Expected: FAIL because governance Terraform does not exist.

- [ ] **Step 3: Implement account-guarded Terraform**

Require Terraform `>= 1.5.0`, AWS provider `>= 5.0`, and `backend "s3" {}`.
Configure `allowed_account_ids = [var.expected_account_id]`, default UAT tags,
and variable validation accepting only region `ap-east-1` and account
`672172129937`. Create:

```hcl
resource "aws_accessanalyzer_analyzer" "uat_account" {
  analyzer_name = "uat-account-access-analyzer"
  type          = "ACCOUNT"
}
```

Output analyzer ARN/name and set exact values in `uat.tfvars`.

- [ ] **Step 4: Validate and commit**

```bash
terraform -chdir=platform-prerequisites/terraform/access-governance fmt -recursive
terraform -chdir=platform-prerequisites/terraform/access-governance init -backend=false
terraform -chdir=platform-prerequisites/terraform/access-governance validate
python3 -m unittest tests.uat_access.test_static_contract -v
git add platform-prerequisites/terraform/access-governance \
  tests/uat_access/test_static_contract.py
git commit -m "feat: add UAT access governance"
```

Expected: Terraform and static tests PASS.

### Task 4: Add UAT EKS workforce access

**Files:**
- Create: `platform-prerequisites/terraform/eks-access/versions.tf`
- Create: `platform-prerequisites/terraform/eks-access/variables.tf`
- Create: `platform-prerequisites/terraform/eks-access/main.tf`
- Create: `platform-prerequisites/terraform/eks-access/outputs.tf`
- Create: `platform-prerequisites/terraform/eks-access/uat.tfvars`
- Modify: `tests/uat_access/test_static_contract.py`

- [ ] **Step 1: Add failing EKS tests**

Assert exactly three principals (`infra_admin`, `application_developer`,
`boomi_admin`), no `process_owner`, Boomi Admin namespace scope with
`namespaces = [var.boomi_namespace]`, and no Identity Center/IAM-user resources.

- [ ] **Step 2: Verify the tests fail**

```bash
python3 -m unittest tests.uat_access.test_static_contract -v
```

Expected: FAIL because EKS Terraform does not exist.

- [ ] **Step 3: Implement validated inputs**

Use the Task 3 provider guard. Validate every principal starts with:

```text
arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/
```

Set cluster `EKS-boomi-runtime-cluster` and namespace `boomi-uat` in
`uat.tfvars`.

- [ ] **Step 4: Implement entries and associations**

Use one `aws_eks_access_entry` with `for_each` over the three principals.
Associate `AmazonEKSClusterAdminPolicy` at cluster scope to Infra Admin / EA
and Application Developer. Associate `AmazonEKSAdminPolicy` to Boomi Admin:

```hcl
access_scope {
  type       = "namespace"
  namespaces = [var.boomi_namespace]
}
```

Create no Process Owner entry and do not modify `aws-auth`. Output entry and
policy ARNs only.

- [ ] **Step 5: Validate and commit**

Generate temporary ignored valid role input, then run:

```bash
terraform -chdir=platform-prerequisites/terraform/eks-access fmt -recursive
terraform -chdir=platform-prerequisites/terraform/eks-access init -backend=false
terraform -chdir=platform-prerequisites/terraform/eks-access validate
python3 -m unittest tests.uat_access.test_static_contract -v
rm -f platform-prerequisites/terraform/eks-access/generated.auto.tfvars.json
git add platform-prerequisites/terraform/eks-access \
  tests/uat_access/test_static_contract.py
git commit -m "feat: define UAT EKS workforce access"
```

Expected: Terraform and static tests PASS.

### Task 5: Add UAT-only orchestration

**Files:**
- Create: `scripts/provision-uat-access.sh`
- Modify: `tests/uat_access/test_platform_env.py`

- [ ] **Step 1: Add failing ordering tests**

Assert:

```text
governance: verify UAT account -> backend -> fmt -> validate -> plan -> apply
eks-access: verify account -> verify context -> offline principal validation -> backend -> fmt -> validate -> plan -> apply
all: governance before eks-access
wrong account: no backend, Terraform, mutation, or generated output
missing principals: stop before backend
```

Assert no invocation contains `sso-admin`, `identitystore`, `organizations`,
`sts assume-role`, or another account/profile.

- [ ] **Step 2: Verify the tests fail**

```bash
python3 -m unittest tests.uat_access.test_platform_env -v
```

Expected: FAIL because the entrypoint does not exist.

- [ ] **Step 3: Implement the entrypoint**

Create `provision-uat-access.sh <governance|eks-access|all>
[--auto-approve]`. Load UAT and verify STS before backend bootstrap. For EKS,
also verify context and convert ignored principal input to ignored Terraform
input before backend bootstrap. Each root runs `fmt -check`, `validate`, saved
`plan`, and applies only after successful planning. `all` runs governance then
EKS. Never call Identity Center APIs or existing dev provisioning scripts.

- [ ] **Step 4: Verify and commit**

```bash
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
bash -n scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/platform-env.sh
git add scripts/provision-uat-access.sh tests/uat_access/test_platform_env.py
git commit -m "feat: orchestrate UAT workforce access"
```

Expected: all tests PASS and Bash syntax exits 0.

### Task 6: Document the external identity handoff

**Files:**
- Modify: `docs/guides/environment-setup.md`
- Modify: `docs/guides/operator-runbook.md`
- Modify: `docs/references/verification-commands.md`
- Modify: `docs/index.md`

- [ ] **Step 1: Document boundaries and commands**

Document the four external permission sets, memberships, required UAT ARN JSON,
and that repository automation does not manage or inspect Identity Center. Say
explicitly: UAT-only mutation, no other AWS account access, no SAML/IAM-user
fallback, Process Owner gets no EKS entry, and database/workload/S3 access is
deferred.

Document:

```bash
bash scripts/validate-uat-workforce-principals.sh \
  --input config/environments/uat-workforce-principals.json \
  --output platform-prerequisites/terraform/eks-access/generated.auto.tfvars.json
bash scripts/provision-uat-access.sh governance
bash scripts/provision-uat-access.sh eks-access
```

Link the approved design and this plan from `docs/index.md`.

- [ ] **Step 2: Commit documentation**

```bash
git add docs/guides/environment-setup.md docs/guides/operator-runbook.md \
  docs/references/verification-commands.md docs/index.md
git commit -m "docs: add UAT access handoff"
```

### Task 7: Verify the foundation end to end

**Files:**
- Verify: all files from Tasks 1-6

- [ ] **Step 1: Run executable verification**

```bash
terraform fmt -check -recursive platform-prerequisites/terraform/access-governance
terraform fmt -check -recursive platform-prerequisites/terraform/eks-access
terraform -chdir=platform-prerequisites/terraform/access-governance validate
terraform -chdir=platform-prerequisites/terraform/eks-access validate
python3 -m unittest discover -s tests/uat_access -p 'test_*.py' -v
bash -n scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/platform-env.sh
git diff --check
```

Expected: all commands exit 0 and tests pass.

- [ ] **Step 2: Prove forbidden APIs/accounts are absent**

```bash
if rg -n 'aws_ssoadmin_|aws_identitystore_|sso-admin|identitystore|organizations|sts assume-role|815402439714' \
  config/environments/uat.env scripts/provision-uat-access.sh \
  scripts/validate-uat-workforce-principals.sh scripts/lib/platform-env.sh \
  platform-prerequisites/terraform/access-governance \
  platform-prerequisites/terraform/eks-access; then
  echo "Forbidden account or identity API reference found" >&2
  exit 1
fi
```

Expected: no matches. Rejection tests may reference dev; implementation may not.

- [ ] **Step 3: Produce read-only UAT plans**

After direct UAT authentication and receipt of all four approved ARNs:

```bash
bash scripts/provision-uat-access.sh governance
bash scripts/provision-uat-access.sh eks-access
```

Do not approve apply. Expected: one Access Analyzer; three EKS entries and
three associations; Boomi Admin scoped only to `boomi-uat`.

- [ ] **Step 4: Record evidence**

Record UAT account ID, validated principal ARNs, plan summaries,
denied-boundary checks, and timestamps. Do not commit role ARN input or plans.

## Completion Gate

Complete only when external UAT Identity Center roles exist, repository code
never accesses their owner, all tests pass, wrong-account tests prove no
mutation starts, governance plans only Access Analyzer, EKS plans exactly three
principals, Boomi Admin is namespace-scoped, and no database, S3, dev, SAML,
IAM-user, or legacy-credential mutation appears.

Do not begin database-access work before this evidence is recorded.