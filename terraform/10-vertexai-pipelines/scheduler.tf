# =============================================================================
# WHAT  : Cloud Scheduler job that triggers the forecaster retrain pipeline.
# WHY   : So AI #2 retrains every 6h without human intervention.
# HOW   : POSTs to AI Platform Pipelines REST API with OAuth.
# JD KEYWORD: Vertex AI Pipelines, Cloud Scheduler
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

data "terraform_remote_state" "gcs" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "03-cloudstorage/state" }
}

# Pipeline schedule for forecaster retrain (every 6h)
resource "google_cloud_scheduler_job" "forecaster_retrain" {
  name        = "${local.name_prefix}-forecaster-retrain"
  description = "Triggers Vertex AI Pipeline to retrain the forecaster every 6h"
  schedule    = "0 */6 * * *"
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-aiplatform.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/pipelineJobs"

    headers = {
      "Content-Type" = "application/json"
    }

    # Body is a JSON template; the actual pipeline JSON path is set by start.sh
    # which uploads a config-signed body. For now, an empty placeholder.
    body = base64encode(jsonencode({
      displayName     = "scheduled-forecaster-retrain"
      runtimeConfig = {
        gcsOutputDirectory = "gs://${data.terraform_remote_state.gcs.outputs.bucket_models}/pipeline_root"
      }
      templateUri = "gs://${data.terraform_remote_state.gcs.outputs.bucket_code}/pipelines/forecaster_train_pipeline.json"
      serviceAccount = data.terraform_remote_state.iam.outputs.sa_email_pipeline
    }))

    oauth_token {
      service_account_email = data.terraform_remote_state.iam.outputs.sa_email_scheduler
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count          = 1
    max_retry_duration   = "60s"
    min_backoff_duration = "10s"
    max_backoff_duration = "30s"
  }
}

# Nightly retrain for victim recommender (full retrain)
resource "google_cloud_scheduler_job" "victim_retrain" {
  name        = "${local.name_prefix}-victim-retrain"
  description = "Nightly retrain of AI #1 (victim recommender)"
  schedule    = "0 2 * * *"
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-aiplatform.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/pipelineJobs"

    headers = { "Content-Type" = "application/json" }

    body = base64encode(jsonencode({
      displayName    = "scheduled-victim-retrain"
      runtimeConfig  = {
        gcsOutputDirectory = "gs://${data.terraform_remote_state.gcs.outputs.bucket_models}/pipeline_root"
      }
      templateUri    = "gs://${data.terraform_remote_state.gcs.outputs.bucket_code}/pipelines/victim_train_pipeline.json"
      serviceAccount = data.terraform_remote_state.iam.outputs.sa_email_pipeline
    }))

    oauth_token {
      service_account_email = data.terraform_remote_state.iam.outputs.sa_email_scheduler
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

# Grant scheduler SA the aiplatform.user role (already done in 02-iam, this is belt-and-suspenders)
resource "google_project_iam_member" "scheduler_aiuser" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${data.terraform_remote_state.iam.outputs.sa_email_scheduler}"
}
