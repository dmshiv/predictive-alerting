output "triage_url"   { value = google_cloud_run_v2_service.triage.uri }
output "grafana_url"  { value = google_cloud_run_v2_service.grafana.uri }
output "triage_name"  { value = google_cloud_run_v2_service.triage.name }
output "grafana_name" { value = google_cloud_run_v2_service.grafana.name }
