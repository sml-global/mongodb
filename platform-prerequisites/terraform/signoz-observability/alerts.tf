# Baseline alert rules for infra + app telemetry, defined as code via the
# official SigNoz Terraform provider. Covers every signal this platform now
# ships: MongoDB, PostgreSQL/Aurora, K8s nodes, the OTel Collector pipelines
# themselves, and the Boomi app-telemetry (audit writer) log stream.
#
# `var.notification_channels` defaults to an empty list so these alerts can be
# created before any Slack/webhook/email notification channel is configured.
# Wire up a channel later (Settings -> Notification Channels) and set the
# variable -- no changes to the alert definitions below are needed.

resource "signoz_alert" "mongodb_no_data" {
  alert      = "MongoDB replica set - no metrics received"
  alert_type = "METRIC_BASED_ALERT"
  severity   = "critical"
  version    = "v5"

  schema_version = "v2alpha1"

  condition = jsonencode({
    compositeQuery = {
      queries = [
        {
          type = "builder_query"
          spec = {
            name         = "A"
            stepInterval = 60
            signal       = "metrics"
            source       = ""
            aggregations = [
              {
                metricName       = "mongodb_connections_current"
                temporality      = "unspecified"
                timeAggregation  = "avg"
                spaceAggregation = "avg"
              }
            ]
            filter = {
              expression = ""
            }
            having = {
              expression = ""
            }
          }
        }
      ]
      panelType = "graph"
      queryType = "builder"
    }
    selectedQueryName = "A"
    thresholds = {
      kind = "basic"
      spec = [
        {
          name           = "critical"
          target         = 0
          targetUnit     = ""
          recoveryTarget = null
          matchType      = "1"
          op             = "3"
          channels       = var.notification_channels
        }
      ]
    }
  })

  description = "The mongodb-metrics-collector has not reported connection metrics for 10 minutes. The replica set may be unreachable or the collector may be down."
  summary     = "MongoDB metrics collector: no data"
  eval_window = "10m0s"
  frequency   = "1m0s"
  disabled    = false
  rule_type   = "threshold_rule"

  evaluation = jsonencode({
    kind = "rolling"
    spec = {
      evalWindow = "10m0s"
      frequency  = "1m0s"
    }
  })

  notification_settings = {
    renotify = {
      interval     = "30m0s"
      alert_states = ["nodata", "firing"]
      enabled      = true
    }
    group_by   = []
    use_policy = true
  }

  labels = {
    team      = "platform"
    component = "mongodb"
  }
}

resource "signoz_alert" "postgres_cpu_high" {
  alert      = "PostgreSQL (Aurora writer) - CPU utilization high"
  alert_type = "METRIC_BASED_ALERT"
  severity   = "warning"
  version    = "v5"

  schema_version = "v2alpha1"

  condition = jsonencode({
    compositeQuery = {
      queries = [
        {
          type = "builder_query"
          spec = {
            name         = "A"
            stepInterval = 60
            signal       = "metrics"
            source       = ""
            aggregations = [
              {
                metricName       = "aws_rds_cpuutilization_average"
                temporality      = "unspecified"
                timeAggregation  = "avg"
                spaceAggregation = "avg"
              }
            ]
            filter = {
              expression = "dbinstance_identifier = '${var.postgres_writer_instance_identifier}'"
            }
            having = {
              expression = ""
            }
          }
        }
      ]
      panelType = "graph"
      queryType = "builder"
    }
    selectedQueryName = "A"
    thresholds = {
      kind = "basic"
      spec = [
        {
          name           = "warning"
          target         = 80
          targetUnit     = "percent"
          recoveryTarget = null
          matchType      = "1"
          op             = "1"
          channels       = var.notification_channels
        }
      ]
    }
  })

  description = "Aurora writer instance ${var.postgres_writer_instance_identifier} CPU utilization has been above 80% for 10 minutes (current: {{$value}}, threshold: {{$threshold}})."
  summary     = "PostgreSQL writer CPU high"
  eval_window = "10m0s"
  frequency   = "5m0s"
  disabled    = false
  rule_type   = "threshold_rule"

  evaluation = jsonencode({
    kind = "rolling"
    spec = {
      evalWindow = "10m0s"
      frequency  = "5m0s"
    }
  })

  notification_settings = {
    renotify = {
      interval     = "30m0s"
      alert_states = ["firing"]
      enabled      = true
    }
    group_by   = []
    use_policy = true
  }

  labels = {
    team      = "platform"
    component = "postgresql"
  }
}

resource "signoz_alert" "k8s_node_cpu_high" {
  alert      = "K8s node - CPU utilization high"
  alert_type = "METRIC_BASED_ALERT"
  severity   = "warning"
  version    = "v5"

  schema_version = "v2alpha1"

  condition = jsonencode({
    compositeQuery = {
      queries = [
        {
          type = "builder_query"
          spec = {
            name         = "A"
            stepInterval = 60
            signal       = "metrics"
            source       = ""
            aggregations = [
              {
                metricName       = "k8s_node_cpu_utilization"
                temporality      = "unspecified"
                timeAggregation  = "avg"
                spaceAggregation = "avg"
              }
            ]
            filter = {
              expression = ""
            }
            having = {
              expression = ""
            }
            groupBy = [
              { name = "k8s_node_name" }
            ]
          }
        }
      ]
      panelType = "graph"
      queryType = "builder"
    }
    selectedQueryName = "A"
    thresholds = {
      kind = "basic"
      spec = [
        {
          name           = "warning"
          target         = 85
          targetUnit     = "percent"
          recoveryTarget = null
          matchType      = "1"
          op             = "1"
          channels       = var.notification_channels
        }
      ]
    }
  })

  description = "A Kubernetes node's CPU utilization has been above 85% for 15 minutes (current: {{$value}}, threshold: {{$threshold}})."
  summary     = "K8s node CPU high"
  eval_window = "15m0s"
  frequency   = "5m0s"
  disabled    = false
  rule_type   = "threshold_rule"

  evaluation = jsonencode({
    kind = "rolling"
    spec = {
      evalWindow = "15m0s"
      frequency  = "5m0s"
    }
  })

  notification_settings = {
    renotify = {
      interval     = "30m0s"
      alert_states = ["firing"]
      enabled      = true
    }
    group_by   = ["k8s_node_name"]
    use_policy = true
  }

  labels = {
    team      = "platform"
    component = "kubernetes"
  }
}

resource "signoz_alert" "otel_collector_export_failures" {
  alert      = "OTel Collector - export failures"
  alert_type = "METRIC_BASED_ALERT"
  severity   = "warning"
  version    = "v5"

  schema_version = "v2alpha1"

  condition = jsonencode({
    compositeQuery = {
      queries = [
        {
          type = "builder_query"
          spec = {
            name         = "A"
            stepInterval = 60
            signal       = "metrics"
            source       = ""
            aggregations = [
              {
                metricName       = "otelcol_exporter_send_failed_metric_points"
                temporality      = "cumulative"
                timeAggregation  = "rate"
                spaceAggregation = "sum"
              }
            ]
            filter = {
              expression = ""
            }
            having = {
              expression = ""
            }
          }
        }
      ]
      panelType = "graph"
      queryType = "builder"
    }
    selectedQueryName = "A"
    thresholds = {
      kind = "basic"
      spec = [
        {
          name           = "warning"
          target         = 0
          targetUnit     = ""
          recoveryTarget = null
          matchType      = "1"
          op             = "1"
          channels       = var.notification_channels
        }
      ]
    }
  })

  description = "One of our OTel Collectors (mongodb-metrics-collector, postgres-metrics-collector, or k8s-infra) is failing to export metric points to signoz-otel-collector."
  summary     = "OTel Collector export failures detected"
  eval_window = "10m0s"
  frequency   = "5m0s"
  disabled    = false
  rule_type   = "threshold_rule"

  evaluation = jsonencode({
    kind = "rolling"
    spec = {
      evalWindow = "10m0s"
      frequency  = "5m0s"
    }
  })

  notification_settings = {
    renotify = {
      interval     = "30m0s"
      alert_states = ["firing"]
      enabled      = true
    }
    group_by   = []
    use_policy = true
  }

  labels = {
    team      = "platform"
    component = "otel-collector"
  }
}

resource "signoz_alert" "app_telemetry_no_data" {
  alert      = "Boomi audit writes - no telemetry received"
  alert_type = "LOGS_BASED_ALERT"
  severity   = "critical"
  version    = "v5"

  schema_version = "v2alpha1"

  condition = jsonencode({
    compositeQuery = {
      queries = [
        {
          type = "builder_query"
          spec = {
            name         = "A"
            stepInterval = 60
            signal       = "logs"
            source       = ""
            aggregations = [
              {
                expression = "count()"
              }
            ]
            filter = {
              expression = "service.name = '${var.audit_writer_service_name}'"
            }
            having = {
              expression = ""
            }
          }
        }
      ]
      panelType = "graph"
      queryType = "builder"
    }
    selectedQueryName = "A"
    thresholds = {
      kind = "basic"
      spec = [
        {
          name           = "critical"
          target         = 0
          targetUnit     = ""
          recoveryTarget = null
          matchType      = "1"
          op             = "3"
          channels       = var.notification_channels
        }
      ]
    }
  })

  description = "No audit-log/telemetry events with service.name = '${var.audit_writer_service_name}' were received in the last hour. The Boomi audit-writer integration may have stopped sending telemetry."
  summary     = "No Boomi app telemetry received"
  eval_window = "60m0s"
  frequency   = "5m0s"
  disabled    = false
  rule_type   = "threshold_rule"

  evaluation = jsonencode({
    kind = "rolling"
    spec = {
      evalWindow = "60m0s"
      frequency  = "5m0s"
    }
  })

  notification_settings = {
    renotify = {
      interval     = "60m0s"
      alert_states = ["nodata", "firing"]
      enabled      = true
    }
    group_by   = []
    use_policy = true
  }

  labels = {
    team      = "platform"
    component = "app-telemetry"
  }
}
