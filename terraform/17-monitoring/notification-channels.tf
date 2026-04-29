# =============================================================================
# WHAT  : Email notification channel (always on) + optional Slack via webhook.
# WHY   : Email always works; Slack is opt-in via setup_slack.sh.
# HOW   : The Slack channel is created only if alert_email is set (we don't
#         have a webhook yet at terraform-time, so Slack channel is skipped
#         in TF and configured by setup_slack.sh post-deploy.)
# =============================================================================

variable "alert_email" {
  description = "Email address for Cloud Monitoring alerts"
  type        = string
  default     = ""
}

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" ? 1 : 0
  display_name = "Sentinel-Forecast email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}
