# =============================================================================
# WHAT  : Apply Kubernetes manifests for the namespace + ingestion pod.
# WHY   : So the telemetry pipeline starts running automatically.
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "02-iam/state" }
}

data "terraform_remote_state" "ar" {
  backend = "gcs"
  config = { bucket = var.tfstate_bucket, prefix = "04-artifact-registry/state" }
}

# Namespace
resource "kubernetes_namespace" "sentinel" {
  metadata { name = "sentinel" }
  depends_on = [google_container_cluster.autopilot]
}

# KSA for ingestion (annotated with GSA email -> workload identity)
resource "kubernetes_service_account" "ingestion" {
  metadata {
    name      = "sentinel-ingestion"
    namespace = kubernetes_namespace.sentinel.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = data.terraform_remote_state.iam.outputs.sa_email_ingestion
    }
  }
}

# KSA for victim (also workload-identity-bound)
resource "kubernetes_service_account" "victim" {
  metadata {
    name      = "sentinel-victim"
    namespace = kubernetes_namespace.sentinel.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = data.terraform_remote_state.iam.outputs.sa_email_victim
    }
  }
}

# KSA for forecaster (workload-identity-bound to forecaster GSA which has BQ roles).
# The forecast-detector pod runs as this KSA so it can read telemetry and write
# predictions back to BigQuery without mounting JSON keys.
resource "kubernetes_service_account" "forecaster" {
  metadata {
    name      = "sentinel-forecaster"
    namespace = kubernetes_namespace.sentinel.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = data.terraform_remote_state.iam.outputs.sa_email_forecaster
    }
  }
}

# Telemetry collector deployment (consumes Pub/Sub -> BigQuery)
resource "kubernetes_deployment" "ingestion" {
  metadata {
    name      = "telemetry-collector"
    namespace = kubernetes_namespace.sentinel.metadata[0].name
    labels    = { app = "telemetry-collector" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "telemetry-collector" } }
    template {
      metadata { labels = { app = "telemetry-collector" } }
      spec {
        service_account_name = kubernetes_service_account.ingestion.metadata[0].name
        container {
          name  = "collector"
          image = "${data.terraform_remote_state.ar.outputs.repo_url}/traffic-gen:latest"
          # Image is built and pushed by Cloud Build (docker/cloudbuild.yaml).
          # Falls back to a no-op if image missing — start.sh ensures it exists.

          env {
            name  = "GCP_PROJECT_ID"
            value = var.project_id
          }
          env {
            name  = "PUBSUB_SUBSCRIPTION"
            value = "${local.name_prefix}-ingestion-telemetry"
          }
          env {
            name  = "BQ_DATASET"
            value = "${replace(local.name_prefix, "-", "_")}_features"
          }
          env {
            name  = "BQ_TABLE"
            value = "telemetry_raw"
          }
          env {
            name  = "MODE"
            value = "collector"
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }

  # Don't wait if image isn't built yet — apply will succeed; pod will crashloop
  # until image exists, then heal.
  wait_for_rollout = false
}
