# =============================================================================
# WHAT  : Four BigQuery datasets (logical groupings of tables).
# WHY   : Separation of concerns + per-dataset access control.
# JD KEYWORD: BigQuery
# =============================================================================

locals {
  datasets = {
    features  = "Telemetry features streamed from Pub/Sub for the forecaster"
    incidents = "Predictive alert records with Gemini triage reports"
    audit     = "Cloud Audit Logs export"
    billing   = "Cloud Billing export (for cost dashboards)"
  }
}

resource "google_bigquery_dataset" "ds" {
  for_each   = local.datasets
  dataset_id = replace("${local.name_prefix}_${each.key}", "-", "_")
  location   = var.region
  description = each.value
  delete_contents_on_destroy = true   # demo project; safe to wipe
  default_table_expiration_ms = each.key == "features" ? 7776000000 : null  # 90d for features
}
