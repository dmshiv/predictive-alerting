# Dataset-level IAM (pipeline writes everywhere; triage edits incidents; grafana reads all).

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

locals {
  emails = data.terraform_remote_state.iam.outputs.sa_emails
}

resource "google_bigquery_dataset_iam_member" "pipeline_editor" {
  for_each   = google_bigquery_dataset.ds
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.emails["pipeline"]}"
}

resource "google_bigquery_dataset_iam_member" "ingestion_editor" {
  dataset_id = google_bigquery_dataset.ds["features"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.emails["ingestion"]}"
}

resource "google_bigquery_dataset_iam_member" "triage_editor" {
  dataset_id = google_bigquery_dataset.ds["incidents"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.emails["triage"]}"
}

resource "google_bigquery_dataset_iam_member" "grafana_viewer" {
  for_each   = google_bigquery_dataset.ds
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${local.emails["grafana"]}"
}

resource "google_bigquery_dataset_iam_member" "forecaster_viewer" {
  for_each   = google_bigquery_dataset.ds
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${local.emails["forecaster"]}"
}
