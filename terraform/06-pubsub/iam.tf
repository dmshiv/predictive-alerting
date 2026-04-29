data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

locals { emails = data.terraform_remote_state.iam.outputs.sa_emails }

# Pub/Sub service agent needs publishing on dlq (for dead-letter to work)
data "google_project" "p" { project_id = var.project_id }

resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.dlq.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.p.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
