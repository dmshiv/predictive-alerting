# =============================================================================
# WHAT  : Configure the kubernetes provider with our cluster's credentials.
# WHY   : So we can apply manifests in this same Terraform run.
# =============================================================================

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.autopilot.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate)
}
