# SigNoz Dashboards & Alerts (EA/Operator Quickstart)

Use this page to get baseline dashboards and alert rules for OMS monitoring
with as little manual GUI work as possible.

## What this gives you

- Kubernetes infrastructure visibility (node metrics + pod metrics dashboards)
- MongoDB observability dashboard
- PostgreSQL/Aurora CloudWatch-based dashboard
- OpenTelemetry collector pipeline-health dashboard
- 5 baseline alert rules: MongoDB no-data, PostgreSQL CPU high, K8s node CPU
  high, OTel Collector export failures, and Boomi app-telemetry no-data

Telemetry/data pipelines are provisioned by OMS scripts (see
[Architect Reference § Infrastructure And Database Monitoring](../guides/architect-reference.md#infrastructure-and-database-monitoring));
this page is about the dashboards/alerts layer on top of that data.

## Root Login Credentials

The SigNoz admin (root user) is created automatically at pod startup from a
Kubernetes Secret -- source of truth is the Secret, not any file:

```bash
kubectl -n signoz get secret signoz-root-user -o jsonpath='{.data.email}' | base64 -d; echo
kubectl -n signoz get secret signoz-root-user -o jsonpath='{.data.password}' | base64 -d; echo
```

For convenience, the same values are also copied into the gitignored
`.local-dev-user-passwords.txt` at the repo root when
`scripts/create-signoz-root-user-secret.sh` runs. If you ever rotate the
password (delete + recreate the Secret, then restart the `signoz-0` pod),
the Secret is always the current value -- treat the text file as a
convenience copy, not the source of truth.

## Is This Repeatable?

Yes. `scripts/provision-signoz-observability.sh` (invoked via
`bash scripts/provision.sh signoz-observability`) is a plain `terraform
apply` wrapper and is safe to re-run any number of times:

- Re-running it does **not** create duplicate dashboards or alerts --
  Terraform tracks each resource by ID in state (`oms/dev/signoz-observability.tfstate`
  in the shared S3 state bucket) and updates in place if the `.tf` definition
  changed, or does nothing if it didn't.
- Verified empirically: running it twice in a row produced the exact same
  5 dashboard IDs and 5 alert IDs both times, with `0 added, 0 destroyed`
  (only cosmetic in-place "changes" on a couple of alert fields -- see
  **Known Provider Limitation** in that Terraform root's
  [README.md](../../platform-prerequisites/terraform/signoz-observability/README.md)).
- It is **not** wired into `bash scripts/provision.sh all` or
  `bash scripts/provision.sh signoz` -- it is a separate, explicit scope you
  run yourself. It depends on the Service Account/API key existing, but that
  is now bootstrapped automatically (see below) rather than being a blocking
  manual prerequisite.
- If you edit `dashboards.tf` / `alerts.tf` and re-run, Terraform will update
  the existing dashboards/alerts in place rather than creating new ones.

## Option A (Recommended): Fully automated via Terraform

Dashboards and alerts are defined as code in
[platform-prerequisites/terraform/signoz-observability](../../platform-prerequisites/terraform/signoz-observability)
using the official `SigNoz/signoz` Terraform provider. This is reviewable,
version-controlled, and reproducible across environments -- re-running
`terraform apply` never requires clicking through the UI again.

**One-time prerequisite, fully automated (no manual UI interaction):**

1. Bootstrap the SigNoz root user (removes the manual "Sign Up" step):
   ```bash
   bash scripts/create-signoz-root-user-secret.sh
   bash scripts/provision.sh signoz
   ```
2. Install Playwright once (used to drive a headless browser for the
   Service Account/API key step -- SigNoz itself requires this step to
   exist through the UI or an authenticated API session; there is no
   documented headless *API* bootstrap for it, so this repo automates the
   UI flow instead of doing it by hand):
   ```bash
   python3 -m pip install playwright
   python3 -m playwright install chromium
   ```

**From then on, everything is one command:**

```bash
bash scripts/provision.sh signoz-observability --auto-approve
```

The first run automatically creates the `terraform-automation` Service
Account, assigns the `signoz-admin` role, generates an API key, and stores
it as the `signoz-api-key` Secret (via `scripts/bootstrap-signoz-service-account.sh`)
-- then applies all 5 dashboards + 5 alert rules via Terraform. Subsequent
runs skip the bootstrap step (the Secret already exists) and just apply.
See that Terraform root's
[README.md](../../platform-prerequisites/terraform/signoz-observability/README.md)
for documented, known cosmetic limitations in the early-stage SigNoz
Terraform provider (harmless computed-field drift on alert resources, and an
auto-healed first-apply taint bug).

## Option B: Manual JSON import (fallback / one-off)

If you only need a quick one-time look, or don't want to create a Service
Account, the same dashboard templates are vendored as plain JSON and can be
imported by hand.

### Prerequisites

- SigNoz is up and reachable
- You have a SigNoz user with Editor or Admin role
- Dashboard JSON pack exists in repo:
  `dashboards/signoz-import-pack/`

### Import in 2 minutes

1. Prepare and list the files:

```bash
scripts/prepare-signoz-dashboard-import.sh
```

2. Open SigNoz:

```bash
scripts/open-signoz-ui.sh
```

3. In SigNoz UI:
   - Go to `Dashboards`
   - Click `+ New dashboard`
   - Choose `Import JSON`
   - Upload each file from `dashboards/signoz-import-pack/`

Note: this path only imports dashboards, not alerts. Alerts still need to be
created by hand in the UI if you skip Option A.

## Included dashboard files

- `k8s-hostmetrics-overview.json`
- `mongodb-overview.json`
- `aws-rds-postgresql-overview.json`
- `aws-rds-postgresql-db-metrics-overview.json`
- `opentelemetry-collector-pipeline-health.json`

## Dashboards Created (Option A / Terraform)

| Terraform resource | Dashboard title | Covers |
|---|---|---|
| `signoz_dashboard.k8s_hostmetrics` | Host Metrics (k8s) | Node/pod CPU, memory, disk, network, filesystem |
| `signoz_dashboard.mongodb_overview` | Mongo overview | Replica-set connections, ops, replication, memory, cache |
| `signoz_dashboard.postgres_overview` | AWS RDS Postgres | Aurora writer CPU, IOPS, connections, replication lag, volume |
| `signoz_dashboard.otel_collector_pipeline_health` | OpenTelemetry Collector | Receiver/processor/exporter throughput and failures for all our OTel Collectors |

## Alerts Created (Option A / Terraform)

| Terraform resource | Alert name | Fires when |
|---|---|---|
| `signoz_alert.mongodb_no_data` | MongoDB replica set - no metrics received | `mongodb_connections_current` reports no data for 10 minutes |
| `signoz_alert.postgres_cpu_high` | PostgreSQL (Aurora writer) - CPU utilization high | Aurora writer CPU > 80% for 10 minutes |
| `signoz_alert.k8s_node_cpu_high` | K8s node - CPU utilization high | Any node's CPU > 85% for 15 minutes |
| `signoz_alert.otel_collector_export_failures` | OTel Collector - export failures | Any collector fails to export metric points |
| `signoz_alert.app_telemetry_no_data` | Boomi audit writes - no telemetry received | No `service.name = oms-audit-writer` logs received for 60 minutes |

All 5 alerts default to an empty notification-channel list (`var.notification_channels`)
since no Slack/webhook/email channel is configured in this dev environment yet --
they still show up and evaluate correctly in the **Alerts** tab, they just won't
notify anyone until a channel is wired up.

## Automation summary

| Layer | Automated? |
|---|---|
| SigNoz + telemetry pipelines (K8s, MongoDB, PostgreSQL, app) | Yes -- Terraform/GitOps/Helm |
| SigNoz admin account bootstrap | Yes -- root-user env vars, no UI signup |
| Service Account + API key creation | Yes -- headless browser (Playwright) script, auto-invoked on first run |
| Dashboards + alert rules | Yes -- Terraform (`signoz-observability` root), including auto-recovery from the provider's first-apply taint bug |

