data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

locals { emails = data.terraform_remote_state.iam.outputs.sa_emails }

# Triage service reads gemini-api-key + slack-webhook + alert-email-target
resource "google_secret_manager_secret_iam_member" "triage_access" {
  for_each = google_secret_manager_secret.secrets
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.emails["triage"]}"
}

# Forecaster + grafana need secret-accessor on alert-email-target only
resource "google_secret_manager_secret_iam_member" "forecaster_email" {
  secret_id = google_secret_manager_secret.secrets["alert-email-target"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.emails["forecaster"]}"
}
