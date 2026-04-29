# =============================================================================
# WHAT  : Least-privilege role bindings per service account.
# WHY   : "Owner everywhere" is what causes prod incidents.
# HOW   : Map of (sa_key, list_of_roles) -> google_project_iam_member.
# JD KEYWORD: IAM, security
# =============================================================================

locals {
  role_bindings = {
    victim = [
      "roles/aiplatform.user",
      "roles/storage.objectViewer",
      "roles/pubsub.publisher",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    forecaster = [
      "roles/aiplatform.user",
      "roles/bigquery.dataViewer",
      "roles/bigquery.jobUser",
      "roles/storage.objectViewer",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    triage = [
      "roles/aiplatform.user",
      "roles/bigquery.dataEditor",
      "roles/bigquery.jobUser",
      "roles/pubsub.subscriber",
      "roles/secretmanager.secretAccessor",
      "roles/logging.viewer",
      "roles/logging.logWriter",
      "roles/monitoring.editor",
      "roles/run.invoker",
      "roles/aiplatform.modelUser",
    ]
    pipeline = [
      "roles/aiplatform.user",
      "roles/storage.objectAdmin",
      "roles/bigquery.dataEditor",
      "roles/bigquery.jobUser",
      "roles/artifactregistry.reader",
      "roles/logging.logWriter",
    ]
    traffic_gen = [
      "roles/pubsub.publisher",
      "roles/secretmanager.secretAccessor",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/storage.objectViewer",
    ]
    ingestion = [
      "roles/pubsub.subscriber",
      "roles/bigquery.dataEditor",
      "roles/bigquery.jobUser",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    grafana = [
      "roles/monitoring.viewer",
      "roles/bigquery.dataViewer",
      "roles/bigquery.jobUser",
      "roles/secretmanager.secretAccessor",
      "roles/logging.logWriter",
    ]
    scheduler = [
      "roles/aiplatform.user",
      "roles/run.invoker",
      "roles/cloudfunctions.invoker",
    ]
  }

  # Flatten into (sa_key, role) pairs for for_each
  flat_bindings = merge([
    for sa_key, roles in local.role_bindings : {
      for role in roles : "${sa_key}-${role}" => {
        sa_key = sa_key
        role   = role
      }
    }
  ]...)
}

resource "google_project_iam_member" "bindings" {
  for_each = local.flat_bindings
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.sa[each.value.sa_key].email}"
}
