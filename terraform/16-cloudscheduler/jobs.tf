# =============================================================================
# WHAT  : Cron jobs that touch the system regularly.
# JD KEYWORD: Cloud Scheduler
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

data "terraform_remote_state" "cr" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "15-cloudrun/state" }
}

# Daily warm-up ping for Grafana (keeps the dashboard hot before standups)
resource "google_cloud_scheduler_job" "grafana_warmup" {
  name        = "${local.name_prefix}-grafana-warmup"
  description = "Pings Grafana every 5 min so the dashboard is never cold"
  schedule    = "*/5 * * * *"
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "GET"
    uri         = "${data.terraform_remote_state.cr.outputs.grafana_url}/api/health"
  }
}

# Hourly smoke health check for triage (logs to Cloud Logging if it fails)
resource "google_cloud_scheduler_job" "triage_health" {
  name        = "${local.name_prefix}-triage-health"
  description = "Hourly health check for triage Cloud Run service"
  schedule    = "0 * * * *"
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "GET"
    uri         = "${data.terraform_remote_state.cr.outputs.triage_url}/healthz"

    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.sa_email_scheduler
      audience              = data.terraform_remote_state.cr.outputs.triage_url
    }
  }
}
