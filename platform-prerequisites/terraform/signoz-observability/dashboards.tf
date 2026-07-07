# Dashboards defined as code, sourced from the vendored SigNoz dashboard
# template JSON pack in dashboards/signoz-import-pack/ (see that folder's
# README.md for provenance / upstream links). Loading the templates via
# jsondecode() + re-serializing with jsonencode() avoids hand-transcribing
# large dashboard JSON blobs into HCL.
locals {
  dashboard_pack_dir = "${path.module}/../../../dashboards/signoz-import-pack"

  k8s_node_dashboard_json       = jsondecode(file("${local.dashboard_pack_dir}/kubernetes-node-metrics-overall.json"))
  k8s_pod_dashboard_json        = jsondecode(file("${local.dashboard_pack_dir}/kubernetes-pod-metrics-overall.json"))
  mongodb_dashboard_json        = jsondecode(file("${local.dashboard_pack_dir}/mongodb-overview.json"))
  postgres_dashboard_json       = jsondecode(file("${local.dashboard_pack_dir}/aws-rds-postgresql-overview.json"))
  otel_collector_dashboard_json = jsondecode(file("${local.dashboard_pack_dir}/opentelemetry-collector-pipeline-health.json"))
}

# NOTE: the k8s-infra Helm chart (signoz-k8s-infra) emits metrics under the
# "k8s.node.*" / "k8s.pod.*" OTel semantic-convention names (e.g.
# k8s.node.cpu.usage, k8s.pod.memory.usage). The generic "hostmetrics"
# receiver dashboard template (system.cpu.*, system.memory.*) used previously
# queries a DIFFERENT metric naming scheme and always showed literal "0" for
# every panel — it was the wrong template for this deployment. These two
# "Kubernetes Node/Pod Metrics - Overall" templates from the SigNoz dashboards
# repo's k8s-infra-metrics/ folder match our actual data.
resource "signoz_dashboard" "k8s_node_metrics" {
  name                      = "kubernetes-node-metrics-overall"
  title                     = local.k8s_node_dashboard_json.title
  description               = local.k8s_node_dashboard_json.description
  version                   = local.k8s_node_dashboard_json.version
  tags                      = try(local.k8s_node_dashboard_json.tags, ["kubernetes", "node", "infrastructure"])
  uploaded_grafana          = try(local.k8s_node_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true

  layout    = jsonencode(local.k8s_node_dashboard_json.layout)
  widgets   = jsonencode(local.k8s_node_dashboard_json.widgets)
  variables = jsonencode(try(local.k8s_node_dashboard_json.variables, {}))
  # Only set panel_map when non-empty: the provider has a round-trip bug where
  # submitting "{}" comes back as null, which Terraform then flags as an
  # inconsistent apply result. Omitting it entirely for empty maps avoids that.
  panel_map = length(try(local.k8s_node_dashboard_json.panelMap, {})) > 0 ? jsonencode(local.k8s_node_dashboard_json.panelMap) : null
}

resource "signoz_dashboard" "k8s_pod_metrics" {
  name                      = "kubernetes-pod-metrics-overall"
  title                     = local.k8s_pod_dashboard_json.title
  description               = local.k8s_pod_dashboard_json.description
  version                   = local.k8s_pod_dashboard_json.version
  tags                      = try(local.k8s_pod_dashboard_json.tags, ["kubernetes", "pod", "infrastructure"])
  uploaded_grafana          = try(local.k8s_pod_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true

  layout    = jsonencode(local.k8s_pod_dashboard_json.layout)
  widgets   = jsonencode(local.k8s_pod_dashboard_json.widgets)
  variables = jsonencode(try(local.k8s_pod_dashboard_json.variables, {}))
  panel_map = length(try(local.k8s_pod_dashboard_json.panelMap, {})) > 0 ? jsonencode(local.k8s_pod_dashboard_json.panelMap) : null
}

resource "signoz_dashboard" "mongodb_overview" {
  name                      = try(local.mongodb_dashboard_json.name, "mongodb-overview")
  title                     = local.mongodb_dashboard_json.title
  description               = local.mongodb_dashboard_json.description
  version                   = local.mongodb_dashboard_json.version
  tags                      = try(local.mongodb_dashboard_json.tags, ["mongodb", "database"])
  uploaded_grafana          = try(local.mongodb_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true

  layout    = jsonencode(local.mongodb_dashboard_json.layout)
  widgets   = jsonencode(local.mongodb_dashboard_json.widgets)
  variables = jsonencode(try(local.mongodb_dashboard_json.variables, {}))
  panel_map = length(try(local.mongodb_dashboard_json.panelMap, {})) > 0 ? jsonencode(local.mongodb_dashboard_json.panelMap) : null
}

resource "signoz_dashboard" "postgres_overview" {
  name                      = "aws-rds-postgresql-overview"
  title                     = local.postgres_dashboard_json.title
  description               = local.postgres_dashboard_json.description
  version                   = local.postgres_dashboard_json.version
  tags                      = try(local.postgres_dashboard_json.tags, ["postgresql", "database", "aws"])
  uploaded_grafana          = try(local.postgres_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true

  layout    = jsonencode(local.postgres_dashboard_json.layout)
  widgets   = jsonencode(local.postgres_dashboard_json.widgets)
  variables = jsonencode(try(local.postgres_dashboard_json.variables, {}))
  panel_map = length(try(local.postgres_dashboard_json.panelMap, {})) > 0 ? jsonencode(local.postgres_dashboard_json.panelMap) : null
}

resource "signoz_dashboard" "otel_collector_pipeline_health" {
  name                      = "otel-collector-pipeline-health"
  title                     = local.otel_collector_dashboard_json.title
  description               = local.otel_collector_dashboard_json.description
  version                   = local.otel_collector_dashboard_json.version
  tags                      = try(local.otel_collector_dashboard_json.tags, ["opentelemetry", "collector"])
  uploaded_grafana          = try(local.otel_collector_dashboard_json.uploadedGrafana, false)
  collapsable_rows_migrated = true

  layout    = jsonencode(local.otel_collector_dashboard_json.layout)
  widgets   = jsonencode(local.otel_collector_dashboard_json.widgets)
  variables = jsonencode(try(local.otel_collector_dashboard_json.variables, {}))
  panel_map = length(local.otel_collector_dashboard_json.panelMap) > 0 ? jsonencode(local.otel_collector_dashboard_json.panelMap) : null
}
