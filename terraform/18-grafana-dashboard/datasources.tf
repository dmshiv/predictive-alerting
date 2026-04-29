# =============================================================================
# WHAT  : Uploads the Grafana datasources YAML.
# WHY   : Grafana provisioning auto-configures Cloud Monitoring + BigQuery
#         datasources at startup.
# =============================================================================

resource "google_storage_bucket_object" "datasources" {
  name    = "grafana/datasources.yaml"
  bucket  = data.terraform_remote_state.gcs.outputs.bucket_code
  content = <<-YAML
    apiVersion: 1
    datasources:
      - name: Cloud Monitoring
        type: stackdriver
        access: proxy
        jsonData:
          authenticationType: gce
          defaultProject: ${var.project_id}
        editable: false
      - name: BigQuery
        type: grafana-bigquery-datasource
        access: proxy
        jsonData:
          authenticationType: gce
          defaultProject: ${var.project_id}
        editable: false
  YAML
  content_type = "application/yaml"
}
