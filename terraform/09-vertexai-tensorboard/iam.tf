data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

# Pipeline SA writes; grafana SA reads
resource "google_project_iam_member" "tb_user_pipeline" {
  project = var.project_id
  role    = "roles/aiplatform.tensorboardWebAppUser"
  member  = "serviceAccount:${data.terraform_remote_state.iam.outputs.sa_email_pipeline}"
}
