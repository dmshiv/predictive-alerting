# =============================================================================
# WHAT  : Custom log-based metrics for things we care about.
# WHY   : Cloud Monitoring can alert on these like any other metric.
# =============================================================================

resource "google_logging_metric" "gemini_calls" {
  name        = "${local.name_prefix}_gemini_calls"
  description = "Counter for every Gemini API call from triage"
  filter      = "resource.type=\"cloud_run_revision\" jsonPayload.event=\"gemini_call\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "predictive_alerts" {
  name        = "${local.name_prefix}_predictive_alerts"
  description = "Counter for every predictive alert that fired"
  filter      = "resource.type=\"cloud_run_revision\" jsonPayload.event=\"predictive_alert\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
