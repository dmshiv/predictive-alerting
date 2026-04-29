# =============================================================================
# WHAT  : Cloud Run service hosting the triage orchestrator.
# WHY   : Receives Pub/Sub push messages on every predictive alert, calls
#         Gemini, recommends a runbook, optionally auto-remediates.
# JD KEYWORD: Cloud Run, FastAPI
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

data "terraform_remote_state" "ar" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "04-artifact-registry/state" }
}

data "terraform_remote_state" "bq" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "05-bigquery/state" }
}

data "terraform_remote_state" "ps" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "06-pubsub/state" }
}

data "terraform_remote_state" "sm" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "07-secret-manager/state" }
}

resource "google_cloud_run_v2_service" "triage" {
  name     = "${local.name_prefix}-triage"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"   # only Pub/Sub-reachable; tighten in prod

  template {
    service_account = data.terraform_remote_state.iam.outputs.sa_email_triage

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "${data.terraform_remote_state.ar.outputs.repo_url}/triage:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "BQ_INCIDENTS_TABLE"
        value = data.terraform_remote_state.bq.outputs.incidents_table
      }
      env {
        name  = "PUBSUB_INCIDENTS_TOPIC"
        value = data.terraform_remote_state.ps.outputs.topic_incidents
      }
      env {
        name  = "GEMINI_SECRET_NAME"
        value = data.terraform_remote_state.sm.outputs.secret_gemini_api_key
      }
      env {
        name  = "SLACK_WEBHOOK_SECRET_NAME"
        value = data.terraform_remote_state.sm.outputs.secret_slack_webhook
      }
      env {
        name  = "ALERT_EMAIL_SECRET_NAME"
        value = data.terraform_remote_state.sm.outputs.secret_alert_email_target
      }

      ports { container_port = 8080 }

      startup_probe {
        http_get { path = "/healthz" }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 5
      }

      liveness_probe {
        http_get { path = "/healthz" }
        period_seconds = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,   # image tag changes via Cloud Build, not TF
    ]
  }
}

# Allow Pub/Sub to invoke (push subscription will use this)
resource "google_cloud_run_v2_service_iam_member" "triage_invoker_pubsub" {
  location = var.region
  name     = google_cloud_run_v2_service.triage.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.p.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

data "google_project" "p" { project_id = var.project_id }

# Wire the incidents push subscription to the triage service
resource "google_pubsub_subscription" "triage_push" {
  name  = "${local.name_prefix}-triage-push"
  topic = data.terraform_remote_state.ps.outputs.topic_incidents

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.triage.uri}/alert"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.sa_email_triage
    }
  }

  ack_deadline_seconds = 60
  expiration_policy { ttl = "" }
}
