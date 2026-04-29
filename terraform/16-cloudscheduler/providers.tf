# =============================================================================
# WHAT  : Configures google + google-beta providers for this folder.
# WHY   : Each folder runs its own terraform; providers must be per-folder.
# HOW   : Inputs come from TF_VAR_* environment variables set by start.sh.
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
