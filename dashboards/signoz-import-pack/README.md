# SigNoz Dashboard Import Pack (OMS Baseline)

These JSON files are import-ready SigNoz dashboard templates, vendored from the
official SigNoz dashboard template repository.

## Included dashboards

- `k8s-hostmetrics-overview.json`
  - Source: `hostmetrics/hostmetrics-k8s.json`
  - Purpose: Kubernetes node/host CPU, memory, disk, network, filesystem

- `mongodb-overview.json`
  - Source: `mongodb/mongodb.json`
  - Purpose: MongoDB replica-set health and performance metrics

- `aws-rds-postgresql-overview.json`
  - Source: `aws-rds/postgresql/overview.json`
  - Purpose: Aurora/RDS PostgreSQL high-level health and throughput

- `aws-rds-postgresql-db-metrics-overview.json`
  - Source: `aws-rds/postgresql/db-metrics-overview.json`
  - Purpose: Aurora/RDS PostgreSQL deeper DB metric views

- `opentelemetry-collector-pipeline-health.json`
  - Source: `opentelemetry-collector/opentelemetry-collector-dashboard.json`
  - Purpose: OTel Collector pipeline health (receivers/processors/exporters)

## Why import pack (instead of auto-provisioned dashboards)

Current OMS provisioning scripts deploy SigNoz and telemetry pipelines, but do
not apply custom dashboards as code. The fastest path is importing these JSON
files in SigNoz UI.

## Import steps

1. Open SigNoz UI:
   - `scripts/open-signoz-ui.sh`
2. In SigNoz: `Dashboards` -> `+ New dashboard` -> `Import JSON`.
3. Upload each JSON file from this folder.

## Upstream references

- Dashboard templates index: https://signoz.io/docs/dashboards/
- Import guide: https://signoz.io/docs/dashboards/import-dashboard/
- Template source repo: https://github.com/SigNoz/dashboards
