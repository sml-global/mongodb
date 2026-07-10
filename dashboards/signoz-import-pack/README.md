# SigNoz Dashboard Import Pack (OMS Baseline)

These JSON files are import-ready SigNoz dashboard templates, vendored from the
official SigNoz dashboard template repository.

New to "dashboard", "alert", or other SigNoz terms? See the
[Glossary § SigNoz / Observability Specific](../../docs/references/glossary.md#signoz--observability-specific).

## Read This First

Primary path in this repository is automated provisioning:
- `bash scripts/provision.sh signoz`
- `bash scripts/provision.sh signoz-observability --auto-approve`

That path creates dashboards and alerts as code. This folder exists as a
manual fallback and for one-off experiments.

Use this import pack only when:
1. You intentionally want a manual UI-only workflow.
2. You need to trial a dashboard JSON before promoting to Terraform.
3. Terraform access is temporarily unavailable.

## Included dashboards

- `kubernetes-node-metrics-overall.json`
  - Source: SigNoz dashboards `k8s-infra-metrics`
  - Purpose: Kubernetes node CPU, memory, filesystem, network

- `kubernetes-pod-metrics-overall.json`
  - Source: SigNoz dashboards `k8s-infra-metrics`
  - Purpose: Kubernetes pod CPU/memory and workload pressure

- `mongodb-overview.json`
  - Source: `mongodb/mongodb.json`
  - Purpose: MongoDB replica-set health and performance metrics

- `aws-rds-postgresql-overview.json`
  - Source: `aws-rds/postgresql/overview.json`
  - Purpose: Aurora/RDS PostgreSQL high-level health and throughput

- `aws-rds-postgresql-db-metrics-overview.json`
  - Source: `aws-rds/postgresql/db-metrics-overview.json`
  - Purpose: Aurora/RDS PostgreSQL deeper DB metric views (manual pack only)

- `opentelemetry-collector-pipeline-health.json`
  - Source: `opentelemetry-collector/opentelemetry-collector-dashboard.json`
  - Purpose: OTel Collector pipeline health (receivers/processors/exporters)

## Import steps (manual fallback)

1. Open SigNoz UI:
   - `scripts/open-signoz-ui.sh`
2. In SigNoz: `Dashboards` -> `+ New dashboard` -> `Import JSON`.
3. Upload each JSON file from this folder.

Note: this imports dashboards only. Baseline alerts are not created by this
manual flow.

## Upstream references

- Dashboard templates index: https://signoz.io/docs/dashboards/
- Import guide: https://signoz.io/docs/dashboards/import-dashboard/
- Template source repo: https://github.com/SigNoz/dashboards
