# =============================================================================
# WHAT  : One service account per workload.
# WHY   : Least privilege + clean audit logs ("who did what?").
# JD KEYWORD: IAM, security
# =============================================================================

locals {
  workloads = {
    victim       = "AI #1 serving (multi-modal recommender)"
    forecaster   = "AI #2 serving (time-series forecaster)"
    triage       = "Cloud Run triage service"
    pipeline     = "Vertex AI Pipelines runner"
    traffic_gen  = "Compute Engine load generator VM"
    ingestion    = "Pub/Sub -> BigQuery telemetry collector (GKE)"
    grafana      = "Grafana Cloud Run service"
    scheduler    = "Cloud Scheduler invocations"
  }
}

resource "google_service_account" "sa" {
  for_each     = local.workloads
  account_id   = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  display_name = "Sentinel · ${each.key}"
  description  = each.value
}
