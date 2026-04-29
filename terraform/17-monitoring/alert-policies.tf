# =============================================================================
# WHAT  : Alert policies for the most important failure modes.
# WHY   : Predictive alerting is for ML-specific issues; these alerts cover
#         classic infra failures (uptime, error rate, log severity).
# JD KEYWORD: SRE, SLOs, Cloud Monitoring
# =============================================================================

# Triage uptime alert
resource "google_monitoring_alert_policy" "triage_down" {
  display_name = "Sentinel: Triage down"
  combiner     = "OR"

  conditions {
    display_name = "Triage uptime check failed"

    condition_threshold {
      # NOTE: Filter intentionally omits check_id - we only run one uptime
      # check in this project (triage), so any failed uptime check IS triage.
      # GCP rejects resource.label.check_id and metric.label.check_id combos
      # for the uptime_url resource type with strict validation.
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
      duration        = "120s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }
}

# High error-log rate alert (any service)
resource "google_monitoring_alert_policy" "error_log_rate" {
  display_name = "Sentinel: High error-log rate"
  combiner     = "OR"

  conditions {
    display_name = "Error severity logs > 10/min"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/log_entry_count\" resource.type=\"cloud_run_revision\" metric.label.\"severity\"=\"ERROR\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }
}
