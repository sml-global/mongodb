variable "notification_channels" {
  description = "SigNoz notification channel names to attach to alert thresholds. Leave empty until a channel (Slack/webhook/email) is configured in Settings -> Notification Channels."
  type        = list(string)
  default     = []
}

variable "postgres_writer_instance_identifier" {
  description = "Aurora PostgreSQL writer instance identifier (CloudWatch dbinstance_identifier dimension) monitored by the postgres-metrics-collector."
  type        = string
  default     = "pg18-dev-writer"
}

variable "audit_writer_service_name" {
  description = "OTLP service.name used by the production Boomi audit-writer library (distinct from the run-audit-telemetry-test.sh smoke-test service name)."
  type        = string
  default     = "oms-audit-writer"
}
