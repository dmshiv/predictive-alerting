# =============================================================================
# WHAT  : Uptime checks for triage + grafana.
# WHY   : Synthetic probe = TSE's first signal that something broke.
# =============================================================================

data "terraform_remote_state" "cr" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "15-cloudrun/state" }
}

# Triage health
resource "google_monitoring_uptime_check_config" "triage" {
  display_name = "${local.name_prefix}-triage-uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/healthz"
    port           = "443"
    use_ssl        = true
    validate_ssl   = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = replace(data.terraform_remote_state.cr.outputs.triage_url, "https://", "")
    }
  }
}

# Grafana health
resource "google_monitoring_uptime_check_config" "grafana" {
  display_name = "${local.name_prefix}-grafana-uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/api/health"
    port           = "443"
    use_ssl        = true
    validate_ssl   = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = replace(data.terraform_remote_state.cr.outputs.grafana_url, "https://", "")
    }
  }
}
