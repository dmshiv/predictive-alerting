output "endpoint_id"   { value = google_vertex_ai_endpoint.victim.id }
output "endpoint_name" { value = google_vertex_ai_endpoint.victim.name }
output "endpoint_full" { value = "projects/${var.project_id}/locations/${var.region}/endpoints/${google_vertex_ai_endpoint.victim.name}" }
