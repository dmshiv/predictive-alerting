# =============================================================================
# WHAT  : Uploads the Grafana dashboard JSON files into the code bucket.
# WHY   : So the Grafana container can fetch + provision them at boot.
# HOW   : One bucket object per JSON in src/dashboards/grafana/.
# =============================================================================

data "terraform_remote_state" "gcs" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "03-cloudstorage/state" }
}

locals {
  dashboards_dir = "${path.module}/../../src/dashboards/grafana"
  dashboard_files = fileset(local.dashboards_dir, "*.json")
}

resource "google_storage_bucket_object" "dashboards" {
  for_each = local.dashboard_files

  name    = "grafana/dashboards/${each.value}"
  bucket  = data.terraform_remote_state.gcs.outputs.bucket_code
  source  = "${local.dashboards_dir}/${each.value}"
  content_type = "application/json"
}
