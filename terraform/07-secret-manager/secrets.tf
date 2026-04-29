# =============================================================================
# WHAT  : Secret containers (no values yet — added by setup_*.sh scripts).
# JD KEYWORD: Secret Manager, security
# =============================================================================

locals {
  secret_ids = ["gemini-api-key", "slack-webhook", "alert-email-target"]
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(local.secret_ids)
  secret_id = "${local.name_prefix}-${each.value}"

  replication {
    auto {}
  }
}

# Optional: place a placeholder version so secret-accessor reads don't 404
# during early demos. Real values overwrite via `gcloud secrets versions add`.
resource "google_secret_manager_secret_version" "placeholder" {
  for_each    = google_secret_manager_secret.secrets
  secret      = each.value.id
  secret_data = "PLACEHOLDER_OVERWRITE_ME"
  enabled     = true
}
