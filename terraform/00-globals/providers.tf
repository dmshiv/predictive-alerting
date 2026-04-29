# =============================================================================
# WHAT  : Configures the google + google-beta providers with project & region.
# WHY   : Every resource needs to know which GCP project to land in.
# HOW   : `project` and `region` come from variables, which are populated by
#         start.sh from your .env file (TF_VAR_project_id, TF_VAR_region).
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
