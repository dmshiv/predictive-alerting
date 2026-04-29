output "datasets" {
  value = { for k, ds in google_bigquery_dataset.ds : k => ds.dataset_id }
}
output "dataset_features"  { value = google_bigquery_dataset.ds["features"].dataset_id }
output "dataset_incidents" { value = google_bigquery_dataset.ds["incidents"].dataset_id }
output "dataset_audit"     { value = google_bigquery_dataset.ds["audit"].dataset_id }
output "dataset_billing"   { value = google_bigquery_dataset.ds["billing"].dataset_id }
output "telemetry_table"   { value = "${var.project_id}.${google_bigquery_dataset.ds["features"].dataset_id}.${google_bigquery_table.telemetry_raw.table_id}" }
output "incidents_table"   { value = "${var.project_id}.${google_bigquery_dataset.ds["incidents"].dataset_id}.${google_bigquery_table.incidents.table_id}" }
