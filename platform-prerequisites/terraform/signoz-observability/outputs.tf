output "dashboard_ids" {
  description = "IDs of the dashboards managed by this root, keyed by resource name."
  value = {
    k8s_node_metrics               = signoz_dashboard.k8s_node_metrics.id
    k8s_pod_metrics                = signoz_dashboard.k8s_pod_metrics.id
    mongodb_overview               = signoz_dashboard.mongodb_overview.id
    postgres_overview              = signoz_dashboard.postgres_overview.id
    otel_collector_pipeline_health = signoz_dashboard.otel_collector_pipeline_health.id
  }
}

output "alert_ids" {
  description = "IDs of the alert rules managed by this root, keyed by resource name."
  value = {
    mongodb_no_data                = signoz_alert.mongodb_no_data.id
    postgres_cpu_high              = signoz_alert.postgres_cpu_high.id
    k8s_node_cpu_high              = signoz_alert.k8s_node_cpu_high.id
    otel_collector_export_failures = signoz_alert.otel_collector_export_failures.id
    app_telemetry_no_data          = signoz_alert.app_telemetry_no_data.id
  }
}
