# Operator Runbook

Step-by-step provisioning guide, safety gates, runbook commands, and troubleshooting.

**Who this is for:** Infra Operators who need to provision and maintain the OMS data layer.

**Pre-requisite:** Complete [Environment Setup](environment-setup.md) first.

**Related docs:**
- [Glossary](../references/glossary.md) — jargon/acronym lookup
- [Component Catalog](../references/component-catalog.md) — what each component does
- [Verification Commands](../references/verification-commands.md) — per-component health checks
- [Recovery Procedures](../references/recovery-procedures.md) — when things go wrong
- [Configuration Catalog](../operations/dev-configuration-catalog.md) — all embedded defaults

---

## Quick Start (Experienced Operators)

Use this only after you understand the target environment and state location.

```bash
# Create tfvars for both roots
cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/terraform.tfvars
cp platform-prerequisites/terraform/postgresql/terraform.tfvars.sample platform-prerequisites/terraform/postgresql/terraform.tfvars
nano platform-prerequisites/terraform/mongodb/terraform.tfvars
nano platform-prerequisites/terraform/postgresql/terraform.tfvars

# Provision everything
bash scripts/provision.sh all --auto-approve
bash scripts/provision.sh signoz --auto-approve
bash scripts/provision.sh signoz-observability --auto-approve

# Verify
scripts/verify-platform-health.sh --smoke-test
```

This shortcut does not replace plan review. Stop before apply if the generated plan does not match the intended change.

---

## UAT Access Foundation Procedure

This procedure is separate from, and does not replace, the existing dev data
layer procedures in this runbook. It is limited to UAT account `672172129937`,
region `ap-east-1`, cluster `EKS-boomi-runtime-cluster`, and namespace
`boomi-uat`. Dev account `815402439714` is read-only evidence for this work and
must not be mutated; no other AWS account may be accessed.

Before starting:

1. Obtain deployment authorization.
2. Complete the exact
  [Authorized UAT Workstation Setup](environment-setup.md#authorized-uat-workstation-setup).
  Before proceeding, `AWS_PROFILE` must be `oms-uat`, `AWS_REGION` must be
  `ap-east-1`, STS must report account `672172129937`, and the selected
  Kubernetes context must resolve to the canonical UAT cluster ARN. The
  entrypoint verifies both AWS identity and context before backend
  initialization. Terraform `>= 1.10.0` is required for these two UAT roots,
  which use native S3 lockfiles; this does not change the dev workflow.
3. Confirm the external EKS cluster authentication mode is `API` or
  `API_AND_CONFIG_MAP`. The entrypoint checks this read-only prerequisite after
  account and context validation and does not mutate the cluster mode. It
  stops before generated output, backend initialization, or Terraform for
  `CONFIG_MAP`, an empty response, or an AWS error.
4. Confirm the external Identity Center owner has completed the permission-set
  and membership handoff in
  [Environment Setup](environment-setup.md#uat-workforce-access-prerequisite).
  Repository automation does not manage or inspect Identity Center. There is
  no SAML or IAM-user fallback.
5. Save all four owner-supplied role ARNs at the documented gitignored JSON
  path. Do not fabricate ARN suffixes.

The offline check may be run before any authorized AWS operation:

```bash
bash scripts/validate-uat-workforce-principals.sh \
  --input config/environments/uat-workforce-principals.json \
  --output platform-prerequisites/terraform/eks-access/generated.auto.tfvars.json
```

The generated tfvars contains only the three roles that receive EKS entries:
Infra Admin / EA and Application Developer receive cluster administration;
Boomi Admin receives administrator access only in `boomi-uat`. Process Owner
is validated as part of the external role contract but receives no EKS entry.
The file is local and gitignored. Remove it after a standalone validation; the
orchestration entrypoint regenerates it for EKS planning and removes it after
the plan is saved or whenever the command exits.

After reviewing the approved
[UAT Access Foundation Plan](../superpowers/plans/2026-07-21-uat-access-foundation.md),
run governance before EKS access:

```bash
bash scripts/provision-uat-access.sh governance
bash scripts/provision-uat-access.sh eks-access
```

`governance` verifies the UAT identity, acquires the local orchestration lock,
and then initializes the backend before planning the UAT account Access
Analyzer. `eks-access` verifies identity, Kubernetes context, and EKS
authentication mode before acquiring that lock; it then validates the external
principal file before backend initialization and plans exactly three EKS access
entries and policy associations. `all` acquires one lock after all required
identity/context prerequisites and holds it through governance and EKS, with
governance apply completing before EKS generated output or backend work. The
two UAT roots also use native S3 lockfiles. Use these repository entrypoints
only; do not run raw Terraform or reuse existing dev provisioning scripts for
this UAT workflow.

By default, each saved plan is applied only after the operator reviews it and
types the exact response `yes`. Stop instead of approving if the plan differs
from the authorized UAT scope. The optional `--auto-approve` flag skips that
explicit repository prompt and is appropriate only for a separately reviewed,
known-good rerun under deployment authorization; it does not relax account,
context, validation, or ordering gates. To run both authorized scopes in the
same order, use `bash scripts/provision-uat-access.sh all` with the same
approval rules.

This foundation provisions only UAT Access Analyzer governance and the stated
EKS workforce entries. Database authorization, workload and CSI identity,
cross-account S3 access, and Boomi Platform authorization are deferred to later
work packages. It does not provision or imply any of those capabilities. See
[UAT Access Foundation Verification](../references/verification-commands.md#uat-access-foundation-verification)
for the current evidence status and future authorized checks.

---

## Provisioning Choices

| Goal | When To Use It | Command |
|---|---|---|
| Full baseline | First-time setup or convergence check | `bash scripts/provision.sh all` |
| MongoDB only | MongoDB updates without touching PostgreSQL | `bash scripts/provision.sh mongodb` |
| PostgreSQL only | PostgreSQL updates without touching MongoDB | `bash scripts/provision.sh pg` |
| SigNoz (telemetry) | Install or update the telemetry stack | `bash scripts/provision.sh signoz` |
| SigNoz observability | Apply dashboards and alert rules as code after SigNoz is healthy | `bash scripts/provision.sh signoz-observability --auto-approve` |

Why `signoz` and `signoz-observability` are separate:
1. `signoz` manages platform lifecycle (pods, storage, startup readiness).
2. `signoz-observability` manages API-level objects (dashboards/alerts) that require a ready endpoint and auth.
3. This split reduces blast radius and keeps failures easier to isolate.

## Standard Operator Procedure

### Step 0: Confirm Environment

Purpose: confirms your workstation is ready.

```bash
scripts/verify-platform-health.sh --preflight
```

Expected: all preflight checks pass. If not, return to [Environment Setup](environment-setup.md).

### Step 1: Choose Scope and Create Variables File

Scope-to-root mapping:
- `all` → runs `mongodb` then `pg` sequentially (create BOTH tfvars files)
- `mongodb` → `platform-prerequisites/terraform/mongodb`
- `pg` → `platform-prerequisites/terraform/postgresql`

For `mongodb`:

```bash
cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/terraform.tfvars
```

For `pg`:

```bash
cp platform-prerequisites/terraform/postgresql/terraform.tfvars.sample platform-prerequisites/terraform/postgresql/terraform.tfvars
```

Expected: selected root has local `terraform.tfvars` file (not committed to git).

### Step 2: Fill Required Values

Required minimum values:
- **mongodb**: `cluster_name`
- **pg**: `vpc_id`, `private_subnet_ids`, `db_master_password` (at least 8 chars, printable ASCII, no `/`, `"`, or `@`)
- **all**: fill both files

Expected: no required value is empty or left as a placeholder.

### Step 3: Run Provisioning

Preferred operator entrypoint (runs platform prerequisites + required k8s components):

```bash
bash scripts/provision.sh all
```

Alternative Terraform-only entrypoint (use only when you intentionally do not want the k8s apply step):

```bash
bash scripts/provision-platform-prereq.sh all
```

Alternative scopes:

```bash
bash scripts/provision-platform-prereq.sh mongodb
bash scripts/provision-platform-prereq.sh pg
```

Optional — skip interactive plan confirmation (use only for known-good reruns):

```bash
bash scripts/provision-platform-prereq.sh mongodb --auto-approve
```

What this does:
- Uses remote S3 state (bucket `sml-oms-dev-tfstate` in `ap-east-1`)
- Bootstraps the backend bucket if needed
- Runs `terraform fmt`, `validate`, `plan`, `apply`

Expected: scope applies successfully.

### Step 4: Create MongoDB Secrets (MongoDB scope only)

Skip this step if you only ran the `pg` scope.

```bash
scripts/bootstrap-dev-secrets.sh
```

The script auto-decides:
- Secret already exists → skip
- Escrow file exists on disk → use it
- Nothing exists → generate, save escrow, create secret

Expected: `psmdb-encryption-key` and `psmdb-secrets` exist in namespace `mongodb`.

> **Important:** Copy escrow files (`.local-dev-encryption-key.txt`, `.local-dev-user-passwords.txt`) to a secure location immediately. If lost and cluster secrets are deleted, encrypted MongoDB data may be permanently inaccessible.

### Step 5: Create Audit Writer Secret (MongoDB scope only)

Skip this step if you only ran the `pg` scope.

```bash
scripts/create-audit-writer-secret.sh
```

This creates the `oms-audit-writer` Kubernetes Secret that the Boomi audit log library reads.
If it already exists, the script skips safely.

Expected: Secret `oms-audit-writer` exists in namespace `mongodb`.

### Step 6: Validate MongoDB Overlay (MongoDB scope only)

Skip this step if you only ran the `pg` scope.

```bash
scripts/validate-dev-render.sh
```

Expected: render succeeds, structural checks pass.

### Step 7: Provision SigNoz (if needed)

```bash
bash scripts/provision.sh signoz
```

Expected: SigNoz pods running in namespace `signoz`, including `signoz-0` at
`1/1 Ready` (see Step 7A below for what makes that possible without a manual
signup step).

> **Security:** The ClickHouse password in `gitops/signoz/base/helmreleases.yaml` is set to a placeholder (`CHANGE_ME_BEFORE_PRODUCTION`). Replace it with a real password before deploying to any shared or production environment.

### Step 7A: SigNoz Admin Account Bootstrap (Automated, No Manual Signup)

This environment uses SigNoz's **root user** feature (v0.112.0+) so the admin
account is created automatically at pod startup -- nobody needs to race to be
"first to sign up". `gitops/signoz/base/helmreleases.yaml` wires
`SIGNOZ_USER_ROOT_EMAIL`/`SIGNOZ_USER_ROOT_PASSWORD` to a `signoz-root-user`
Secret **without** `optional: true` -- if that Secret doesn't exist, the
`signoz-0` pod fails to start with `CreateContainerConfigError`.

**`scripts/provision.sh signoz` (Step 7) now handles this automatically** --
it creates the `signoz-root-user` Secret first if missing, and restarts the
`signoz` StatefulSet afterward if it had already been created without one
(Kubernetes does not hot-inject a newly created Secret's values into an
already-running or already-erroring pod, so a restart is required in that
specific case). You do not need to run the two steps in a particular order
anymore -- but if you want explicit control over the generated credentials
before SigNoz ever starts, you can still run the bootstrap first:

```bash
bash scripts/create-signoz-root-user-secret.sh
bash scripts/provision.sh signoz
```

What this does:
- Creates the `signoz-root-user` Secret (namespace `signoz`) with a generated
  email/password meeting SigNoz's password policy (12+ chars, upper/lower/
  digit/symbol)
- The HelmRelease (`gitops/signoz/base/helmreleases.yaml`) wires
  `SIGNOZ_USER_ROOT_*` env vars to that Secret, so the admin account exists
  the moment the `signoz-0` pod starts

If you ever see `signoz-0` stuck in `CreateContainerConfigError`, that
Secret is missing -- re-run `scripts/provision.sh signoz` (self-heals) or
manually:

```bash
kubectl -n signoz get secret signoz-root-user || bash scripts/create-signoz-root-user-secret.sh
kubectl -n signoz rollout restart statefulset/signoz
```

Retrieve the credentials any time (source of truth is the Secret, not any
file):

```bash
kubectl -n signoz get secret signoz-root-user -o jsonpath='{.data.email}' | base64 -d; echo
kubectl -n signoz get secret signoz-root-user -o jsonpath='{.data.password}' | base64 -d; echo
```

A convenience copy is also appended to the gitignored
`.local-dev-user-passwords.txt` the first time the script runs.

After logging in with those credentials:
1. **Settings** -> **Organization** -> invite additional admins (at least one
   backup admin) and least-privilege users:
  - `omsadmin@sml.com`: **Admin** (day-to-day operations owner)
  - `infraadmin@sml.com`: **Admin** (infrastructure escalation owner)
  - Boomi Admin account(s): **Editor**
  - Enterprise Architect account(s): **Viewer**
2. Record admin ownership in your team runbook.
3. Confirm ingress controls for production (SSO/OIDC + restricted source
   networks) before broad access.

> **Fallback (pre-v0.112 SigNoz, or if you prefer manual control):** skip
> `create-signoz-root-user-secret.sh` and instead let the first person to
> open the dashboard sign up manually -- that person becomes the admin. See
> [Boomi Integration Guide § SigNoz Dashboard](boomi-integration-guide.md#accessing-signoz-dashboard).

### Step 7A.1: SigNoz First-Login Checklist (Do This In Order)

Use this when the SigNoz dashboard shows onboarding cards ("add data source", "send logs/traces/metrics", and similar).

| Dashboard prompt | What to do in this repo | Required now? |
|---|---|---|
| Add your first data source | Skip for now. OTLP ingestion path is already wired by platform setup. | Optional |
| Send your logs | Validate with `scripts/verify-platform-health.sh --smoke-test` or `scripts/run-audit-telemetry-test.sh`. | Yes |
| Send your traces | Covered by the same smoke/test scripts. | Yes |
| Send your metrics | Not required for current audit-log acceptance path. | Optional |
| Setup alerts | Automated -- see Step 7B below (`signoz-observability`). Add extra alerts by hand only for cases the baseline set doesn't cover. | Automated |
| Setup saved views | Save baseline log filters (for example `service.name = oms-audit-writer`). | Recommended (day-2) |
| Setup dashboards | Automated -- see Step 7B below (`signoz-observability`). | Automated |

Minimum Day-1 completion criteria:
1. Admin account created (automated root-user bootstrap, or manual first signup as fallback).
2. Role-based users invited (Admin backup, Editor, Viewer).
3. Log/trace ingestion verified by smoke/test script.
4. Baseline dashboards + alerts applied (Step 7B).

Notification setup note:
- SMTP is only required if you want email alert notifications.
- If you use Slack/webhook/PagerDuty notification channels, SMTP is not required.

### Step 7B: Provision Dashboards & Alerts (as Code)

Once SigNoz is reachable and the admin account exists, dashboards and alert
rules for every monitored signal (K8s nodes, MongoDB, PostgreSQL, the OTel
Collector pipelines, Boomi app telemetry) are applied as code via Terraform --
not clicked together by hand.

**Fully automated, including the Service Account/API key**: SigNoz itself
requires a Service Account + API key before its Terraform provider can
authenticate, but this is no longer a manual step -- the first time you run
the command below and the `signoz-api-key` Secret doesn't exist yet, it
automatically invokes `scripts/bootstrap-signoz-service-account.sh`, which
drives a headless Chromium browser (Playwright) through the same steps a
human would use (create Service Account -> assign `signoz-admin` role ->
create an API key) and stores the result as the `signoz-api-key` Secret. No
UI clicking, no separate port-forward session required.

One-time setup for the headless browser itself (uses `python3`, already a
required tool -- see [Environment Setup](environment-setup.md)):

```bash
python3 -m pip install playwright
python3 -m playwright install chromium
```

From then on, applying (and re-applying) dashboards/alerts is one command,
safe to run repeatedly (idempotent -- verified: two consecutive runs produce
the same 5 dashboard + 5 alert IDs with `0 added, 0 destroyed`):

```bash
bash scripts/provision.sh signoz-observability --auto-approve
```

Full details, the exact list of dashboards/alerts created, and a manual
JSON-import fallback: [SigNoz Dashboard Import Pack](../references/signoz-dashboard-import-pack.md).

### Step 7C: Validate SigNoz Reachability For Intended Persona

Before handing off dashboard usage, verify the access path matches the target user:

- Infra Operator/Architect in dev: `scripts/open-signoz-ui.sh`
- Shared/prod users: `scripts/open-signoz-ui.sh --mode ingress`

Checks:
- Viewer account can log in and open dashboards
- Editor account can access logs/traces query pages
- Non-admin accounts cannot access organization admin settings

### Step 8: Verify Deployment

```bash
scripts/verify-platform-health.sh
```

Or check specific components — see [Verification Commands](../references/verification-commands.md).

---

## Day-2 Operations (Ongoing Maintenance)

Use this section after initial provisioning to run recurring checks and controlled changes.

### Recurring Health Checks

Run at least daily in active environments and after any infrastructure or integration change:

```bash
scripts/verify-platform-health.sh
```

For path-level confidence (write/read/telemetry), run post-change smoke:

```bash
scripts/verify-platform-health.sh --smoke-test
```

### Trigger-Based Maintenance

Run these only when a trigger occurs:

| Trigger | Action |
|---|---|
| MongoDB URI or credentials changed | Re-run `scripts/create-audit-writer-secret.sh` |
| New telemetry users need access | Update SigNoz users/roles in Settings |
| Secret rotation or controlled rebuild | Re-run `scripts/bootstrap-dev-secrets.sh` with change record |
| Incident or failed health check | Follow [Recovery Procedures](../references/recovery-procedures.md) |

### Day-2 Change Checklist

1. Confirm target scope and rollback approach.
2. Run the minimum provisioning scope (`mongodb`, `pg`, or `signoz`).
3. Execute post-change verification (`scripts/verify-platform-health.sh`).
4. Run smoke validation for integration-impacting changes.
5. Record outcome, owner, and timestamp in team runbook.

---

## What Happens When The Script Runs

```mermaid
flowchart TD
  A[Operator runs scripts/provision-platform-prereq.sh] --> B{Scope}
  B -->|all| B1[Run mongodb then pg sequentially]
  B -->|mongodb| B2[Root: mongodb, state key: oms/dev/mongo.tfstate]
  B -->|pg| B3[Root: postgresql, state key: oms/dev/pg.tfstate]
  B1 --> B2
  B1 --> B3
  B2 --> C[Prepare S3 backend]
  B3 --> C
  C --> E[Format Terraform files]
  E --> F[Validate configuration]
  F --> G[Plan and apply]
```

The script stops on any error (init, format, validate, plan, or apply).

---

## Required Safety Gates

Do not apply infrastructure until these gates are satisfied.

| Gate | Required Evidence | Stop If |
|---|---|---|
| Environment | AWS account, region, cluster confirmed | Any target value is guessed |
| Access | AWS identity has permissions, kubectl works | Returns Unauthorized/Forbidden |
| Tooling | All required CLIs available | Any command missing |
| Configuration | `terraform.tfvars` exists with real values | Values are empty or placeholders |
| State | Using correct S3 bucket and key | State location changed accidentally |
| Plan/Apply | Provisioning script succeeds | Any step fails |
| Controllers | Flux, Kyverno, cert-manager, EBS CSI exist | CRD preflight fails |
| MongoDB readiness | Secret bootstrap and render check pass | Secret or render fails |

---

## Runbook Commands

| Command | What It Does | When To Run |
|---|---|---|
| `bash scripts/provision.sh <all\|mongodb\|pg\|signoz>` | Full provisioning for scope | Day-1 and selective reruns |
| `bash scripts/provision.sh <scope> --bootstrap-platform-controllers` | Same + installs missing controllers | Platform-admin bootstrap |
| `bash scripts/provision-platform-prereq.sh <all\|mongodb\|pg>` | Terraform-only provisioning | Infra-only changes |
| `bash scripts/provision-k8s-components.sh <scope>` | Kubernetes manifests only | K8s-only changes |
| `scripts/bootstrap-dev-secrets.sh` | Create MongoDB secrets | After Terraform, before workload |
| `scripts/validate-dev-render.sh` | Render check for MongoDB overlay | Before applying manifests |
| `scripts/verify-dev-identity.sh` | Check pod ServiceAccount | After MongoDB pods start |
| `scripts/verify-platform-health.sh` | Full platform verification | After any provisioning |
| `scripts/verify-platform-health.sh --preflight` | Environment-only check | Before provisioning |
| `scripts/open-signoz-ui.sh` | SigNoz dashboard access (dev) | When viewing telemetry |
| `scripts/open-signoz-ui.sh --mode ingress` | SigNoz dashboard URL (prod) | Production access |
| `scripts/create-signoz-root-user-secret.sh` | Bootstrap SigNoz admin account (no manual signup) | Once per environment, before/with `provision.sh signoz` |
| `bash scripts/provision.sh signoz-observability --auto-approve` | Apply dashboards + alert rules as code | After SigNoz is up (API key bootstrap is automated if missing) |
| `bash scripts/destroy.sh <mongodb\|pg\|signoz\|all>` | Scoped teardown | Post-test cleanup, controlled rebuild — see [Recovery Procedures § Component-by-component teardown](../references/recovery-procedures.md#component-by-component-teardown) |

---

## Troubleshooting

### Common First-Run Issues

| What Was Missed | How To Check | Fix |
|---|---|---|
| Wrong AWS account or region | `aws sts get-caller-identity` | Switch profile/region |
| AWS SSO not logged in | `aws sts get-caller-identity` | `aws sso login --profile default` |
| Wrong Kubernetes context | `kubectl config current-context` | Update kubeconfig |
| `terraform.tfvars` not created | Check root for file | Copy from sample |
| Placeholder values left | Review tfvars content | Replace with real values |
| State bucket override | `echo "$TF_STATE_BUCKET"` | `unset TF_STATE_BUCKET` |
| Missing CLI tools | `command -v terraform aws kubectl` | Install and reopen shell |
| Missing platform controllers | `kubectl get crd helmreleases.helm.toolkit.fluxcd.io` | Use `--bootstrap-platform-controllers` |
| No RBAC in mongodb namespace | `kubectl auth can-i create secrets -n mongodb` | Fix EKS Access Entry |

### AWS SSO And Credentials

| Symptom | Fix |
|---|---|
| `The config profile could not be found` | `aws configure sso --profile default` |
| Browser login expired | `aws sso login --profile default` |
| `Unable to locate credentials` | `export AWS_PROFILE=default` |
| Wrong region | `export AWS_REGION=ap-east-1` |
| `AccessDenied` | Ask account owner for correct permission set |

### Kubernetes Access

| Symptom | Fix |
|---|---|
| `kubectl` points to wrong cluster | `aws eks update-kubeconfig --name EKS-boomi-runtime-cluster --region ap-east-1` |
| `You must be logged in to the server` | `aws sso login --profile default` then retry |
| `Forbidden` after auth succeeds | Fix EKS Access Entry or RBAC for your role |
| Namespace `mongodb` not found | Run Terraform prerequisites first |

### Terraform Issues

| Symptom | Fix |
|---|---|
| Plan asks for variables | Create `terraform.tfvars` from sample |
| Wrong cluster in plan | Fix `cluster_name` in tfvars |
| PostgreSQL subnet error | Ensure `private_subnet_ids` belong to `vpc_id` |
| State bucket not found | Check `TF_STATE_BUCKET` override; ensure bucket exists |
| Unexpected state migration prompt | Confirm this is first remote-state run before accepting |

### MongoDB Issues

| Symptom | Fix |
|---|---|
| PVC stays `Pending` | Check EBS CSI driver: `kubectl get csidriver ebs.csi.aws.com` |
| `cannot create secrets` | Fix RBAC: `kubectl auth can-i create secrets -n mongodb` |
| Escrow file invalid | Restore from backup or regenerate for fresh environment |
| Pod CrashLooping | Check logs: `kubectl -n mongodb logs <pod> -c mongod --tail=60` |
| Wrong ServiceAccount | Run `scripts/verify-dev-identity.sh` to identify mismatch |
| Verification fails during rolling reconcile | Wait for rollout completion: `kubectl -n mongodb rollout status statefulset/psmdb-rs0 --timeout=300s`, then re-run `scripts/verify-platform-health.sh` |
| Replica set auth/health check intermittently fails right after clean rebuild | Wait for all three mongod pods to be Ready and CR status to stabilize, then re-run verification |
| Repeated cert-manager re-issuance (`psmdb-ssl*` revisions climbing rapidly) with continuous Mongo pod rotation | Keep `psmdb-ssl` and `psmdb-ssl-internal` operator-managed only; do not define duplicate `Certificate` resources in `k8s/base/certificates.yaml` |
| `run-audit-telemetry-test.sh` pod exits OOMKilled | Re-run with updated script defaults; if still constrained, raise pod memory limit in `scripts/run-audit-telemetry-test.sh` |
| `run-audit-telemetry-test.sh` fails with `not primary`, `not authorized`, or `MongoServerSelectionError ... connection <monitor> ... closed` | Use the updated script flow (rollout gate + replicaSet URI + database-admin creds + mounted internal TLS cert); if failures persist, confirm `scripts/verify-platform-health.sh` is green first |

### SigNoz Issues

| Symptom | Fix |
|---|---|
| Pods Pending (PVC) | Check StorageClass and EBS CSI driver |
| HelmRelease not reconciling | Check Flux: `kubectl -n flux-system logs deployment/helm-controller --tail=30` |
| Dashboard unreachable | Verify port-forward: `kubectl -n signoz port-forward svc/signoz 3301:8080` |
| Telemetry send fails | Use frontend endpoint (`3301/v1/logs`), not collector directly |
| Namespace stuck `Terminating` after `scripts/destroy.sh signoz` | ClickHouse finalizer stuck; see [Recovery Procedures § Component-by-component teardown](../references/recovery-procedures.md#component-by-component-teardown) |
| `signoz-0` pod crash-loops right after adding root-user env vars: `failed to validate config "user"` | Root-user password doesn't meet policy (12+ chars, upper/lower/digit/symbol from `~!@#$%^&*()_+`-={}\|[]\:"<>?,./`, no other characters). Delete and re-run `scripts/create-signoz-root-user-secret.sh` (its generator already satisfies this). |
| `bash scripts/provision.sh signoz-observability` fails with `Secret 'signoz-api-key' not found` | This should self-heal automatically (the script bootstraps it via headless browser). If it still fails, ensure `playwright` is installed (`python3 -m pip install playwright && python3 -m playwright install chromium`) and that `scripts/create-signoz-root-user-secret.sh` + `scripts/provision.sh signoz` ran first. |
| `bash scripts/provision.sh signoz-observability` fails with `dial tcp 127.0.0.1:3301: connect: connection refused` | The local port-forward isn't running; start one with `scripts/open-signoz-ui.sh` (or pass `--endpoint` pointing at a reachable SigNoz URL). |
| `terraform apply` for `signoz-observability` reports `Error: Provider returned invalid result object after apply` | Known cosmetic limitation in the early-stage SigNoz Terraform provider (v0.0.14) on `signoz_alert` resources; the alert is usually already correctly created. Verify with `curl $SIGNOZ_ENDPOINT/api/v1/rules -H "SIGNOZ-API-KEY: $SIGNOZ_ACCESS_TOKEN"`, then `terraform untaint <resource>` if needed. See the Terraform root's [README.md](../../platform-prerequisites/terraform/signoz-observability/README.md). |

| Symptom | Fix |
|---|---|
| `kustomize build` fails | Fix manifest syntax in `k8s/overlays/dev` |
| Render succeeds but rg finds nothing | Check overlay patches and resource inclusion |
| `verify-dev-identity.sh` exits 1 | No pods yet — apply workload manifests first |
| `verify-dev-identity.sh` exits 2 | Pod uses wrong ServiceAccount — fix workload spec |

---

## Boomi Audit Writer: Credentials, Secrets, And Accounts

> **Audience:** Infra Operator/Admin. Boomi developers and process owners
> never handle any of this — the Groovy audit library resolves its MongoDB
> connection internally, and the
> [Boomi Integration Guide](boomi-integration-guide.md) deliberately
> contains no credential material. This section is the one place that
> documents how that connection is provisioned and troubleshot.

### MongoDB Account Mapping

Use the right account for the right task. Using the wrong one usually looks like a successful connection but fails with `Unauthorized` on `oms_audit` queries.

| Use Case | Account Source | Intended Privilege | Notes |
|---|---|---|---|
| Boomi audit write URI secret (`scripts/create-audit-writer-secret.sh`) | `MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD` in `psmdb-secrets` | Application data read/write | This is the account used to build `oms-audit-writer` secret. |
| In-cluster smoke writer (`scripts/run-audit-telemetry-test.sh`) | `MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD` in `psmdb-secrets` | Application data read/write | Writes and reads `oms_audit.auditlogs` for verification. |
| Human read-only querying (Compass/mongosh) | `audit_reader` created by `scripts/create-audit-reader.sh` | Read-only on `oms_audit` | Recommended for dashboards, audit review, and analyst access. |
| Cluster administration | `MONGODB_CLUSTER_ADMIN_USER` / `MONGODB_CLUSTER_ADMIN_PASSWORD` | Cluster management operations | Not the recommended account for app-level audit log queries. |

If Compass shell shows `authenticatedUsers: [{ user: 'clusterAdmin', db: 'admin' }]` and query fails on `oms_audit`, reconnect with `audit_reader` (or database-admin for operator-only debugging).

### Secret Strategy: Kubernetes Secrets (Recommended)

**Use Kubernetes Secrets** — they are free, already provisioned in the cluster, and the library supports them natively.

**Do NOT use AWS Secrets Manager** unless you have a specific requirement — it adds cost and complexity. The AWS path exists in the library for environments where kubectl access is not available.

Use AWS Secrets Manager path only when at least one is true:
1. The Boomi runtime cannot access kubeconfig/kubectl.
2. Organization policy requires centralized secret governance outside the cluster.
3. You need cross-cluster secret reuse managed by AWS controls.

| Secret Source | Cost | When to Use |
|---|---|---|
| K8s Secret (recommended) | Free | Default for all environments where kubectl is available |
| AWS Secrets Manager | ~$0.40/secret/month + $0.05/10K API calls | Only if Boomi runtime cannot access kubectl |
| Explicit URI (hardcoded) | Free | Local testing only — never in production |

**Create the K8s Secret** (one-time):

```bash
scripts/create-audit-writer-secret.sh
```

This creates `oms-audit-writer` in the `mongodb` namespace with a `mongoUri` key containing the full connection string.

The script uses database-admin credentials from `psmdb-secrets` (`MONGODB_DATABASE_ADMIN_USER` / `MONGODB_DATABASE_ADMIN_PASSWORD`), not `clusterAdmin`.

### Secret Formats

**Kubernetes Secret (recommended — free, already provisioned).** The library
reads base64-encoded values from Kubernetes Secrets via `kubectl`. Expected
structure:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oms-audit-writer
  namespace: mongodb
type: Opaque
data:
  mongoUri: <base64-encoded MongoDB URI>
```

`writeAuditLog` reads this secret automatically — no code needed. Override
only for advanced/test scenarios via environment variables:

```bash
export BOOMI_AUDIT_K8S_SECRET_NAME=oms-audit-writer
export BOOMI_AUDIT_K8S_NAMESPACE=mongodb
export BOOMI_AUDIT_K8S_SECRET_KEY=mongoUri
```

**AWS Secrets Manager (optional — NOT provisioned by default).** This path
is NOT provisioned by the current Terraform stack. Use it only if the Boomi
runtime cannot access `kubectl`; you would need to manually create the
secret in AWS Secrets Manager. The library accepts two formats:

Format 1 — plain URI string (the secret value is the MongoDB URI directly):
```
mongodb://user:password@host:27017/dbname?authSource=admin
```

Format 2 — JSON object with one of these keys (checked in order —
`mongoUri`, `mongodbUri`, `uri`, `MONGO_URI`):
```json
{
  "mongoUri": "mongodb://user:password@host:27017/dbname"
}
```

### Diagnostic Library Methods (Operator Use Only)

`BoomiAuditLogLibrary` exposes a few methods only an operator diagnosing
connection resolution should ever call — a Boomi process calling
`writeAuditLog` never needs them:

| Method | Purpose |
|---|---|
| `resolveMongoUri()` | Returns the URI `writeAuditLog` would use, resolved in order: `BOOMI_AUDIT_MONGO_URI` env var → `BOOMI_AUDIT_AWS_SECRET_ID` env var (AWS Secrets Manager) → K8s Secret `oms-audit-writer` in ns `mongodb` (overridable via `BOOMI_AUDIT_K8S_*`) → local dev fallback with a warning. |
| `redactUri(uri)` | Masks the username/password segment (`***:***`). **Never log a raw mongoUri** — always wrap with this. |
| `readKubernetesSecretValue(ns, name, key)` | Reads one base64-decoded value from a K8s Secret via kubectl. Throws if missing. |
| `readAwsSecretString(secretId, region)` | Reads a secret string (or decoded binary) from AWS Secrets Manager. |

Example (prints the resolved connection target, credentials masked):

```groovy
import boomi.BoomiAuditLogLibrary
println BoomiAuditLogLibrary.redactUri(BoomiAuditLogLibrary.resolveMongoUri())
```

### Testing Secret Resolution Paths

The local test harness accepts explicit secret-source flags for verifying
each resolution path:

```bash
# Via Kubernetes Secret
scripts/write-auditlog-and-telemetry.sh \
  --mongo-uri-k8s-secret oms-audit-writer \
  --mongo-uri-k8s-namespace mongodb \
  --mongo-uri-k8s-key mongoUri

# Via AWS Secrets Manager
scripts/write-auditlog-and-telemetry.sh \
  --mongo-uri-secret-id /oms/dev/mongodb/audit-writer \
  --aws-region ap-east-1
```

### Secret-Resolution Errors

| Error | Cause | Resolution |
|---|---|---|
| `Failed to read Kubernetes secret` | kubectl not available, wrong namespace, or missing RBAC | Verify kubectl access and secret exists, or set `BOOMI_AUDIT_MONGO_URI` directly |
| `Secret JSON does not contain a non-empty mongoUri/mongodbUri/uri/MONGO_URI key` | AWS secret payload format mismatch, or the key exists but is blank | Use one of: `mongoUri`, `mongodbUri`, `uri`, `MONGO_URI`, with a non-empty value |
| `Unable to resolve MongoDB connection: ...` | No MongoDB URI could be resolved from any source | Ensure the Kubernetes secret exists, or set `BOOMI_AUDIT_MONGO_URI` / `BOOMI_AUDIT_AWS_SECRET_ID` |
| `RuntimeException: Secret payload is empty` | Secret exists but has no value | Recreate the secret with valid content |
| `WARNING: ... falling back to local dev default` (stderr, not an exception) | No `BOOMI_AUDIT_MONGO_URI`/`BOOMI_AUDIT_AWS_SECRET_ID` env var and the Kubernetes secret could not be read | Ensure the Kubernetes secret exists in the target cluster, or set `BOOMI_AUDIT_MONGO_URI` explicitly in production |

### Read-Only Audit Querying (Operators / Analysts)

> Direct MongoDB access is an **operator/analyst** task, not a Boomi
> developer one. It needs `kubectl` access, an operator-created read-only
> account, and a MongoDB client on the workstation. Boomi Admins verify
> their audit writes through SigNoz and the automated smoke test's
> read-back instead — see
> [Boomi Integration Guide § Viewing Your Audit Records](boomi-integration-guide.md#viewing-your-audit-records).

**Step 1 — install a MongoDB client** (one-time, on the workstation doing
the querying). Two options:

| Client | Type | Get it | Best for |
|---|---|---|---|
| **MongoDB Compass** | Desktop GUI | <https://www.mongodb.com/products/compass> | Point-and-click browsing, filters, and exports — recommended for analysts and compliance reviewers |
| **`mongosh`** | Command-line shell | `brew install mongosh` (macOS) or the [MongoDB docs](https://www.mongodb.com/docs/mongodb-shell/install/) | Scripted/repeatable queries, terminal workflows |

**Step 2 — create a dedicated read-only user** (run once). A read-only user
means a query can never accidentally modify the immutable audit store:

```bash
scripts/create-audit-reader.sh --db oms_audit --username audit_reader
# or with a chosen password:
scripts/create-audit-reader.sh --db oms_audit --username audit_reader --password 'MySecurePass123!'
```

This outputs the connection string and password — store both securely and
hand the read-only credential to the analyst who needs it.

**Step 3 — connect** (dev; production uses cluster-internal DNS instead of a
port-forward):

```bash
# Terminal 1: expose MongoDB locally
kubectl -n mongodb port-forward svc/psmdb-rs0 27017:27017
```

- **Compass:** paste the connection string into the "New Connection" box:
  `mongodb://audit_reader:<password>@127.0.0.1:27017/oms_audit?authSource=oms_audit&directConnection=true`
- **mongosh:**
  ```bash
  mongosh 'mongodb://audit_reader:<password>@127.0.0.1:27017/oms_audit?authSource=oms_audit&directConnection=true'
  ```

**Step 4 — common queries** (database `oms_audit`, collection `auditlogs`):

```javascript
// Recent audit events
db.auditlogs.find().sort({ time: -1 }).limit(10)

// Events for a specific resource
db.auditlogs.find({ resource_id: 'ORD-2024-001' }).sort({ time: -1 })

// Events by action in a date range (time is a native BSON Date -> use new Date())
db.auditlogs.find({
  action: 'confirm',
  time: { $gte: new Date('2026-07-01T00:00:00Z'), $lte: new Date('2026-07-06T23:59:59Z') }
}).sort({ time: -1 })

// Everything sharing one trace_id (cross-reference with SigNoz)
db.auditlogs.find({ trace_id: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6' }).sort({ time: 1 })

// Count events by action
db.auditlogs.aggregate([
  { $group: { _id: '$action', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
```

Query action by verb and use `new Date(...)`
bounds — because `time` is stored as a native BSON Date, a plain string
comparison would silently match nothing.

---

## Remote State

Remote S3 state is always enabled. No local-state mode exists.

- Bucket: `sml-oms-dev-tfstate` (region `ap-east-1`)
- MongoDB key: `oms/dev/mongo.tfstate`
- PostgreSQL key: `oms/dev/pg.tfstate`

Override only if intentionally targeting a different bucket:

```bash
export TF_STATE_BUCKET="my-other-bucket"
export TF_STATE_REGION="us-east-1"
```

See [Architect Reference § State Strategy](architect-reference.md#state-backend-strategy) for the full state model.
