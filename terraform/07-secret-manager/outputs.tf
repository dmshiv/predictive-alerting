output "secrets" {
  value = { for k, s in google_secret_manager_secret.secrets : k => s.secret_id }
}
output "secret_gemini_api_key"     { value = google_secret_manager_secret.secrets["gemini-api-key"].secret_id }
output "secret_slack_webhook"      { value = google_secret_manager_secret.secrets["slack-webhook"].secret_id }
output "secret_alert_email_target" { value = google_secret_manager_secret.secrets["alert-email-target"].secret_id }
