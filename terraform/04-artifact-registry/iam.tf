# Cloud Build pushes (so Cloud Build SA needs writer); workloads pull (reader).

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

# Cloud Build default SA needs writer
data "google_project" "p" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  repository = google_artifact_registry_repository.images.name
  location   = var.region
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.p.number}@cloudbuild.gserviceaccount.com"
}

# All workload SAs need reader
resource "google_artifact_registry_repository_iam_member" "workload_readers" {
  for_each   = data.terraform_remote_state.iam.outputs.sa_emails
  repository = google_artifact_registry_repository.images.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value}"
}
