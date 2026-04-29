# =============================================================================
# WHAT  : Docker repository for our 4 container images.
# WHY   : Centralized, versioned, vulnerability-scanned image storage.
# JD KEYWORD: Artifact Registry, Docker
# =============================================================================

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "sentinel-images"
  description   = "Docker images for Sentinel-Forecast (victim, forecaster, triage, traffic-gen, grafana)"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged-7d"
    action = "DELETE"
    condition {
      tag_state    = "UNTAGGED"
      older_than   = "604800s"  # 7 days
    }
  }
}
