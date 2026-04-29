# =============================================================================
# WHAT  : Tables in the datasets.
# WHY   : Define schemas up front so streaming inserts work immediately.
# =============================================================================

# Telemetry raw events from Pub/Sub
resource "google_bigquery_table" "telemetry_raw" {
  dataset_id          = google_bigquery_dataset.ds["features"].dataset_id
  table_id            = "telemetry_raw"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "event_time"
  }

  clustering = ["endpoint_id", "metric_name"]

  schema = jsonencode([
    { name = "event_time",   type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "endpoint_id",  type = "STRING",    mode = "REQUIRED" },
    { name = "metric_name",  type = "STRING",    mode = "REQUIRED" },
    { name = "metric_value", type = "FLOAT64",   mode = "REQUIRED" },
    { name = "feature_stats",type = "JSON",      mode = "NULLABLE" },
    { name = "request_id",   type = "STRING",    mode = "NULLABLE" },
  ])
}

# Incident records
resource "google_bigquery_table" "incidents" {
  dataset_id          = google_bigquery_dataset.ds["incidents"].dataset_id
  table_id            = "incidents"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "fired_at"
  }

  schema = jsonencode([
    { name = "incident_id",     type = "STRING",    mode = "REQUIRED" },
    { name = "fired_at",        type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "predicted_breach_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "endpoint_id",     type = "STRING",    mode = "REQUIRED" },
    { name = "metric_name",     type = "STRING",    mode = "REQUIRED" },
    { name = "severity",        type = "STRING",    mode = "REQUIRED" },
    { name = "gemini_report",   type = "STRING",    mode = "NULLABLE" },
    { name = "runbook_id",      type = "STRING",    mode = "NULLABLE" },
    { name = "remediation",     type = "STRING",    mode = "NULLABLE" },
    { name = "resolved_at",     type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "feature_fingerprint", type = "JSON",  mode = "NULLABLE" },
  ])
}

# Runbook history (used by RecSys)
resource "google_bigquery_table" "runbook_history" {
  dataset_id          = google_bigquery_dataset.ds["incidents"].dataset_id
  table_id            = "runbook_history"
  deletion_protection = false

  schema = jsonencode([
    { name = "incident_id", type = "STRING",    mode = "REQUIRED" },
    { name = "runbook_id",  type = "STRING",    mode = "REQUIRED" },
    { name = "applied_at",  type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "success",     type = "BOOL",      mode = "REQUIRED" },
    { name = "duration_s",  type = "FLOAT64",   mode = "NULLABLE" },
  ])
}

# Predictions log (forecaster outputs, kept for retrospective accuracy)
resource "google_bigquery_table" "predictions" {
  dataset_id          = google_bigquery_dataset.ds["features"].dataset_id
  table_id            = "predictions"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "predicted_at"
  }

  schema = jsonencode([
    { name = "predicted_at",       type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "horizon_minutes",    type = "INT64",     mode = "REQUIRED" },
    { name = "metric_name",        type = "STRING",    mode = "REQUIRED" },
    { name = "predicted_value",    type = "FLOAT64",   mode = "REQUIRED" },
    { name = "lower_bound",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "upper_bound",        type = "FLOAT64",   mode = "NULLABLE" },
    { name = "actual_value",       type = "FLOAT64",   mode = "NULLABLE" },  # backfilled later
    { name = "model_version",      type = "STRING",    mode = "NULLABLE" },
  ])
}
