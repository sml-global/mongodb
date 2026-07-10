# Terraform: SigNoz Dashboards & Alerts (as Code)

## Purpose
This directory is a runnable Terraform root that manages SigNoz **dashboards**
and **alert rules** as code, using the official `SigNoz/signoz` Terraform
provider. It covers the full monitored surface: K8s node/host metrics,
MongoDB, PostgreSQL/Aurora, the OTel Collector pipelines themselves, and
Boomi app telemetry (audit writes).

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | 5 dashboards (K8s node metrics, K8s pod metrics, MongoDB, PostgreSQL/Aurora, OTel Collector pipeline health) + 5 alert rules. |
| Which script uses this root? | `bash scripts/provision-signoz-observability.sh` (or `bash scripts/provision.sh signoz-observability`). |
| Which default state key is used? | `oms/dev/signoz-observability.tfstate`. |
| Where do dashboard JSON templates come from? | `dashboards/signoz-import-pack/` (vendored SigNoz dashboard templates, loaded via `jsondecode(file(...))`). |
| Is the Service Account/API key bootstrap manual? | No -- fully automated via a headless-browser (Playwright) script, see below. |
| New to a term here (dashboard, alert, taint)? | [Glossary](../../../docs/references/glossary.md#signoz--observability-specific). |

## Prerequisites (one-time, fully automated)

1. SigNoz root user bootstrapped (no manual signup):
   ```bash
   bash scripts/create-signoz-root-user-secret.sh
   bash scripts/provision.sh signoz
   ```
2. A Service Account + API key: `scripts/provision-signoz-observability.sh`
   auto-invokes `scripts/bootstrap-signoz-service-account.sh` the first time
   it runs and the `signoz-api-key` Secret is missing. That script drives a
   headless Chromium browser (Playwright) through the exact same steps a
   human would use (Settings -> Service Accounts -> create -> assign
   `signoz-admin` role -> Keys tab -> create key), then stores the result as
   the `signoz-api-key` Secret automatically -- **no manual UI interaction
   required**, and no separate `open-signoz-ui.sh` port-forward needed either
   (both scripts manage their own temporary port-forward if none is already
   running on the target port).
   One-time setup for the headless browser itself:
   ```bash
   python3 -m pip install playwright && python3 -m playwright install chromium
   ```

## Standard Use

```bash
bash scripts/provision-signoz-observability.sh --auto-approve
```

This bootstraps the Service Account/API key if needed (see above), reads
`SIGNOZ_ACCESS_TOKEN` from the resulting `signoz-api-key` Secret, defaults
`SIGNOZ_ENDPOINT` to `http://127.0.0.1:3301` (auto-starting a temporary
port-forward if nothing is listening there), then runs `terraform fmt`,
`validate`, `plan`, `apply` -- fully unattended end to end.

## Known Provider Limitation (v0.0.14)

The `SigNoz/signoz` Terraform provider is early-stage (published within the
last week as of this writing). Two round-trip quirks were found and handled:

1. **`panel_map` inconsistency**: submitting an empty JSON object (`"{}"`)
   for `panel_map` causes the provider to report a "Provider produced
   inconsistent result" error on the next apply. Fixed by only setting
   `panel_map` when the source dashboard JSON's `panelMap` is non-empty
   (see `dashboards.tf`).
2. **`signoz_alert` computed-field drift**: `preferred_channels`,
   `broadcast_to_all`, `create_at`/`update_at`, and similar computed
   attributes do not stabilize between plan/apply cycles for alert
   resources. `terraform plan` will perpetually show benign in-place
   "updates" to these fields. This is cosmetic: the underlying alert
   definition (condition, thresholds, eval window) is correctly applied
   and does not drift. Re-running `terraform apply` is safe and idempotent
   -- it will not duplicate or misconfigure alerts.
3. **`signoz_alert` first-apply taint (auto-healed)**: on apply, the
   provider can return an unknown value for `preferred_channels`, causing
   `Error: Provider returned invalid result object after apply` and marking
   the resource tainted -- even though the alert was actually
   created/updated successfully in SigNoz. **`terraform untaint` alone does
   NOT reliably fix this**: an untainted resource is replaced (destroy +
   recreate) on the next apply, and that fresh creation can hit the exact
   same bug again, looping indefinitely rather than settling (observed
   directly -- 6+ untaint/reapply cycles in a row all failed the same way).
   `scripts/provision-signoz-observability.sh` handles this automatically
   by patching Terraform state directly instead: it clears the tainted
   status and sets `preferred_channels = []` (the value this repo always
   uses, since `alerts.tf` never sets a non-empty value) without going
   through the provider again at all, then re-plans and re-applies. This is
   fully automatic -- no manual `terraform untaint` is needed.

If you ever need to do this by hand: `terraform state pull > state.json`,
remove the `"status": "tainted"` key and set `"preferred_channels": []` for
the affected `signoz_alert` instance(s), bump `"serial"` by 1, then
`terraform state push state.json`.

## Boundaries
- Do not commit the SigNoz API key to git. It is only ever read from the
  `signoz-api-key` Kubernetes Secret via environment variables at apply time.
- Do not reuse this root's state key for the mongodb/postgresql roots.
