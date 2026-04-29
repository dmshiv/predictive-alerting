# =============================================================================
# WHAT  : 1-minute rollup view for fast dashboard queries.
# WHY   : Querying raw rows for a 24h dashboard is slow; pre-rolled is instant.
# =============================================================================

resource "google_bigquery_table" "telemetry_1m" {
  dataset_id          = google_bigquery_dataset.ds["features"].dataset_id
  table_id            = "telemetry_1m_rollup"
  deletion_protection = false

  view {
    use_legacy_sql = false
    query = <<-SQL
      SELECT
        TIMESTAMP_TRUNC(event_time, MINUTE) AS minute,
        endpoint_id,
        metric_name,
        AVG(metric_value)            AS avg_value,
        APPROX_QUANTILES(metric_value, 100)[OFFSET(50)] AS p50,
        APPROX_QUANTILES(metric_value, 100)[OFFSET(95)] AS p95,
        APPROX_QUANTILES(metric_value, 100)[OFFSET(99)] AS p99,
        COUNT(*)                     AS n_events
      FROM `${var.project_id}.${google_bigquery_dataset.ds["features"].dataset_id}.telemetry_raw`
      WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      GROUP BY minute, endpoint_id, metric_name
    SQL
  }
}
