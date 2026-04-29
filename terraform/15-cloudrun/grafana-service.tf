# =============================================================================
# WHAT  : Cloud Run service hosting Grafana with our dashboards baked in.
# WHY   : Cheap, public, auto-scaling. Way easier than running Grafana on a VM.
# =============================================================================

resource "google_cloud_run_v2_service" "grafana" {
  name     = "${local.name_prefix}-grafana"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = data.terraform_remote_state.iam.outputs.sa_email_grafana

    scaling {
      min_instance_count = 1   # always on; otherwise cold starts ruin the demo
      max_instance_count = 3
    }

    containers {
      image = "${data.terraform_remote_state.ar.outputs.repo_url}/grafana:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GF_AUTH_ANONYMOUS_ENABLED"
        value = "true"        # demo mode; flip off in prod
      }
      env {
        name  = "GF_AUTH_ANONYMOUS_ORG_ROLE"
        value = "Viewer"
      }
      env {
        name  = "GF_SECURITY_ADMIN_PASSWORD"
        value = "sentinel-demo"   # change for prod
      }

      ports { container_port = 3000 }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

# Public access for grafana (demo)
resource "google_cloud_run_v2_service_iam_member" "grafana_public" {
  location = var.region
  name     = google_cloud_run_v2_service.grafana.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
