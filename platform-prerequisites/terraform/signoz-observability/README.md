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

## Provider Version and Schema History

This root uses the `SigNoz/signoz` Terraform provider `~> 0.1.1` against
SigNoz app `v0.136.1` (see `gitops/signoz/base/helmreleases.yaml`). Both were
upgraded together (#122/#123) from provider `0.0.14`/SigNoz `v0.130.1`:

- **Alerts**: `signoz_rule` (typed, v2alpha1 rules API) replaced the
  deprecated `signoz_alert` (opaque `jsonencode(...)` blobs, v1 rules API)
  in #117/#119. `signoz_rule`'s schema is unchanged between provider `0.0.17`
  and `0.1.1` -- the schema itself was never the blocker. What blocked alert
  creation until this upgrade (#121) was that SigNoz `v0.130.1`'s `/api/v2/rules`
  endpoint didn't accept the provider's wire format at all
  (`unknown field "builder_query"` when the provider's own official
  test-fixture payload was sent directly). Upgrading the app resolved this;
  no further alerts.tf changes were needed once the platform-prerequisites
  is running against `v0.136.1`.
- **Dashboards**: `signoz_dashboard`'s schema was completely rewritten in
  provider `0.1.0`/`0.1.1` (a fully typed Perses-based `spec` tree replacing
  the old `jsonencode(layout)`/`jsonencode(widgets)`/`jsonencode(variables)`
  flat-attribute design), and requires SigNoz `>= v0.135.0` (the version
  that exposes the dashboards v2 API, `/api/v2/dashboards`). `dashboards.tf`
  was migrated using the provider's own `terraform plan -generate-config-out`
  workflow against the already-migrated live dashboards (import by ID, no
  dashboard recreated) -- see
  `SigNoz/terraform-provider-signoz`'s `docs/guides/v0.0.x-to-v0.1.0.md` for
  the full migration guide this followed. The `dashboards/signoz-import-pack/`
  vendored JSON templates (used by the old `jsondecode(file(...))` pattern)
  are no longer read by `dashboards.tf` -- the generated HCL is now the
  source of truth; the JSON pack remains only as historical/import
  reference material for anyone recreating a dashboard from scratch.

## Known Historical Provider Limitations (provider 0.0.14, `signoz_alert` -- no longer applicable)

The issues below applied only to the retired `signoz_alert` resource on
provider `0.0.14` and no longer apply to this root's current `signoz_rule`
resources. Kept here for historical context in case an older branch/tag is
consulted:

1. **`panel_map` inconsistency**: submitting an empty JSON object (`"{}"`)
   for `panel_map` caused the provider to report a "Provider produced
   inconsistent result" error on the next apply.
2. **`signoz_alert` computed-field drift**: `preferred_channels`,
   `broadcast_to_all`, `create_at`/`update_at`, and similar computed
   attributes did not stabilize between plan/apply cycles for alert
   resources.
3. **`signoz_alert` first-apply taint**: the provider could return an
   unknown value for `preferred_channels` on apply, causing
   `Error: Provider returned invalid result object after apply` and marking
   the resource tainted even though the alert was actually created.

## Boundaries
- Do not commit the SigNoz API key to git. It is only ever read from the
  `signoz-api-key` Kubernetes Secret via environment variables at apply time.
- Do not reuse this root's state key for the mongodb/postgresql roots.

