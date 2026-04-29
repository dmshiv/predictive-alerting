output "warmup_job"  { value = google_cloud_scheduler_job.grafana_warmup.name }
output "health_job"  { value = google_cloud_scheduler_job.triage_health.name }
