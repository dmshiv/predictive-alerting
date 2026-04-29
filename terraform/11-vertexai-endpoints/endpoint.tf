# =============================================================================
# WHAT  : Empty Vertex AI Endpoint shell for AI #1.
# WHY   : Pre-create so the pipeline only has to deploy a model, not also
#         create the endpoint (slow + permissions juggling).
# JD KEYWORD: Vertex AI Endpoints
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "01-vpc/state" }
}

resource "google_vertex_ai_endpoint" "victim" {
  name         = "victim-recommender"
  display_name = "${local.name_prefix}-victim-recommender"
  description  = "AI #1 — multi-modal product recommender (NLP + CV + RecSys)"
  location     = var.region

  labels = {
    project = "sentinel-forecast"
    role    = "victim"
    ai_id   = "1"
  }
}
