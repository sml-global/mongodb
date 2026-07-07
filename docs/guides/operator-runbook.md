# Operator Runbook

Step-by-step provisioning guide, safety gates, runbook commands, and troubleshooting.

**Who this is for:** Infra Operators who need to provision and maintain the OMS data layer.

**Pre-requisite:** Complete [Environment Setup](environment-setup.md) first.

**Related docs:**
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
bash scripts/provision.sh all
scripts/bootstrap-dev-secrets.sh
scripts/create-audit-writer-secret.sh
scripts/validate-dev-render.sh

# Verify
scripts/verify-platform-health.sh
```

This shortcut does not replace plan review. Stop before apply if the generated plan does not match the intended change.

---

## Provisioning Choices

| Goal | When To Use It | Command |
|---|---|---|
| Full baseline | First-time setup or convergence check | `bash scripts/provision.sh all` |
| MongoDB only | MongoDB updates without touching PostgreSQL | `bash scripts/provision.sh mongodb` |
| PostgreSQL only | PostgreSQL updates without touching MongoDB | `bash scripts/provision.sh pg` |
| SigNoz (telemetry) | Install or update the telemetry stack | `bash scripts/provision.sh signoz` |

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

Expected: SigNoz pods running in namespace `signoz`.

> **Security:** The ClickHouse password in `gitops/signoz/base/helmreleases.yaml` is set to a placeholder (`CHANGE_ME_BEFORE_PRODUCTION`). Replace it with a real password before deploying to any shared or production environment.

### Step 7A: Bootstrap the SigNoz Admin Account (Automated, No Manual Signup)

This environment uses SigNoz's **root user** feature (v0.112.0+) so the admin
account is created automatically at pod startup -- nobody needs to race to be
"first to sign up". Run this **before** Step 7 on a fresh environment (or
before restarting `signoz-0` if SigNoz is already up):

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
   - Boomi Admin: **Editor**
   - Enterprise Architect: **Viewer**
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
| `bash scripts/provision.sh signoz-observability --auto-approve` | Apply dashboards + alert rules as code | After SigNoz is up and the one-time API key Secret exists |
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
