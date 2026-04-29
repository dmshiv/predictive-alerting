# =============================================================================
# WHAT  : SA emails per workload (consumed by every downstream folder).
# =============================================================================
output "sa_emails" {
  value = { for k, sa in google_service_account.sa : k => sa.email }
  description = "Map of workload -> service account email"
}

# Convenience individual outputs (more ergonomic than [for x in y...])
output "sa_email_victim"      { value = google_service_account.sa["victim"].email }
output "sa_email_forecaster"  { value = google_service_account.sa["forecaster"].email }
output "sa_email_triage"      { value = google_service_account.sa["triage"].email }
output "sa_email_pipeline"    { value = google_service_account.sa["pipeline"].email }
output "sa_email_traffic_gen" { value = google_service_account.sa["traffic_gen"].email }
output "sa_email_ingestion"   { value = google_service_account.sa["ingestion"].email }
output "sa_email_grafana"     { value = google_service_account.sa["grafana"].email }
output "sa_email_scheduler"   { value = google_service_account.sa["scheduler"].email }
