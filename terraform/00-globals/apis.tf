# =============================================================================
# WHAT  : Enables every GCP API the rest of the project will need.
# WHY   : APIs are disabled by default; first apply elsewhere would fail.
# HOW   : One google_project_service per API. `disable_on_destroy = false`
#         so `terraform destroy` does NOT disable APIs (other workloads in the
#         project may still need them).
# JD KEYWORD: covers Vertex AI, Pub/Sub, BigQuery, GKE, Cloud Run, etc.
# =============================================================================

locals {
  required_apis = [
    "aiplatform.googleapis.com",        # Vertex AI (workbench, pipelines, endpoints, TB, registry)
    "artifactregistry.googleapis.com",  # Docker image registry
    "bigquery.googleapis.com",          # BigQuery
    "bigquerydatatransfer.googleapis.com",
    "cloudbuild.googleapis.com",        # Cloud Build
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",    # Cron jobs
    "compute.googleapis.com",           # VPC, Compute Engine, LB
    "container.googleapis.com",         # GKE
    "dns.googleapis.com",               # Cloud DNS
    "iam.googleapis.com",                # IAM
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",           # Cloud Logging
    "monitoring.googleapis.com",        # Cloud Monitoring
    "notebooks.googleapis.com",         # Vertex Workbench
    "pubsub.googleapis.com",            # Pub/Sub
    "run.googleapis.com",               # Cloud Run
    "secretmanager.googleapis.com",     # Secret Manager
    "serviceusage.googleapis.com",
    "storage.googleapis.com",           # Cloud Storage
    "generativelanguage.googleapis.com",# Gemini API
    "networkmanagement.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
