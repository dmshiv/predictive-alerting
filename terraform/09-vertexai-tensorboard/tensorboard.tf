# =============================================================================
# WHAT  : Vertex AI TensorBoard instance.
# WHY   : Centralized training visualization across pipeline runs.
# JD KEYWORD: Vertex AI TensorBoard
# =============================================================================

resource "google_vertex_ai_tensorboard" "tb" {
  display_name = "${local.name_prefix}-tensorboard"
  description  = "Sentinel-Forecast training experiments"
  region       = var.region

  labels = {
    project = "sentinel-forecast"
  }
}
