# =============================================================================
# WHAT  : Workload Identity bindings.
# WHY   : So a Kubernetes Service Account (KSA) in GKE can act as a GCP
#         Service Account (GSA) without mounting JSON key files.
# HOW   : Add roles/iam.workloadIdentityUser on the GSA for the KSA.
#         The actual KSA<->GSA annotation is set in 13-gke manifests.
# JD KEYWORD: IAM, GKE security
# =============================================================================

# NOTE: Workload Identity pool `PROJECT.svc.id.goog` only exists once a GKE
# cluster has been created with Workload Identity enabled (done in 13-gke).
# We therefore gate these bindings behind `enable_workload_identity_bindings`.
# After 13-gke applies, re-run 02-iam with `-var enable_workload_identity_bindings=true`
# (start.sh does this automatically on its second pass).

resource "google_service_account_iam_member" "wi_ingestion" {
  count              = var.enable_workload_identity_bindings ? 1 : 0
  service_account_id = google_service_account.sa["ingestion"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[sentinel/sentinel-ingestion]"
}

resource "google_service_account_iam_member" "wi_victim" {
  count              = var.enable_workload_identity_bindings ? 1 : 0
  service_account_id = google_service_account.sa["victim"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[sentinel/sentinel-victim]"
}

resource "google_service_account_iam_member" "wi_forecaster" {
  count              = var.enable_workload_identity_bindings ? 1 : 0
  service_account_id = google_service_account.sa["forecaster"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[sentinel/sentinel-forecaster]"
}
