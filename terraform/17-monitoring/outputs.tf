output "email_channel" { value = var.alert_email != "" ? google_monitoring_notification_channel.email[0].id : null }
output "dashboard_id"  { value = google_monitoring_dashboard.system.id }
output "uptime_triage" { value = google_monitoring_uptime_check_config.triage.uptime_check_id }
output "uptime_grafana"{ value = google_monitoring_uptime_check_config.grafana.uptime_check_id }
