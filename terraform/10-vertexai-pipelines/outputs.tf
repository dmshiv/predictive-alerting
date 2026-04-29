output "scheduler_forecaster_job" { value = google_cloud_scheduler_job.forecaster_retrain.name }
output "scheduler_victim_job"     { value = google_cloud_scheduler_job.victim_retrain.name }
