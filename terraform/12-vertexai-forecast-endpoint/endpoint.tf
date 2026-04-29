# =============================================================================
# WHAT  : Empty endpoint shell for AI #2 (forecaster).
# JD KEYWORD: Vertex AI Endpoints
# =============================================================================

resource "google_vertex_ai_endpoint" "forecaster" {
  name         = "forecaster"
  display_name = "${local.name_prefix}-forecaster"
  description  = "AI #2 — time-series forecaster (predicts AI #1 vital signs 2h ahead)"
  location     = var.region

  labels = {
    project = "sentinel-forecast"
    role    = "forecaster"
    ai_id   = "2"
  }
}
