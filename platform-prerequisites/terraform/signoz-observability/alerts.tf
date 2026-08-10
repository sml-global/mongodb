# Baseline alert rules for infra + app telemetry, defined as code via the
# official SigNoz Terraform provider. Covers every signal this platform now
# ships: MongoDB, PostgreSQL/Aurora, K8s nodes, the OTel Collector pipelines
# themselves, and the Boomi app-telemetry (audit writer) log stream.
#
# Uses signoz_rule (the typed v2 rules API resource), not the deprecated
# signoz_alert -- see issue #117. signoz_rule has no schema-compatible
# in-place upgrade from signoz_alert (typed nested blocks vs. jsonencode
# blobs), so this migration replaces all 5 alert resources outright
# (destroy + create, new alert IDs) rather than importing old ones.
#
# `var.notification_channels` defaults to an empty list so these alerts can be
# created before any Slack/webhook/email notification channel is configured.
# Wire up a channel later (Settings -> Notification Channels) and set the
# variable -- no changes to the alert definitions below are needed.

resource "signoz_rule" "mongodb_no_data" {
  alert          = "MongoDB replica set - no metrics received"
  alert_type     = "METRIC_BASED_ALERT"
  schema_version = "v2alpha1"
  rule_type      = "threshold_rule"

  condition = {
    selected_query_name = "A"
    composite_query = {
      panel_type = "graph"
      query_type = "builder"
      queries = [
        {
          builder_query = {
            type = "builder_query"
            spec = {
              metrics = {
                name          = "A"
                step_interval = "60"
                signal        = "metrics"
                source        = ""
                aggregations = [
                  {
                    metric_name       = "mongodb_connections_current"
                    temporality       = "unspecified"
                    time_aggregation  = "avg"
                    space_aggregation = "avg"
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
          }
        }
      ]
    }
    thresholds = {
      basic = {
        kind = "basic"
        spec = [
          {
            name            = "critical"
            target          = 0
            target_unit     = ""
            recovery_target = null
            match_type      = "at_least_once"
            op              = "equal"
            channels        = var.notification_channels
          }
        ]
      }
    }
  }

  description = "The mongodb-metrics-collector has not reported connection metrics for 10 minutes. The replica set may be unreachable or the collector may be down."
  disabled    = false

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "10m0s"
        frequency   = "1m0s"
      }
    }
  }

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
    severity  = "critical"
  }
}

resource "signoz_rule" "postgres_cpu_high" {
  alert          = "PostgreSQL (Aurora writer) - CPU utilization high"
  alert_type     = "METRIC_BASED_ALERT"
  schema_version = "v2alpha1"
  rule_type      = "threshold_rule"

  condition = {
    selected_query_name = "A"
    composite_query = {
      panel_type = "graph"
      query_type = "builder"
      queries = [
        {
          builder_query = {
            type = "builder_query"
            spec = {
              metrics = {
                name          = "A"
                step_interval = "60"
                signal        = "metrics"
                source        = ""
                aggregations = [
                  {
                    metric_name       = "aws_rds_cpuutilization_average"
                    temporality       = "unspecified"
                    time_aggregation  = "avg"
                    space_aggregation = "avg"
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
          }
        }
      ]
    }
    thresholds = {
      basic = {
        kind = "basic"
        spec = [
          {
            name            = "warning"
            target          = 80
            target_unit     = "percent"
            recovery_target = null
            match_type      = "at_least_once"
            op              = "above"
            channels        = var.notification_channels
          }
        ]
      }
    }
  }

  description = "Aurora writer instance ${var.postgres_writer_instance_identifier} CPU utilization has been above 80% for 10 minutes (current: {{$value}}, threshold: {{$threshold}})."
  disabled    = false

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "10m0s"
        frequency   = "5m0s"
      }
    }
  }

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
    severity  = "warning"
  }
}

resource "signoz_rule" "k8s_node_cpu_high" {
  alert          = "K8s node - CPU utilization high"
  alert_type     = "METRIC_BASED_ALERT"
  schema_version = "v2alpha1"
  rule_type      = "threshold_rule"

  condition = {
    selected_query_name = "A"
    composite_query = {
      panel_type = "graph"
      query_type = "builder"
      queries = [
        {
          builder_query = {
            type = "builder_query"
            spec = {
              metrics = {
                name          = "A"
                step_interval = "60"
                signal        = "metrics"
                source        = ""
                aggregations = [
                  {
                    metric_name       = "k8s_node_cpu_utilization"
                    temporality       = "unspecified"
                    time_aggregation  = "avg"
                    space_aggregation = "avg"
                  }
                ]
                filter = {
                  expression = ""
                }
                having = {
                  expression = ""
                }
                group_by = [
                  { name = "k8s_node_name" }
                ]
              }
            }
          }
        }
      ]
    }
    thresholds = {
      basic = {
        kind = "basic"
        spec = [
          {
            name            = "warning"
            target          = 85
            target_unit     = "percent"
            recovery_target = null
            match_type      = "at_least_once"
            op              = "above"
            channels        = var.notification_channels
          }
        ]
      }
    }
  }

  description = "A Kubernetes node's CPU utilization has been above 85% for 15 minutes (current: {{$value}}, threshold: {{$threshold}})."
  disabled    = false

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "15m0s"
        frequency   = "5m0s"
      }
    }
  }

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
    severity  = "warning"
  }
}

resource "signoz_rule" "otel_collector_export_failures" {
  alert          = "OTel Collector - export failures"
  alert_type     = "METRIC_BASED_ALERT"
  schema_version = "v2alpha1"
  rule_type      = "threshold_rule"

  condition = {
    selected_query_name = "A"
    composite_query = {
      panel_type = "graph"
      query_type = "builder"
      queries = [
        {
          builder_query = {
            type = "builder_query"
            spec = {
              metrics = {
                name          = "A"
                step_interval = "60"
                signal        = "metrics"
                source        = ""
                aggregations = [
                  {
                    metric_name       = "otelcol_exporter_send_failed_metric_points"
                    temporality       = "cumulative"
                    time_aggregation  = "rate"
                    space_aggregation = "sum"
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
          }
        }
      ]
    }
    thresholds = {
      basic = {
        kind = "basic"
        spec = [
          {
            name            = "warning"
            target          = 0
            target_unit     = ""
            recovery_target = null
            match_type      = "at_least_once"
            op              = "above"
            channels        = var.notification_channels
          }
        ]
      }
    }
  }

  description = "One of our OTel Collectors (mongodb-metrics-collector, postgres-metrics-collector, or k8s-infra) is failing to export metric points to signoz-otel-collector."
  disabled    = false

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "10m0s"
        frequency   = "5m0s"
      }
    }
  }

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
    severity  = "warning"
  }
}

resource "signoz_rule" "app_telemetry_no_data" {
  alert          = "Boomi audit writes - no telemetry received"
  alert_type     = "LOGS_BASED_ALERT"
  schema_version = "v2alpha1"
  rule_type      = "threshold_rule"

  condition = {
    selected_query_name = "A"
    composite_query = {
      panel_type = "graph"
      query_type = "builder"
      queries = [
        {
          builder_query = {
            type = "builder_query"
            spec = {
              logs = {
                name          = "A"
                step_interval = "60"
                signal        = "logs"
                source        = ""
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
          }
        }
      ]
    }
    thresholds = {
      basic = {
        kind = "basic"
        spec = [
          {
            name            = "critical"
            target          = 0
            target_unit     = ""
            recovery_target = null
            match_type      = "at_least_once"
            op              = "equal"
            channels        = var.notification_channels
          }
        ]
      }
    }
  }

  description = "No audit-log/telemetry events with service.name = '${var.audit_writer_service_name}' were received in the last hour. The Boomi audit-writer integration may have stopped sending telemetry."
  disabled    = false

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "60m0s"
        frequency   = "5m0s"
      }
    }
  }

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
    severity  = "critical"
  }
}
