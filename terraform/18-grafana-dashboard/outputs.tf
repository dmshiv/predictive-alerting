output "dashboards_uploaded" {
  value = [for o in google_storage_bucket_object.dashboards : o.name]
}
output "datasources_url" {
  value = "gs://${data.terraform_remote_state.gcs.outputs.bucket_code}/${google_storage_bucket_object.datasources.name}"
}
