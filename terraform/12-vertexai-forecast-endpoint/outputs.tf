output "endpoint_id"   { value = google_vertex_ai_endpoint.forecaster.id }
output "endpoint_name" { value = google_vertex_ai_endpoint.forecaster.name }
output "endpoint_full" { value = "projects/${var.project_id}/locations/${var.region}/endpoints/${google_vertex_ai_endpoint.forecaster.name}" }
