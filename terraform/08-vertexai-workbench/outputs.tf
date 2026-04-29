output "workbench_name" { value = google_workbench_instance.wb.name }
output "workbench_url" {
  description = "Console URL to open JupyterLab"
  value       = "https://console.cloud.google.com/vertex-ai/workbench/instances?project=${var.project_id}"
}
